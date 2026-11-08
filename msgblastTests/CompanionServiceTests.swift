import XCTest
@testable import msgblastCore

final class CompanionServiceTests: XCTestCase {
    private let alice = "+15550100001"
    private let bob = "test@example.invalid"
    private let day: TimeInterval = 86_400
    private var folder: URL!
    private var configURL: URL { folder.appendingPathComponent("companion.json") }
    private var clock: TestClock!
    private var tokens: FakeTokens!
    private var uplink: RecordingUplink!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("companion-service-\(UUID().uuidString)")
        clock = TestClock(Date(timeIntervalSince1970: 1_794_000_000))
        tokens = FakeTokens("test-token")
        uplink = RecordingUplink()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func configure(cursor: Int64?, url: URL? = URL(string: "https://uplink-test.invalid")) throws {
        try CompanionConfig(uplinkURL: url, deviceID: "mac-0000aaaa", paused: false, cursor: cursor).save(to: configURL)
    }

    private var savedCursor: Int64? { CompanionConfig.load(from: configURL).cursor }

    private func service(_ path: String, names: [String: String] = [:]) -> CompanionService {
        let uplink = self.uplink!, clock = self.clock!
        return CompanionService(databasePath: path, configURL: configURL, tokens: tokens, names: FakeNames(names),
                                makeUplink: { _, _ in uplink }, now: { clock.now })
    }

    private func directChat(_ f: CompanionFixture) throws -> Int64 {
        try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
    }

    func test_firstRunUplinksLastThreeDaysOnly() async throws {
        try configure(cursor: nil)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        let now = clock.now
        try f.addMessage(chats: [chat], text: "old", date: now - 5 * day, handle: alice)
        try f.addMessage(chats: [chat], text: "recent", date: now - 2 * day, handle: alice)
        try f.addMessage(chats: [chat], text: "newest", date: now - 1 * day, handle: alice)
        let s = service(f.url.path)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 1)
        XCTAssertEqual(uplink.batches[0].messages.map(\.rowid), [2, 3])
        XCTAssertTrue(uplink.batches[0].firstRun)
        XCTAssertEqual(savedCursor, 3)
        try f.addMessage(chats: [chat], text: "later", date: now, handle: alice)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 2)
        XCTAssertEqual(uplink.batches[1].messages.map(\.rowid), [4])
        XCTAssertFalse(uplink.batches[1].firstRun)
    }

    func test_cursorAdvancesOnlyOnAck() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<3 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        uplink.script([.failure(.retryable(503))])
        let status = await service(f.url.path).tick()
        XCTAssertEqual(status.state, .offline(retryIn: 5))
        XCTAssertEqual(savedCursor, 0)
    }

    func test_failedPostKeepsCursorAndReplaysSameRows() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<3 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        uplink.script([.failure(.retryable(503)), .failure(.retryable(nil))])
        let s = service(f.url.path)
        _ = await s.tick()
        clock.advance(1)
        let waiting = await s.tick()
        XCTAssertEqual(waiting.state, .offline(retryIn: 4))
        XCTAssertEqual(uplink.batches.count, 1, "no post inside the backoff window")
        clock.advance(4)
        let second = await s.tick()
        XCTAssertEqual(second.state, .offline(retryIn: 10), "backoff doubles")
        clock.advance(10)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 3)
        XCTAssertEqual(Set(uplink.batches.map { $0.messages.map(\.guid) }).count, 1, "every attempt replays the same rows")
        XCTAssertEqual(savedCursor, 3)
    }

    func test_backoffCapsAt300Seconds() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        try f.addMessage(chats: [try directChat(f)], text: "m", handle: alice)
        uplink.script(Array(repeating: .failure(.retryable(nil)), count: 9))
        let s = service(f.url.path)
        var delays: [TimeInterval] = []
        for _ in 0..<9 {
            if case .offline(let delay) = await s.tick().state { delays.append(delay); clock.advance(delay) }
        }
        XCTAssertEqual(delays, [5, 10, 20, 40, 80, 160, 300, 300, 300])
    }

    func test_ackBelowBatchCursorIsRespected() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<5 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        uplink.script([.success(UplinkAck(acceptedCursor: 3))])
        _ = await service(f.url.path).tick()
        XCTAssertEqual(savedCursor, 3)
    }

    func test_ackAboveBatchCursorIsClamped() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<2 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        uplink.script([.success(UplinkAck(acceptedCursor: 99))])
        _ = await service(f.url.path).tick()
        XCTAssertEqual(savedCursor, 2)
    }

    func test_orphanOnlyStretchAdvancesWithoutPost() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<2 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        let s = service(f.url.path)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 1)
        try f.addMessage(chats: [], text: "orphan", handle: alice)
        try f.addMessage(chats: [], text: "orphan", handle: alice)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 1)
        XCTAssertEqual(savedCursor, 4)
    }

    func test_backlogIsBatched() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        for _ in 0..<450 { try f.addMessage(chats: [chat], text: "m", date: clock.now, handle: alice) }
        let s = service(f.url.path)
        var cursors: [Int64?] = []
        for _ in 0..<3 { _ = await s.tick(); cursors.append(savedCursor) }
        XCTAssertEqual(uplink.batches.map(\.messages.count), [200, 200, 50])
        XCTAssertEqual(uplink.batches.map(\.cursor), [200, 400, 450])
        XCTAssertEqual(cursors, [200, 400, 450])
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 3, "caught up and nothing changed")
    }

    func test_ssnInAttributedBodyOnlyIsScrubbed() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        try f.addMessage(chats: [try directChat(f)],
                         attributedBody: AttributedBodyDecoderTests.archived("mine is 123-45-6789 ok"), handle: alice)
        _ = await service(f.url.path).tick()
        let text = try XCTUnwrap(uplink.batches.first?.messages.first?.text)
        XCTAssertEqual(text, "mine is [SSN removed] ok")
        XCTAssertNil(text.range(of: "6789"))
    }

    func test_skippedMessagesAreSentWithoutText() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        try f.addMessage(chats: [try directChat(f)], text: "Your verification code is 482913", handle: alice)
        _ = await service(f.url.path).tick()
        let message = try XCTUnwrap(uplink.batches.first?.messages.first)
        XCTAssertEqual(message.kind, .skipped)
        XCTAssertNil(message.text)
    }

    func test_unreadableDatabaseReportsPermission() async throws {
        try configure(cursor: 0)
        let missing = folder.appendingPathComponent("missing.db").path
        let status = await service(missing).tick()
        XCTAssertEqual(status.state, .noDatabaseAccess)
        XCTAssertTrue(uplink.batches.isEmpty)
        XCTAssertEqual(savedCursor, 0)
    }

    func test_pausedDoesNothing() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        try f.addMessage(chats: [try directChat(f)], text: "m", handle: alice)
        let s = service(f.url.path)
        let paused = await s.setPaused(true)
        XCTAssertEqual(paused.state, .paused)
        let ticked = await s.tick()
        XCTAssertEqual(ticked.state, .paused)
        XCTAssertTrue(uplink.batches.isEmpty)
        XCTAssertTrue(CompanionConfig.load(from: configURL).paused)
        let missing = service(folder.appendingPathComponent("missing.db").path)
        let pausedMissing = await missing.tick()
        XCTAssertEqual(pausedMissing.state, .paused, "paused is checked before the database is opened")
        _ = await s.setPaused(false)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 1)
    }

    func test_unauthorizedStops() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let chat = try directChat(f)
        try f.addMessage(chats: [chat], text: "m", handle: alice)
        uplink.script([.failure(.unauthorized)])
        let s = service(f.url.path)
        let stopped = await s.tick()
        guard case .stopped = stopped.state else { return XCTFail("got \(stopped.state)") }
        try f.addMessage(chats: [chat], text: "m", handle: alice)
        clock.advance(600)
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 1, "no posts while stopped")
        tokens.write("new-token")
        _ = await s.tick()
        XCTAssertEqual(uplink.batches.count, 2)
        XCTAssertEqual(savedCursor, 2)
    }

    func test_rejectedStopsWithoutMessageContent() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        try f.addMessage(chats: [try directChat(f)], text: "secret words", handle: alice)
        uplink.script([.failure(.rejected(422))])
        let status = await service(f.url.path).tick()
        guard case .stopped(let reason) = status.state else { return XCTFail("got \(status.state)") }
        XCTAssertTrue(reason.contains("422"), reason)
        XCTAssertFalse(reason.contains("secret") || reason.contains(alice), reason)
    }

    func test_namesAttached() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let group = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: "", handles: [alice, bob])
        try f.addMessage(chats: [group], text: "m", handle: bob)
        _ = await service(f.url.path, names: [alice: "Test Person"]).tick()
        let thread = try XCTUnwrap(uplink.batches.first?.threads.first)
        XCTAssertEqual(thread.kind, .group)
        XCTAssertNil(thread.displayName)
        XCTAssertEqual(thread.participants.first { $0.handle == alice }?.name, "Test Person")
        XCTAssertNil(thread.participants.first { $0.handle == bob }?.name)
    }

    func test_contactsDeniedGivesNullNames() async throws {
        try configure(cursor: 0)
        let f = try CompanionFixture()
        let group = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: nil, handles: [alice, bob])
        try f.addMessage(chats: [group], text: "m", handle: bob)
        _ = await service(f.url.path, names: [:]).tick()
        let thread = try XCTUnwrap(uplink.batches.first?.threads.first)
        XCTAssertEqual(thread.participants.count, 2)
        XCTAssertTrue(thread.participants.allSatisfy { $0.name == nil })
        XCTAssertNil(thread.displayName)
    }

    func test_notConfigured() async throws {
        try configure(cursor: 0, url: nil)
        let missing = folder.appendingPathComponent("missing.db").path
        let noURL = await service(missing).tick()
        XCTAssertEqual(noURL.state, .notConfigured)
        try configure(cursor: 0)
        tokens.write(nil)
        let noToken = await service(missing).tick()
        XCTAssertEqual(noToken.state, .notConfigured)
        XCTAssertTrue(uplink.batches.isEmpty)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

final class FakeTokens: CompanionTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(_ token: String?) { self.token = token }
    func read() -> String? { lock.lock(); defer { lock.unlock() }; return token }
    @discardableResult func write(_ token: String?) -> Bool { lock.lock(); self.token = token; lock.unlock(); return true }
}

struct FakeNames: CompanionNameResolving {
    let table: [String: String]
    init(_ table: [String: String]) { self.table = table }
    func names(for handles: [String]) async -> [String: String] { table.filter { handles.contains($0.key) } }
}

final class RecordingUplink: CompanionUplinking, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [UplinkBatch] = []
    private var queue: [Result<UplinkAck, UplinkError>] = []
    var batches: [UplinkBatch] { lock.lock(); defer { lock.unlock() }; return recorded }
    func script(_ responses: [Result<UplinkAck, UplinkError>]) { lock.lock(); queue = responses; lock.unlock() }
    func post(_ batch: UplinkBatch) async throws(UplinkError) -> UplinkAck {
        let next: Result<UplinkAck, UplinkError> = lock.withLock {
            recorded.append(batch)
            return queue.isEmpty ? .success(UplinkAck(acceptedCursor: batch.cursor)) : queue.removeFirst()
        }
        return try next.get()
    }
}

import XCTest
@testable import msgblastCore

final class CompanionSendLedgerTests: XCTestCase {
    private var folder: URL!
    private let t0 = Date(timeIntervalSince1970: 1_794_492_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("send-ledger-\(UUID().uuidString)")
            .appendingPathComponent("companion-sends")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func record(_ id: String = "snd-1", text: String = "See you at 6") -> SendRecord {
        SendRecord(sendID: id, threadGUID: "iMessage;-;+15555550100", textLength: text.count,
                   textSHA256: CompanionTextHash.of(text), baselineRowID: 42, createdAt: t0)
    }

    private func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    }

    func test_beginIsExclusive() throws {
        let ledger = CompanionSendLedger(folder: folder)
        try ledger.begin(record())
        XCTAssertThrowsError(try ledger.begin(record()))
        XCTAssertThrowsError(try CompanionSendLedger(folder: folder).begin(record()), "a second instance too")
        XCTAssertEqual(try files().count, 1)
    }

    func test_roundTripAndModes() throws {
        let ledger = CompanionSendLedger(folder: folder)
        var r = record()
        try ledger.begin(r)
        XCTAssertEqual(ledger.record("snd-1"), r)
        XCTAssertEqual(ledger.record("snd-1")?.state, .inProgress)
        r.state = .finished; r.outcome = .sent; r.detail = .confirmed; r.anchorGUID = "row"; r.finishedAt = t0
        r.dispatchedAt = t0
        try ledger.update(r)
        XCTAssertEqual(ledger.record("snd-1"), r)
        let folderMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
        XCTAssertEqual(folderMode, 0o700)
        for file in try files() {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        }
        XCTAssertNil(ledger.record("snd-other"))
    }

    func test_fileHoldsNoText() throws {
        let ledger = CompanionSendLedger(folder: folder)
        var r = record(text: "SECRET-PHRASE")
        try ledger.begin(r)
        r.state = .finished; r.outcome = .ambiguous; r.detail = .noReadback
        try ledger.update(r)
        for file in try files() {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("SECRET-PHRASE".utf8)))
            XCTAssertNotNil(bytes.range(of: Data(CompanionTextHash.of("SECRET-PHRASE").utf8)))
        }
    }

    func test_fileNameIsHashedSendID() throws {
        let ledger = CompanionSendLedger(folder: folder)
        try ledger.begin(record("../../escape"))
        let names = try files().map(\.lastPathComponent)
        XCTAssertEqual(names, [CompanionTextHash.of("../../escape") + ".json"])
        XCTAssertEqual(ledger.record("../../escape")?.sendID, "../../escape")
    }

    func test_inProgressAndUnreported() throws {
        let ledger = CompanionSendLedger(folder: folder)
        try ledger.begin(record("a"))
        var b = record("b"); try ledger.begin(b)
        b.state = .finished; b.outcome = .notSent; b.detail = .expired; b.finishedAt = t0
        try ledger.update(b)
        var c = record("c"); try ledger.begin(c)
        c.state = .finished; c.outcome = .sent; c.detail = .confirmed; c.finishedAt = t0; c.reportedAt = t0
        try ledger.update(c)
        XCTAssertEqual(ledger.inProgress().map(\.sendID), ["a"])
        XCTAssertEqual(ledger.unreported().map(\.sendID), ["b"])
    }

    func test_attemptsCountsDispatchedOnly() throws {
        let ledger = CompanionSendLedger(folder: folder)
        for (index, offset) in [-90_000.0, -3_600, -60].enumerated() {
            var r = record("d\(index)"); try ledger.begin(r)
            r.dispatchedAt = t0.addingTimeInterval(offset); try ledger.update(r)
        }
        try ledger.begin(record("refused-never-dispatched"))
        XCTAssertEqual(ledger.attempts(since: t0.addingTimeInterval(-86_400)), 2)
    }

    func test_pruneKeepsUnreportedAndInProgress() throws {
        let ledger = CompanionSendLedger(folder: folder)
        let old = t0.addingTimeInterval(-100 * 86_400)
        var reported = record("old-reported"); try ledger.begin(reported)
        reported.state = .finished; reported.finishedAt = old; reported.reportedAt = old; try ledger.update(reported)
        var unreported = record("old-unreported"); try ledger.begin(unreported)
        unreported.state = .finished; unreported.finishedAt = old; try ledger.update(unreported)
        try ledger.begin(record("in-progress"))
        var recent = record("recent"); try ledger.begin(recent)
        recent.state = .finished; recent.finishedAt = t0; recent.reportedAt = t0; try ledger.update(recent)
        ledger.prune(finishedBefore: t0.addingTimeInterval(-90 * 86_400))
        XCTAssertNil(ledger.record("old-reported"))
        XCTAssertNotNil(ledger.record("old-unreported"))
        XCTAssertNotNil(ledger.record("in-progress"))
        XCTAssertNotNil(ledger.record("recent"))
    }

    func test_corruptFileBlocksRedispatch() throws {
        let ledger = CompanionSendLedger(folder: folder)
        try ledger.begin(record("snd-x"))
        try Data("{garbled".utf8).write(to: folder.appendingPathComponent(CompanionTextHash.of("snd-x") + ".json"))
        XCTAssertNil(ledger.record("snd-x"))
        XCTAssertTrue(ledger.exists("snd-x"))
        XCTAssertThrowsError(try ledger.begin(record("snd-x")))
        XCTAssertTrue(ledger.inProgress().isEmpty)
    }
}

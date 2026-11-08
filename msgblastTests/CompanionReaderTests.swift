import XCTest
@testable import msgblastCore

final class CompanionReaderTests: XCTestCase {
    private let alice = "+15550100001"
    private let bob = "test@example.invalid"

    private func reader(_ fixture: CompanionFixture) throws -> CompanionReader {
        try CompanionReader(path: fixture.url.path)
    }

    func test_rowsAfterCursorInRowIDOrder() throws {
        let f = try CompanionFixture()
        let direct = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        let group = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: "Fixture Group", handles: [alice, bob])
        for chat in [direct, group, direct, group, direct] { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        let result = try reader(f).rows(after: 2, limit: 10)
        XCTAssertEqual(result.messages.map(\.rowid), [3, 4, 5])
        XCTAssertEqual(result.messages.map(\.threadGUID), ["iMessage;-;direct", "iMessage;+;group", "iMessage;-;direct"])
        XCTAssertEqual(result.lastScannedRowID, 5)
    }

    func test_limitCaps() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        for _ in 0..<250 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        let result = try reader(f).rows(after: 0, limit: 200)
        XCTAssertEqual(result.messages.count, 200)
        XCTAssertEqual(result.lastScannedRowID, 200)
    }

    func test_orphanRowsAdvanceScan() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        for _ in 0..<5 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        try f.addMessage(chats: [], text: "orphan", handle: alice)
        try f.addMessage(chats: [], text: "orphan", handle: alice)
        let result = try reader(f).rows(after: 5, limit: 10)
        XCTAssertEqual(result.messages, [])
        XCTAssertEqual(result.lastScannedRowID, 7)
    }

    func test_messageInTwoChatsAppearsOnce() throws {
        let f = try CompanionFixture()
        let first = try f.addChat(guid: "iMessage;-;first", style: 45, displayName: nil, handles: [alice])
        let second = try f.addChat(guid: "iMessage;-;second", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [second, first], text: "m", handle: alice)
        let result = try reader(f).rows(after: 0, limit: 10)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.first?.threadGUID, "iMessage;-;first")
    }

    func test_groupSenderAndDirection() throws {
        let f = try CompanionFixture()
        let group = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: nil, handles: [alice, bob])
        try f.addMessage(chats: [group], text: "in", fromMe: false, handle: bob)
        try f.addMessage(chats: [group], text: "out", fromMe: true)
        let messages = try reader(f).rows(after: 0, limit: 10).messages
        XCTAssertEqual(messages[0].senderHandle, bob)
        XCTAssertFalse(messages[0].fromMe)
        XCTAssertTrue(messages[1].fromMe)
        XCTAssertNil(messages[1].senderHandle)
    }

    func test_bodyFallsBackToAttributedBody() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [chat], attributedBody: AttributedBodyDecoderTests.archived("from body"), handle: alice)
        try f.addMessage(chats: [chat], handle: alice, attachments: 1)
        try f.addMessage(chats: [chat], handle: alice)
        try f.addMessage(chats: [chat], attributedBody: Data([0x04, 0x0b, 0x01, 0x02]), handle: alice)
        let messages = try reader(f).rows(after: 0, limit: 10).messages
        XCTAssertEqual(messages[0].kind, .text)
        XCTAssertEqual(messages[0].text, "from body")
        XCTAssertEqual(messages[1].kind, .attachmentOnly)
        XCTAssertEqual(messages[1].attachmentCount, 1)
        XCTAssertNil(messages[1].text)
        XCTAssertEqual(messages[2].kind, .unreadable)
        XCTAssertEqual(messages[3].kind, .unreadable)
        XCTAssertNil(messages[3].text)
    }

    func test_objectReplacementStripped() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [chat], text: "\u{FFFC}see this", handle: alice, attachments: 1)
        let message = try XCTUnwrap(reader(f).rows(after: 0, limit: 10).messages.first)
        XCTAssertEqual(message.text, "see this")
        XCTAssertEqual(message.kind, .text)
        XCTAssertEqual(message.attachmentCount, 1)
    }

    func test_reactionsAreKindReactionWithoutText() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [chat], text: "Loved “hi”", handle: alice, associatedType: 2001)
        let message = try XCTUnwrap(reader(f).rows(after: 0, limit: 10).messages.first)
        XCTAssertEqual(message.kind, .reaction)
        XCTAssertNil(message.text)
    }

    func test_replyToGUIDAndDate() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        let when = Date(timeIntervalSince1970: 1_794_000_000)
        try f.addMessage(chats: [chat], guid: "g-1", text: "r", date: when, handle: alice, threadOriginator: "g-0")
        let message = try XCTUnwrap(reader(f).rows(after: 0, limit: 10).messages.first)
        XCTAssertEqual(message.guid, "g-1")
        XCTAssertEqual(message.replyToGUID, "g-0")
        XCTAssertEqual(message.sentAt.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_threadsFor() throws {
        let f = try CompanionFixture()
        try f.addChat(guid: "iMessage;+;group", style: 43, displayName: "Fixture Group", handles: [alice, bob])
        try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        try f.addChat(guid: "iMessage;-;unasked", style: 45, displayName: nil, handles: [bob])
        let threads = try reader(f).threads(guids: ["iMessage;+;group", "iMessage;-;direct"]).sorted { $0.guid < $1.guid }
        XCTAssertEqual(threads.map(\.guid), ["iMessage;+;group", "iMessage;-;direct"])
        let group = threads[0]
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.displayName, "Fixture Group")
        XCTAssertEqual(Set(group.participants.map(\.handle)), [alice, bob])
        XCTAssertTrue(group.participants.allSatisfy { $0.name == nil })
        XCTAssertEqual(group.participantsFingerprint, CompanionFingerprint.of(handles: [alice, bob]))
        XCTAssertEqual(threads[1].kind, .direct)
    }

    func test_duplicateHandleRowsCountOnce() throws {
        // Messages keeps one handle row per service, so one person can be joined to a chat twice.
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: nil, handles: [alice, bob])
        try f.exec("INSERT INTO handle(id) VALUES('\(alice)'); INSERT INTO chat_handle_join VALUES(\(chat), last_insert_rowid());")
        let thread = try XCTUnwrap(reader(f).threads(guids: ["iMessage;+;group"]).first)
        XCTAssertEqual(thread.participants.map(\.handle).sorted(), [alice, bob].sorted())
        XCTAssertEqual(thread.participantsFingerprint, CompanionFingerprint.of(handles: [alice, bob]))
    }

    func test_groupWithoutDisplayName() throws {
        let f = try CompanionFixture()
        try f.addChat(guid: "iMessage;+;group", style: 43, displayName: "", handles: [alice, bob])
        XCTAssertNil(try reader(f).threads(guids: ["iMessage;+;group"]).first?.displayName)
    }

    func test_firstRowIDSince() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;-;direct", style: 45, displayName: nil, handles: [alice])
        let day: TimeInterval = 86_400
        let now = Date()
        try f.addMessage(chats: [chat], text: "m", date: now - 5 * day, handle: alice)
        let twoDays = try f.addMessage(chats: [chat], text: "m", date: now - 2 * day, handle: alice)
        try f.addMessage(chats: [chat], text: "m", date: now - 1 * day, handle: alice)
        let r = try reader(f)
        XCTAssertEqual(try r.firstRowID(since: now - 3 * day), twoDays)
        XCTAssertNil(try r.firstRowID(since: now))
        XCTAssertEqual(try r.maxRowID(), 3)
    }

    func test_missingFileIsUnreadable() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).db").path
        XCTAssertThrowsError(try CompanionReader(path: path)) { error in
            guard case .unreadable = error as? CompanionReaderError else { return XCTFail("got \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "a read-only open must not create the file")
    }

    func test_missingColumnIsUnsupportedSchema() throws {
        let f = try CompanionFixture()
        try f.exec("ALTER TABLE message DROP COLUMN associated_message_type")
        XCTAssertThrowsError(try CompanionReader(path: f.url.path)) { error in
            guard case .unsupportedSchema = error as? CompanionReaderError else { return XCTFail("got \(error)") }
        }
    }

    func test_readOnly() throws {
        let f = try CompanionFixture()
        let chat = try f.addChat(guid: "iMessage;+;group", style: 43, displayName: nil, handles: [alice, bob])
        for _ in 0..<3 { try f.addMessage(chats: [chat], text: "m", handle: alice) }
        let before = try FileManager.default.attributesOfItem(atPath: f.url.path)
        let r = try reader(f)
        _ = try r.rows(after: 0, limit: 10)
        _ = try r.threads(guids: ["iMessage;+;group"])
        _ = try r.dataVersion()
        _ = try r.firstRowID(since: Date(timeIntervalSince1970: 0))
        let after = try FileManager.default.attributesOfItem(atPath: f.url.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(before[.size] as? Int, after[.size] as? Int)
    }
}

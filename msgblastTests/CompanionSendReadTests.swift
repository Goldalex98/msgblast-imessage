import XCTest
@testable import msgblastCore

final class CompanionSendReadTests: XCTestCase {
    private let alice = "+15555550100", bob = "bob@example.com", carol = "+15555550102"

    func test_identityDirectAndGroup() throws {
        let f = try CompanionFixture()
        try f.addChat(guid: "iMessage;-;\(alice)", style: 45, displayName: nil, handles: [alice])
        try f.addChat(guid: "iMessage;+;chat1", style: 43, displayName: "Trip", handles: [alice, bob, carol])
        let reader = try CompanionReader(path: f.url.path)
        let direct = try XCTUnwrap(try reader.sendIdentity(chatGUID: "iMessage;-;\(alice)"))
        XCTAssertEqual(direct, CompanionSendIdentity(service: "iMessage", kind: .direct, handles: [alice],
                                                     participantsFingerprint: CompanionFingerprint.of(handles: [alice])))
        let group = try XCTUnwrap(try reader.sendIdentity(chatGUID: "iMessage;+;chat1"))
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.handles, [alice, bob, carol])
        let uplinked = try reader.threads(guids: ["iMessage;+;chat1"]).first
        XCTAssertEqual(group.participantsFingerprint, uplinked?.participantsFingerprint, "same value phase 1 uploads")
    }

    func test_identityMissingChatIsNil() throws {
        let f = try CompanionFixture()
        try f.addChat(guid: "iMessage;-;\(alice)", style: 45, displayName: nil, handles: [alice])
        XCTAssertNil(try CompanionReader(path: f.url.path).sendIdentity(chatGUID: "iMessage;-;nobody"))
    }

    func test_identityReportsSMSService() throws {
        let f = try CompanionFixture()
        try f.addChat(guid: "SMS;-;\(alice)", style: 45, displayName: nil, handles: [alice], service: "SMS")
        XCTAssertEqual(try CompanionReader(path: f.url.path).sendIdentity(chatGUID: "SMS;-;\(alice)")?.service, "SMS")
    }

    func test_maxRowIDPerChat() throws {
        let f = try CompanionFixture()
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        let b = try f.addChat(guid: "b", style: 45, displayName: nil, handles: [bob])
        let inA = try f.addMessage(chats: [a], text: "one", handle: alice)
        try f.addMessage(chats: [b], text: "newer elsewhere", handle: bob)
        let reader = try CompanionReader(path: f.url.path)
        XCTAssertEqual(try reader.maxRowID(chatGUID: "a"), inA)
        XCTAssertEqual(try reader.maxRowID(chatGUID: "empty-or-missing"), 0)
    }

    func test_outgoingRowsStrictlyAfterBaseline() throws {
        let f = try CompanionFixture()
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        let baseline = try f.addMessage(chats: [a], text: "before", fromMe: true)
        let after = try f.addMessage(chats: [a], guid: "g-after", text: "after", fromMe: true, isSent: true)
        let rows = try CompanionReader(path: f.url.path).outgoingRows(chatGUID: "a", after: baseline)
        XCTAssertEqual(rows, [CompanionOutgoingRow(rowID: after, guid: "g-after", body: "after", error: 0, isSent: true)])
    }

    func test_outgoingRowsDecodeAttributedBodyOnly() throws {
        let f = try CompanionFixture()
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [a], attributedBody: AttributedBodyDecoderTests.archived("from body "), fromMe: true)
        try f.addMessage(chats: [a], text: "", attributedBody: AttributedBodyDecoderTests.archived("empty text"),
                         fromMe: true)
        let rows = try CompanionReader(path: f.url.path).outgoingRows(chatGUID: "a", after: 0)
        XCTAssertEqual(rows.map(\.body), ["from body ", "empty text"], "decoded, not trimmed")
    }

    func test_outgoingRowsReadErrorAndIsSent() throws {
        let f = try CompanionFixture()
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [a], text: "failed", fromMe: true, error: 22)
        try f.addMessage(chats: [a], text: "pending", fromMe: true)
        let rows = try CompanionReader(path: f.url.path).outgoingRows(chatGUID: "a", after: 0)
        XCTAssertEqual(rows.map(\.error), [22, 0])
        XCTAssertEqual(rows.map(\.isSent), [false, false])
    }

    func test_outgoingRowsSkipIncomingAndOtherChats() throws {
        let f = try CompanionFixture()
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        let b = try f.addChat(guid: "b", style: 45, displayName: nil, handles: [bob])
        try f.addMessage(chats: [a], text: "incoming", handle: alice)
        try f.addMessage(chats: [b], text: "mine, other chat", fromMe: true)
        try f.addMessage(chats: [a], text: "mine", fromMe: true)
        XCTAssertEqual(try CompanionReader(path: f.url.path).outgoingRows(chatGUID: "a", after: 0).map(\.body), ["mine"])
    }

    func test_missingSendColumnsDoesNotBreakPhase1Rows() throws {
        let f = try CompanionFixture(sendColumns: false)
        let a = try f.addChat(guid: "a", style: 45, displayName: nil, handles: [alice])
        try f.addMessage(chats: [a], text: "hello", handle: alice)
        let reader = try CompanionReader(path: f.url.path)
        XCTAssertEqual(try reader.rows(after: 0, limit: 10).messages.count, 1)
        XCTAssertThrowsError(try reader.outgoingRows(chatGUID: "a", after: 0)) { error in
            guard case .unsupportedSchema = error as? CompanionReaderError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try reader.sendIdentity(chatGUID: "a")) { error in
            guard case .unsupportedSchema = error as? CompanionReaderError else { return XCTFail("\(error)") }
        }
    }
}

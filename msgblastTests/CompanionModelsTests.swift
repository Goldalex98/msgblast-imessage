import XCTest
@testable import msgblastCore

final class CompanionModelsTests: XCTestCase {
    private func sampleBatch() -> UplinkBatch {
        let thread = CompanionThread(
            guid: "iMessage;+;chat0001", kind: .group, displayName: nil,
            participants: [CompanionParticipant(handle: "+15550100001", name: "Test Person")],
            participantsFingerprint: CompanionFingerprint.of(handles: ["+15550100001"]))
        let message = CompanionMessage(
            guid: "00000000-0000-0000-0000-000000000001", rowid: 7, threadGUID: thread.guid,
            fromMe: false, senderHandle: "+15550100001", sentAt: Date(timeIntervalSince1970: 1_794_000_000),
            kind: .attachmentOnly, text: nil, replyToGUID: nil, attachmentCount: 1)
        return UplinkBatch(deviceID: "mac-0000aaaa", batchID: UUID(), cursor: 7, firstRun: true,
                           threads: [thread], messages: [message])
    }

    func test_batchEncodesContractKeys() throws {
        let data = try CompanionJSON.encoder.encode(sampleBatch())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["device_id", "batch_id", "cursor", "first_run", "threads", "messages"])
        let message = try XCTUnwrap((object["messages"] as? [[String: Any]])?.first)
        XCTAssertEqual(message["thread_guid"] as? String, "iMessage;+;chat0001")
        XCTAssertEqual(message["from_me"] as? Bool, false)
        XCTAssertEqual(message["kind"] as? String, "attachment_only")
        XCTAssertEqual(message["attachment_count"] as? Int, 1)
        XCTAssertTrue(try XCTUnwrap(message["sent_at"] as? String).hasSuffix("Z"))
        let thread = try XCTUnwrap((object["threads"] as? [[String: Any]])?.first)
        XCTAssertEqual(thread["kind"] as? String, "group")
        XCTAssertNotNil(thread["participants_fingerprint"] as? String)
        XCTAssertTrue(thread.keys.contains("display_name"), "display_name is sent as null, not omitted")
    }

    func test_batchRoundTrips() throws {
        let batch = sampleBatch()
        let decoded = try CompanionJSON.decoder.decode(UplinkBatch.self, from: CompanionJSON.encoder.encode(batch))
        XCTAssertEqual(decoded, batch)
    }

    func test_fingerprintIsOrderAndFormatInsensitive() {
        let a = CompanionFingerprint.of(handles: ["+1 (555) 010-0001", "Test@Example.invalid"])
        let b = CompanionFingerprint.of(handles: ["test@example.invalid", "+15550100001"])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertNotEqual(a, CompanionFingerprint.of(handles: ["+15550100001"]))
    }

    func test_ackDecodes() throws {
        let ack = try CompanionJSON.decoder.decode(UplinkAck.self, from: Data(#"{"accepted_cursor": 42}"#.utf8))
        XCTAssertEqual(ack, UplinkAck(acceptedCursor: 42))
    }
}

import XCTest
@testable import msgblastCore

final class CompanionSendModelsTests: XCTestCase {
    func test_approvedSendDecodesContractExample() throws {
        let json = #"""
        {"sends": [{"send_id": "snd-0001", "thread_guid": "iMessage;-;+15555550100",
          "participants_fingerprint": "6b3a", "text": "Sounds good, see you at 6", "text_sha256": "abc",
          "approved_at": "2026-11-12T14:00:00Z", "expires_at": "2026-11-12T14:10:00Z"}]}
        """#
        let page = try CompanionJSON.decoder.decode(SendsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.sends.count, 1)
        let send = try XCTUnwrap(page.sends.first)
        XCTAssertEqual(send.sendID, "snd-0001")
        XCTAssertEqual(send.threadGUID, "iMessage;-;+15555550100")
        XCTAssertEqual(send.participantsFingerprint, "6b3a")
        XCTAssertEqual(send.text, "Sounds good, see you at 6")
        XCTAssertEqual(send.textSHA256, "abc")
        XCTAssertEqual(send.approvedAt, Date(timeIntervalSince1970: 1_794_492_000))
        XCTAssertEqual(send.expiresAt.timeIntervalSince(send.approvedAt), 600)
    }

    func test_sendResultEncodesSnakeCaseAndOmitsNilAnchor() throws {
        let sent = SendResult(sendID: "snd-1", outcome: .sent, anchorGUID: "row-guid", textSHA256: "h", detail: .confirmed)
        let sentJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: CompanionJSON.encoder.encode(sent)) as? [String: Any])
        XCTAssertEqual(sentJSON["send_id"] as? String, "snd-1")
        XCTAssertEqual(sentJSON["outcome"] as? String, "sent")
        XCTAssertEqual(sentJSON["anchor_guid"] as? String, "row-guid")
        XCTAssertEqual(sentJSON["text_sha256"] as? String, "h")
        XCTAssertEqual(sentJSON["detail"] as? String, "confirmed")

        let ambiguous = SendResult(sendID: "snd-2", outcome: .ambiguous, anchorGUID: nil, textSHA256: "h",
                                   detail: .noReadback)
        let data = try CompanionJSON.encoder.encode(ambiguous)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["anchor_guid"])
        XCTAssertEqual(json["outcome"] as? String, "ambiguous")
        XCTAssertEqual(json["detail"] as? String, "no_readback")
        XCTAssertEqual(try CompanionJSON.decoder.decode(SendResult.self, from: data), ambiguous)
        XCTAssertEqual(SendOutcome.notSent.rawValue, "not_sent")
    }

    func test_detailCodesAreSnakeCase() {
        for detail in SendDetail.allCases {
            XCTAssertNotNil(detail.rawValue.range(of: "^[a-z]+(_[a-z]+)*$", options: .regularExpression), detail.rawValue)
        }
        XCTAssertEqual(SendDetail.allCases.count, 21)
    }

    func test_textHashKnownVector() {
        XCTAssertEqual(CompanionTextHash.of("hello"), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func test_textHashIsOverExactUTF8() {
        XCTAssertNotEqual(CompanionTextHash.of("hi"), CompanionTextHash.of("hi "))
        XCTAssertNotEqual(CompanionTextHash.of("e\u{301}"), CompanionTextHash.of("\u{e9}"), "no Unicode normalization")
    }
}

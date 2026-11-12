import XCTest
@testable import msgblastCore

final class CompanionSendRulesTests: XCTestCase {
    private let approved = Date(timeIntervalSince1970: 1_794_492_000)

    private func send(_ text: String = "See you at 6", hash: String? = nil, approvalLength: TimeInterval = 600)
        -> ApprovedSend {
        ApprovedSend(sendID: "snd-1", threadGUID: "iMessage;-;+15555550100", participantsFingerprint: "fp", text: text,
                     textSHA256: hash ?? CompanionTextHash.of(text), approvedAt: approved,
                     expiresAt: approved.addingTimeInterval(approvalLength))
    }

    private func refusal(_ send: ApprovedSend, at offset: TimeInterval = 60, attempts: Int = 0) -> SendDetail? {
        CompanionSendRules.refusal(for: send, now: approved.addingTimeInterval(offset), attemptsLast24h: attempts)
    }

    func test_validSendPasses() {
        XCTAssertNil(refusal(send()))
    }

    func test_expiryBoundary() {
        XCTAssertNil(refusal(send(), at: 599))
        XCTAssertEqual(refusal(send(), at: 600), .expired)
        XCTAssertEqual(refusal(send(), at: 3600), .expired)
    }

    func test_approvalLengthBoundary() {
        XCTAssertNil(refusal(send(approvalLength: 600)))
        XCTAssertEqual(refusal(send(approvalLength: 601)), .approvalTooLong)
    }

    func test_hashMismatch() {
        XCTAssertEqual(refusal(send(hash: CompanionTextHash.of("something else"))), .hashMismatch)
        XCTAssertEqual(refusal(send(hash: CompanionTextHash.of("See you at 6").uppercased())), .hashMismatch)
    }

    func test_emptyAndWhitespaceTextRefused() {
        XCTAssertEqual(refusal(send("")), .textRules)
        XCTAssertEqual(refusal(send(" \n\t")), .textRules)
    }

    func test_lengthBoundaryCountsCharacters() {
        XCTAssertNil(refusal(send(String(repeating: "a", count: 4000))))
        XCTAssertEqual(refusal(send(String(repeating: "a", count: 4001))), .textRules)
        XCTAssertNil(refusal(send(String(repeating: "👍🏽", count: 4000))), "an emoji with a skin tone is one Character")
        XCTAssertEqual(refusal(send(String(repeating: "👍🏽", count: 4001))), .textRules)
    }

    func test_controlCharactersRefusedExceptTabLFCR() {
        XCTAssertEqual(refusal(send("hi\u{0007}")), .textRules)
        XCTAssertEqual(refusal(send("hi\u{001B}[0m")), .textRules)
        XCTAssertEqual(refusal(send("hi\u{0}")), .textRules)
        XCTAssertEqual(refusal(send("hi\u{7F}")), .textRules)
        XCTAssertNil(refusal(send("line 1\nline 2\r\n\tindented")))
    }

    func test_dailyCapBoundary() {
        XCTAssertNil(refusal(send(), attempts: 29))
        XCTAssertEqual(refusal(send(), attempts: 30), .dailyCap)
    }

    func test_textIsNotTrimmed() {
        XCTAssertNil(refusal(send("hi ")))
        XCTAssertEqual(refusal(send("hi ", hash: CompanionTextHash.of("hi"))), .hashMismatch)
    }

    func test_ruleOrder() {
        let everythingWrong = ApprovedSend(sendID: "s", threadGUID: "g", participantsFingerprint: "f", text: "",
                                           textSHA256: "x", approvedAt: approved,
                                           expiresAt: approved.addingTimeInterval(700))
        XCTAssertEqual(refusal(everythingWrong, at: 800, attempts: 30), .expired)
        XCTAssertEqual(refusal(everythingWrong, at: 60, attempts: 30), .approvalTooLong)
    }
}

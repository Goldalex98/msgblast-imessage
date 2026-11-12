import XCTest
@testable import msgblastCore

final class CompanionSendDecisionTests: XCTestCase {
    private let text = "See you at 6"

    private func row(_ body: String?, guid: String = "g1", error: Int = 0, sent: Bool = true, id: Int64 = 10)
        -> CompanionOutgoingRow {
        CompanionOutgoingRow(rowID: id, guid: guid, body: body, error: error, isSent: sent)
    }

    private func decide(_ script: ScriptResult, _ rows: [CompanionOutgoingRow], final: Bool = false)
        -> CompanionSendDecision {
        CompanionSendDecision.decide(script: script, rows: rows, text: text, deadlinePassed: final)
    }

    func test_automationDeniedIsNotSent() {
        XCTAssertEqual(decide(.notSubmitted(code: -1743), [row(text)]), .final(.notSent, .automationDenied, anchorGUID: nil))
    }

    func test_otherRefusalsAreNotSentWithoutReadingRows() {
        XCTAssertEqual(decide(.notSubmitted(code: 9004), []), .final(.notSent, .scriptRefused, anchorGUID: nil))
        XCTAssertEqual(decide(.failedToStart, []), .final(.notSent, .scriptRefused, anchorGUID: nil))
    }

    func test_twoMatchesAreAmbiguous() {
        let rows = [row(text, guid: "a", id: 10), row(text, guid: "b", id: 11)]
        XCTAssertEqual(decide(.submitted, rows), .final(.ambiguous, .multipleMatches, anchorGUID: nil))
        XCTAssertEqual(decide(.submitted, rows, final: true), .final(.ambiguous, .multipleMatches, anchorGUID: nil))
    }

    func test_matchWithErrorIsNotSentWithAnchor() {
        XCTAssertEqual(decide(.submitted, [row(text, guid: "f", error: 22, sent: false)]),
                       .final(.notSent, .messagesError, anchorGUID: "f"))
    }

    func test_confirmedMatchIsSent() {
        XCTAssertEqual(decide(.submitted, [row(text, guid: "s")]), .final(.sent, .confirmed, anchorGUID: "s"))
    }

    func test_timedOutScriptWithConfirmedRowIsSent() {
        for script in [ScriptResult.timedOut, .uncertain(code: -1712), .exitNonZero, .unexpected] {
            XCTAssertEqual(decide(script, [row(text, guid: "s")]), .final(.sent, .confirmed, anchorGUID: "s"), "\(script)")
        }
    }

    func test_keepWaitingBeforeDeadline() {
        XCTAssertEqual(decide(.submitted, []), .keepWaiting)
        XCTAssertEqual(decide(.submitted, [row(text, sent: false)]), .keepWaiting)
        XCTAssertEqual(decide(.timedOut, []), .keepWaiting)
    }

    func test_atDeadline() {
        XCTAssertEqual(decide(.submitted, [row(text, sent: false)], final: true),
                       .final(.ambiguous, .notConfirmed, anchorGUID: nil))
        XCTAssertEqual(decide(.submitted, [], final: true), .final(.ambiguous, .noReadback, anchorGUID: nil))
        XCTAssertEqual(decide(.timedOut, [], final: true), .final(.ambiguous, .scriptUncertain, anchorGUID: nil))
        XCTAssertEqual(decide(.uncertain(code: 1), [], final: true), .final(.ambiguous, .scriptUncertain, anchorGUID: nil))
    }

    func test_nearMatchIsAmbiguousNotNotSent() {
        XCTAssertEqual(decide(.submitted, [row("See you at 6 ")], final: true), .final(.ambiguous, .noReadback, anchorGUID: nil))
        XCTAssertEqual(decide(.submitted, [row("see you at 6", error: 22)], final: true),
                       .final(.ambiguous, .noReadback, anchorGUID: nil), "a failed row with other text says nothing")
    }

    func test_nonMatchingRowsIgnored() {
        let rows = [row("something else Alex typed", guid: "x", id: 9), row(text, guid: "s", id: 10), row(nil, guid: "n", id: 11)]
        XCTAssertEqual(decide(.submitted, rows), .final(.sent, .confirmed, anchorGUID: "s"))
    }

    func test_neverNotSentAfterSubmittedWithoutEvidence() {
        let scripts: [ScriptResult] = [.submitted, .uncertain(code: 0), .uncertain(code: -1712), .timedOut, .exitNonZero,
                                       .unexpected]
        let rowSets: [[CompanionOutgoingRow]] = [[], [row("other")], [row("other", error: 5)], [row(nil)],
                                                 [row(text, sent: false)], [row(text + "!", error: 3)]]
        for script in scripts {
            for rows in rowSets {
                for final in [false, true] {
                    if case .final(.notSent, _, _) = decide(script, rows, final: final) {
                        XCTFail("not_sent without evidence: \(script) \(rows) final=\(final)")
                    }
                }
            }
        }
    }
}

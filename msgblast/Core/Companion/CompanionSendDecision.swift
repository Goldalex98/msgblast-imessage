import Foundation

// iMessage companion (fork-only), phase 3. Turns what the script said and what chat.db shows after the baseline
// into a result. `not_sent` needs evidence (a refusal before sending, or a failed row); anything uncertain is
// `ambiguous`, which is never retried (design §5.5).
public enum CompanionSendDecision: Equatable, Sendable {
    case final(SendOutcome, SendDetail, anchorGUID: String?)
    case keepWaiting

    public static func decide(script: ScriptResult, rows: [CompanionOutgoingRow], text: String,
                              deadlinePassed: Bool) -> CompanionSendDecision {
        switch script {
        case .notSubmitted(code: -1743): return .final(.notSent, .automationDenied, anchorGUID: nil)
        case .notSubmitted, .failedToStart: return .final(.notSent, .scriptRefused, anchorGUID: nil)
        default: break
        }
        let matches = rows.filter { $0.body == text }
        if matches.count > 1 { return .final(.ambiguous, .multipleMatches, anchorGUID: nil) }
        if let match = matches.first {
            if match.error != 0 { return .final(.notSent, .messagesError, anchorGUID: match.guid) }
            if match.isSent { return .final(.sent, .confirmed, anchorGUID: match.guid) }
        }
        guard deadlinePassed else { return .keepWaiting }
        if !matches.isEmpty { return .final(.ambiguous, .notConfirmed, anchorGUID: nil) }
        return .final(.ambiguous, script == .submitted ? .noReadback : .scriptUncertain, anchorGUID: nil)
    }
}

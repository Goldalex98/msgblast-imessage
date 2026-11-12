import Foundation

// iMessage companion (fork-only), phase 3. The checks a fetched send must pass before anything else happens
// (design §5.5; phase 3 plan, Global Constraints).
public enum CompanionSendRules {
    public static let maxCharacters = 4000
    /// `expires_at` may be at most this long after `approved_at`.
    public static let maxApproval: TimeInterval = 600
    /// Dispatch attempts allowed in any rolling 24 h.
    public static let dailyCap = 30

    /// nil when the send may go ahead. Checked in this order: expiry, approval length, hash, text, cap.
    public static func refusal(for send: ApprovedSend, now: Date, attemptsLast24h: Int) -> SendDetail? {
        if now >= send.expiresAt { return .expired }
        if send.expiresAt.timeIntervalSince(send.approvedAt) > maxApproval { return .approvalTooLong }
        if CompanionTextHash.of(send.text) != send.textSHA256 { return .hashMismatch }
        if !textAllowed(send.text) { return .textRules }
        if attemptsLast24h >= dailyCap { return .dailyCap }
        return nil
    }

    static func textAllowed(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maxCharacters else {
            return false
        }
        let allowedControls: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        return !text.unicodeScalars.contains { $0.properties.generalCategory == .control && !allowedControls.contains($0) }
    }
}

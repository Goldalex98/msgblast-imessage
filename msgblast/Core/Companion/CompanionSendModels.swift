import CryptoKit
import Foundation

// iMessage companion (fork-only), phase 3. Wire types for the send routes in the uplink contract
// (`GET /imsg/sends`, `POST /imsg/send-results`).

/// A send Alex approved on HomeChat, with its exact text.
public struct ApprovedSend: Codable, Sendable, Equatable {
    public let sendID: String
    public let threadGUID: String
    public let participantsFingerprint: String
    /// Sent exactly as is; never trimmed.
    public let text: String
    public let textSHA256: String
    public let approvedAt: Date
    public let expiresAt: Date

    public init(sendID: String, threadGUID: String, participantsFingerprint: String, text: String, textSHA256: String,
                approvedAt: Date, expiresAt: Date) {
        self.sendID = sendID; self.threadGUID = threadGUID; self.participantsFingerprint = participantsFingerprint
        self.text = text; self.textSHA256 = textSHA256; self.approvedAt = approvedAt; self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case sendID = "send_id", threadGUID = "thread_guid", participantsFingerprint = "participants_fingerprint", text,
             textSHA256 = "text_sha256", approvedAt = "approved_at", expiresAt = "expires_at"
    }
}

public struct SendsPage: Codable, Sendable, Equatable {
    public let sends: [ApprovedSend]
    public init(sends: [ApprovedSend]) { self.sends = sends }
}

public enum SendOutcome: String, Codable, Sendable { case sent, notSent = "not_sent", ambiguous }

/// The fixed codes a result may carry. Never free text.
public enum SendDetail: String, Codable, Sendable, CaseIterable {
    case confirmed, expired, approvalTooLong = "approval_too_long", textRules = "text_rules",
         hashMismatch = "hash_mismatch", dailyCap = "daily_cap", paused, sendsOff = "sends_off",
         threadMissing = "thread_missing", threadChanged = "thread_changed", notIMessage = "not_imessage",
         badTarget = "bad_target", automationDenied = "automation_denied", scriptRefused = "script_refused",
         messagesError = "messages_error", noReadback = "no_readback", multipleMatches = "multiple_matches",
         notConfirmed = "not_confirmed", scriptUncertain = "script_uncertain", databaseUnreadable = "database_unreadable",
         recoveredAfterRestart = "recovered_after_restart"
}

public struct SendResult: Codable, Sendable, Equatable {
    public let sendID: String
    public let outcome: SendOutcome
    public let anchorGUID: String?
    /// The Mac's own hash of the text it fetched.
    public let textSHA256: String
    public let detail: SendDetail

    public init(sendID: String, outcome: SendOutcome, anchorGUID: String?, textSHA256: String, detail: SendDetail) {
        self.sendID = sendID; self.outcome = outcome; self.anchorGUID = anchorGUID; self.textSHA256 = textSHA256
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case sendID = "send_id", outcome, anchorGUID = "anchor_guid", textSHA256 = "text_sha256", detail
    }
}

public enum CompanionTextHash {
    /// Lowercase hex SHA-256 of the exact UTF-8 bytes (no trimming, no Unicode normalization).
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

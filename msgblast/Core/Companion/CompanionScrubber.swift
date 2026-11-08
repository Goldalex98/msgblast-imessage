import Foundation

// iMessage companion (fork-only). Runs on the Mac before anything is uplinked (contract: messages[].text, kind skipped).
public enum CompanionScrubber {
    public static let maxTextLength = 4000
    static let truncationSuffix = "…[truncated]"

    // Anything shaped like a US SSN, bare 9-digit numbers included on purpose. \p{Nd} also catches full-width and
    // other non-ASCII digits.
    private static let ssn = try! NSRegularExpression(
        pattern: #"(?<!\p{Nd})\p{Nd}{3}[-. ]?\p{Nd}{2}[-. ]?\p{Nd}{4}(?!\p{Nd})"#)
    private static let keyword = #"\b(code|passcode|otp|verification|one[- ]time|pin|2fa|mfa)\b"#
    // 4–8 digits, or the split 6-digit form ("123-456", "123 456") some services send.
    private static let number = #"(?<!\p{Nd})(?:\p{Nd}{4,8}|\p{Nd}{3}[- ]\p{Nd}{3})(?!\p{Nd})"#
    private static let verification = try! NSRegularExpression(
        pattern: "\(keyword)[\\s\\S]{0,40}?\(number)|\(number)[\\s\\S]{0,40}?\(keyword)", options: [.caseInsensitive])

    public static func scrub(_ text: String) -> String {
        ssn.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[SSN removed]")
    }

    /// A short-code sender (all digits, 3–6 long) or a verification-code message.
    public static func isSkipped(senderHandle: String?, text: String?) -> Bool {
        if let handle = senderHandle, (3...6).contains(handle.count), handle.allSatisfy(\.isASCIIDigit) { return true }
        guard let text else { return false }
        return verification.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    public static func apply(to message: CompanionMessage) -> CompanionMessage {
        var result = message
        if isSkipped(senderHandle: message.senderHandle, text: message.text) {
            result.kind = .skipped
            result.text = nil
            return result
        }
        // Scrub before cutting, so a cut can never leave part of a number behind unscrubbed.
        result.text = message.text.map { truncate(scrub($0)) }
        return result
    }

    /// At most `maxTextLength` Unicode scalars (the server counts code points), cut on a character boundary.
    static func truncate(_ text: String) -> String {
        guard text.unicodeScalars.count > maxTextLength else { return text }
        let budget = maxTextLength - truncationSuffix.unicodeScalars.count
        var kept = ""
        var used = 0
        for character in text {
            let size = character.unicodeScalars.count
            guard used + size <= budget else { break }
            kept.append(character)
            used += size
        }
        return kept + truncationSuffix
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

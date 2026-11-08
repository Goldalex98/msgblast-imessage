import Foundation

// iMessage companion (fork-only). Decodes `message.attributedBody` (a typedstream NSAttributedString).
public enum AttributedBodyDecoder {
    /// The message text, or nil when the blob is missing, malformed or not an attributed string.
    public static func text(from blob: Data?) -> String? {
        guard let blob, isWellFormed(blob) else { return nil }
        // NSUnarchiver raises an Objective-C exception on corrupt input, which Swift can't catch and which
        // would crash the app, so only blobs that pass the structural gate above ever reach it. The gate
        // mirrors the byte scanner in companion/spikes/bodies.py, which stays as the fixture oracle.
        guard let object = NSUnarchiver.unarchiveObject(with: blob) else { return nil }
        return (object as? NSAttributedString)?.string
    }

    private static let header = Data([0x0b]) + Data("streamtyped".utf8)

    /// Header, class names in order, and a string payload whose declared length fits inside the blob.
    static func isWellFormed(_ blob: Data) -> Bool {
        let bytes = [UInt8](blob)
        guard bytes.count > 13, Data(bytes[1...12]) == header else { return false }
        guard let attributed = find(Array("NSAttributedString".utf8), in: bytes, from: 13),
              let string = find(Array("NSString".utf8), in: bytes, from: attributed),
              let marker = find([0x01, 0x2b], in: bytes, from: string) else { return false }
        var k = marker  // find() returns the index just past the match
        guard k < bytes.count else { return false }
        var length = Int(bytes[k]); k += 1
        if length == 0x81 {
            guard k + 2 <= bytes.count else { return false }
            length = Int(bytes[k]) | Int(bytes[k + 1]) << 8; k += 2
        } else if length == 0x82 {
            guard k + 4 <= bytes.count else { return false }
            length = (0..<4).reduce(0) { $0 | Int(bytes[k + $1]) << (8 * $1) }; k += 4
        } else if length > 0x7f {
            return false
        }
        guard k + length <= bytes.count else { return false }
        return String(bytes: bytes[k..<(k + length)], encoding: .utf8) != nil
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard needle.count <= bytes.count, start <= bytes.count - needle.count else { return nil }
        for i in start...(bytes.count - needle.count) where bytes[i] == needle[0] {
            if Array(bytes[i..<(i + needle.count)]) == needle { return i + needle.count }
        }
        return nil
    }
}

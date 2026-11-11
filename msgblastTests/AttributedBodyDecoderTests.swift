import XCTest
@testable import msgblastCore

final class AttributedBodyDecoderTests: XCTestCase {
    /// The typedstream format Messages stores in `message.attributedBody`.
    static func archived(_ text: String) -> Data {
        NSArchiver.archivedData(withRootObject: NSAttributedString(string: text))
    }

    func test_roundTrips() {
        for text in ["hi", String(repeating: "x", count: 200), String(repeating: "y", count: 70_000), "café 👋"] {
            XCTAssertEqual(AttributedBodyDecoder.text(from: Self.archived(text)), text, "length \(text.count)")
        }
    }

    func test_badInputReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.text(from: nil))
        XCTAssertNil(AttributedBodyDecoder.text(from: Data()))
        XCTAssertNil(AttributedBodyDecoder.text(from: Data((0..<16).map { UInt8(($0 * 37 + 11) % 256) })))
        let whole = Self.archived("hello there, this is a test")
        XCTAssertNil(AttributedBodyDecoder.text(from: whole.prefix(whole.count / 2)))
        var overlong = whole
        let marker = overlong.range(of: Data([0x84, 0x01, 0x2b]))!
        overlong[marker.upperBound] = 0x7f  // claims 127 bytes; the blob holds far fewer after this point
        XCTAssertNil(AttributedBodyDecoder.text(from: overlong.prefix(marker.upperBound + 40)))
    }

    func test_nonAttributedRootReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.text(from: NSArchiver.archivedData(withRootObject: NSNumber(value: 42))))
    }

    func test_emptyStringDecodesToNoText() {
        XCTAssertTrue((AttributedBodyDecoder.text(from: Self.archived("")) ?? "").isEmpty)
    }

    func test_largeBodyUnderTheCapDecodes() {
        let text = String(repeating: "z", count: 1_572_864)  // 1.5 MiB
        XCTAssertEqual(AttributedBodyDecoder.text(from: Self.archived(text)), text)
    }

    func test_blobOverTheCapIsNotDecoded() {
        let blob = Self.archived(String(repeating: "z", count: 4 * 1024 * 1024 + 1024))
        XCTAssertGreaterThan(blob.count, AttributedBodyDecoder.maxBlobBytes)
        XCTAssertNil(AttributedBodyDecoder.text(from: blob), "a well-formed blob over the cap is refused before any unarchiving")
    }
}

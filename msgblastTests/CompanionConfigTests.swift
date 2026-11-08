import XCTest
@testable import msgblastCore

final class CompanionConfigTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("companion-config-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func assertFresh(_ config: CompanionConfig, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(config.deviceID.range(of: "^mac-[0-9a-f]{8}$", options: .regularExpression), config.deviceID,
                        file: file, line: line)
        XCTAssertNil(config.uplinkURL, file: file, line: line)
        XCTAssertFalse(config.paused, file: file, line: line)
        XCTAssertNil(config.cursor, file: file, line: line)
    }

    func test_missingFileGivesFreshConfig() {
        let config = CompanionConfig.load(from: folder.appendingPathComponent("companion.json"))
        assertFresh(config)
        XCTAssertNotEqual(config.deviceID, CompanionConfig.load(from: folder.appendingPathComponent("companion.json")).deviceID)
    }

    func test_roundTripAndMode0600() throws {
        let url = folder.appendingPathComponent("companion.json")
        var config = CompanionConfig.load(from: url)
        config.uplinkURL = URL(string: "https://uplink.example.invalid")
        config.paused = true
        config.cursor = 1234
        try config.save(to: url)
        XCTAssertEqual(CompanionConfig.load(from: url), config)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try config.save(to: url)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
    }

    func test_corruptFileGivesFreshConfig() throws {
        let url = folder.appendingPathComponent("companion.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        assertFresh(CompanionConfig.load(from: url))
        try Data(#"{"device_id": "not-a-device", "paused": false}"#.utf8).write(to: url)
        assertFresh(CompanionConfig.load(from: url))
    }

    func test_defaultURL() {
        let url = CompanionConfig.defaultURL(supportFolder: "msgblast-iMessage")
        XCTAssertTrue(url.path.hasSuffix("/Library/Application Support/msgblast-iMessage/companion.json"), url.path)
    }
}

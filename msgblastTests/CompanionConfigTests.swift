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

    // MARK: Settings save (the Settings section's Save button)

    private var configURL: URL { folder.appendingPathComponent("companion.json") }

    func test_saveWithAddressAndTokenIsReady() {
        let tokens = SettingsTokens(nil)
        let outcome = CompanionConfig.saveSettings(url: " https://home.example/ ", token: " tok-1\n", configURL: configURL,
                                                   tokens: tokens)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.host, "home.example")
        XCTAssertTrue(outcome.tokenSaved)
        XCTAssertEqual(tokens.read(), "tok-1")
        XCTAssertEqual(CompanionConfig.load(from: configURL).uplinkURL?.host, "home.example")
        XCTAssertEqual(outcome.deviceID, CompanionConfig.load(from: configURL).deviceID)
    }

    func test_saveWithEmptyTokenAndNoneSavedSaysTokenNeeded() {
        for entered in [nil, "", "  \n"] as [String?] {
            let tokens = SettingsTokens(nil)
            let outcome = CompanionConfig.saveSettings(url: "https://home.example", token: entered, configURL: configURL,
                                                       tokens: tokens)
            XCTAssertEqual(outcome.error, CompanionConfig.tokenNeededMessage, "\(String(describing: entered))")
            XCTAssertEqual(outcome.host, "home.example", "the address is still saved")
            XCTAssertFalse(outcome.tokenSaved)
            XCTAssertEqual(CompanionConfig.load(from: configURL).uplinkURL?.host, "home.example")
            XCTAssertEqual(tokens.writes, 0, "an empty field never deletes or writes the token")
        }
    }

    func test_saveWithEmptyTokenKeepsSavedOne() {
        let tokens = SettingsTokens("tok-old")
        let outcome = CompanionConfig.saveSettings(url: "https://home.example", token: "", configURL: configURL,
                                                   tokens: tokens)
        XCTAssertNil(outcome.error)
        XCTAssertTrue(outcome.tokenSaved)
        XCTAssertEqual(tokens.read(), "tok-old")
        XCTAssertEqual(tokens.writes, 0)
    }

    func test_saveRejectsNonHTTPSAndTouchesNothing() {
        for bad in ["", "http://home.example", "home.example", "https://"] {
            let tokens = SettingsTokens(nil)
            let outcome = CompanionConfig.saveSettings(url: bad, token: "tok-1", configURL: configURL, tokens: tokens)
            XCTAssertEqual(outcome.error, "Enter an https:// address.", bad)
            XCTAssertNil(outcome.host, bad)
            XCTAssertEqual(tokens.writes, 0, bad)
            XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path), bad)
        }
    }

    func test_saveReportsKeychainWriteFailureButKeepsAddress() {
        let tokens = SettingsTokens(nil, writeSucceeds: false)
        let outcome = CompanionConfig.saveSettings(url: "https://home.example", token: "tok-1", configURL: configURL,
                                                   tokens: tokens)
        XCTAssertEqual(outcome.error, "Couldn't save the token to the Keychain.")
        XCTAssertEqual(outcome.host, "home.example")
        XCTAssertFalse(outcome.tokenSaved)
    }

    func test_saveReportsTokenThatCantBeReadBack() {
        let tokens = SettingsTokens(nil, readable: false)
        let outcome = CompanionConfig.saveSettings(url: "https://home.example", token: "tok-1", configURL: configURL,
                                                   tokens: tokens)
        XCTAssertEqual(outcome.error, CompanionConfig.tokenUnreadableMessage)
        XCTAssertFalse(outcome.tokenSaved)
    }

    func test_saveReportsSettingsFileFailure() throws {
        // A plain file where the support folder should be makes the save fail.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let tokens = SettingsTokens(nil)
        let outcome = CompanionConfig.saveSettings(url: "https://home.example", token: "tok-1",
                                                   configURL: blocker.appendingPathComponent("companion.json"), tokens: tokens)
        XCTAssertEqual(outcome.error, "Couldn't save the settings file.")
        XCTAssertNil(outcome.host)
        XCTAssertEqual(tokens.writes, 0)
    }
}

private final class SettingsTokens: CompanionTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private let writeSucceeds: Bool
    private let readable: Bool
    private(set) var writes = 0
    init(_ token: String?, writeSucceeds: Bool = true, readable: Bool = true) {
        self.token = token; self.writeSucceeds = writeSucceeds; self.readable = readable
    }
    func read() -> String? { lock.lock(); defer { lock.unlock() }; return readable ? token : nil }
    @discardableResult func write(_ token: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        writes += 1
        guard writeSucceeds else { return false }
        self.token = token
        return true
    }
}

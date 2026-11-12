import Foundation

// iMessage companion (fork-only). Local, non-secret settings. The token lives in the Keychain, never here.
public struct CompanionConfig: Codable, Sendable, Equatable {
    public var uplinkURL: URL?
    public var deviceID: String
    public var paused: Bool
    /// The highest chat.db ROWID HomeChat has accepted; nil until the first batch is accepted.
    public var cursor: Int64?
    /// Phase 3: fetch and send approved replies. Off until Alex turns it on; files from before phase 3 load as off.
    public var sendsEnabled: Bool

    public init(uplinkURL: URL? = nil, deviceID: String = CompanionConfig.newDeviceID(), paused: Bool = false,
                cursor: Int64? = nil, sendsEnabled: Bool = false) {
        self.uplinkURL = uplinkURL; self.deviceID = deviceID; self.paused = paused; self.cursor = cursor
        self.sendsEnabled = sendsEnabled
    }

    enum CodingKeys: String, CodingKey {
        case uplinkURL = "uplink_url", deviceID = "device_id", paused, cursor, sendsEnabled = "sends_enabled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uplinkURL = try c.decodeIfPresent(URL.self, forKey: .uplinkURL)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        paused = try c.decode(Bool.self, forKey: .paused)
        cursor = try c.decodeIfPresent(Int64.self, forKey: .cursor)
        sendsEnabled = try c.decodeIfPresent(Bool.self, forKey: .sendsEnabled) ?? false
    }

    public static func newDeviceID() -> String {
        "mac-" + (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    public static func defaultURL(supportFolder: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportFolder, isDirectory: true)
            .appendingPathComponent("companion.json")
    }

    /// A missing or corrupt file gives a fresh config (new device ID, not paused, no cursor).
    public static func load(from url: URL) -> CompanionConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(CompanionConfig.self, from: data),
              config.deviceID.range(of: "^mac-[0-9a-f]{8}$", options: .regularExpression) != nil
        else { return CompanionConfig() }
        return config
    }

    /// Atomic, mode 0600.
    public func save(to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let temporary = folder.appendingPathComponent(".companion-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: try encoder.encode(self),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// What a Settings save did, for the status section to show.
public struct CompanionSettingsOutcome: Equatable, Sendable {
    /// The saved address's host; nil when the address wasn't saved.
    public var host: String?
    /// The config's device ID; nil when the address wasn't saved.
    public var deviceID: String?
    public var tokenSaved: Bool
    /// Shown in red. nil means the uplink has an address and a readable token.
    public var error: String?
}

public extension CompanionConfig {
    static let tokenNeededMessage = "Address saved. Paste the uplink token too: none is saved yet."
    static let tokenUnreadableMessage = "The token was written but can't be read back from the Keychain. Paste it again."

    /// The Settings section's Save. `url` must be https with a host. An empty `token` keeps the saved one; with
    /// none saved, the address is still saved and the outcome says a token is needed. The token is read back
    /// after a write, so a write that didn't stick is reported instead of showing as saved.
    static func saveSettings(url: String, token: String?, configURL: URL,
                             tokens: CompanionTokenStoring) -> CompanionSettingsOutcome {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme?.lowercased() == "https", let host = parsed.host,
              !host.isEmpty else {
            return CompanionSettingsOutcome(host: nil, deviceID: nil, tokenSaved: tokens.read() != nil,
                                            error: "Enter an https:// address.")
        }
        var config = CompanionConfig.load(from: configURL)
        config.uplinkURL = parsed
        do {
            try config.save(to: configURL)
        } catch {
            return CompanionSettingsOutcome(host: nil, deviceID: nil, tokenSaved: tokens.read() != nil,
                                            error: "Couldn't save the settings file.")
        }
        var outcome = CompanionSettingsOutcome(host: host, deviceID: config.deviceID, tokenSaved: false, error: nil)
        let entered = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !entered.isEmpty, !tokens.write(entered) {
            outcome.tokenSaved = tokens.read() != nil
            outcome.error = "Couldn't save the token to the Keychain."
            return outcome
        }
        outcome.tokenSaved = tokens.read() != nil
        if !outcome.tokenSaved { outcome.error = entered.isEmpty ? tokenNeededMessage : tokenUnreadableMessage }
        return outcome
    }
}

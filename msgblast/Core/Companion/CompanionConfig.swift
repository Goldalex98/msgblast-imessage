import Foundation

// iMessage companion (fork-only). Local, non-secret settings. The token lives in the Keychain, never here.
public struct CompanionConfig: Codable, Sendable, Equatable {
    public var uplinkURL: URL?
    public var deviceID: String
    public var paused: Bool
    /// The highest chat.db ROWID HomeChat has accepted; nil until the first batch is accepted.
    public var cursor: Int64?

    public init(uplinkURL: URL? = nil, deviceID: String = CompanionConfig.newDeviceID(), paused: Bool = false,
                cursor: Int64? = nil) {
        self.uplinkURL = uplinkURL; self.deviceID = deviceID; self.paused = paused; self.cursor = cursor
    }

    enum CodingKeys: String, CodingKey { case uplinkURL = "uplink_url", deviceID = "device_id", paused, cursor }

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

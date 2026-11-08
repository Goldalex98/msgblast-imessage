import Foundation
import msgblastCore

// iMessage companion (fork-only). Owns the 2 s timer and the settings the status section edits.
@MainActor
final class CompanionController: ObservableObject {
    @Published private(set) var status: CompanionStatus
    /// Host only, for display. The full URL stays in the config file.
    @Published var uplinkHost: String
    @Published private(set) var tokenSaved: Bool
    @Published private(set) var deviceID: String?
    @Published private(set) var settingsError: String?
    let contacts: ContactNameResolver

    private let service: CompanionService
    private let configURL: URL
    private let tokens: KeychainTokenStore
    private var timer: Timer?
    private var ticking = false

    init(supportFolder: String, databasePath: String = NSHomeDirectory() + "/Library/Messages/chat.db") {
        configURL = CompanionConfig.defaultURL(supportFolder: supportFolder)
        tokens = KeychainTokenStore()
        contacts = ContactNameResolver()
        service = CompanionService(databasePath: databasePath, configURL: configURL, tokens: tokens, names: contacts,
                                   makeUplink: { url, token in UplinkClient(baseURL: url, token: token) })
        let config = CompanionConfig.load(from: configURL)
        let exists = FileManager.default.fileExists(atPath: configURL.path)
        status = CompanionStatus(state: config.paused ? .paused : .idle, cursor: config.cursor)
        uplinkHost = config.uplinkURL?.host ?? ""
        deviceID = exists ? config.deviceID : nil
        tokenSaved = tokens.read() != nil
    }

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !ticking else { return }
        ticking = true
        Task { @MainActor in
            status = await service.tick()
            ticking = false
        }
    }

    func setPaused(_ paused: Bool) {
        Task { @MainActor in status = await service.setPaused(paused) }
    }

    /// `url` must be https. An empty `token` keeps the saved one.
    func saveSettings(url: String, token: String?) {
        settingsError = nil
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme?.lowercased() == "https", let host = parsed.host,
              !host.isEmpty else {
            settingsError = "Enter an https:// address."
            return
        }
        var config = CompanionConfig.load(from: configURL)
        config.uplinkURL = parsed
        do {
            try config.save(to: configURL)
        } catch {
            settingsError = "Couldn't save the settings file."
            return
        }
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            guard tokens.write(token) else {
                settingsError = "Couldn't save the token to the Keychain."
                return
            }
        }
        uplinkHost = host
        deviceID = config.deviceID
        tokenSaved = tokens.read() != nil
        tick()
    }
}

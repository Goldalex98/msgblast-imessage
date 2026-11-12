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

    /// `url` must be https. An empty `token` keeps the saved one; with none saved, the error says one is needed.
    func saveSettings(url: String, token: String?) {
        let outcome = CompanionConfig.saveSettings(url: url, token: token, configURL: configURL, tokens: tokens)
        settingsError = outcome.error
        tokenSaved = outcome.tokenSaved
        guard let host = outcome.host else { return }
        uplinkHost = host
        deviceID = outcome.deviceID
        tick()
    }
}

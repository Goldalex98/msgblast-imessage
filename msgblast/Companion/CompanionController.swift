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
    @Published private(set) var sendsEnabled: Bool
    @Published private(set) var sendStatus = CompanionSendStatus(state: .off)
    let contacts: ContactNameResolver

    private let service: CompanionService
    private let configURL: URL
    private let tokens: KeychainTokenStore
    private var timer: Timer?
    private var ticking = false
    private let sender: CompanionSendExecutor
    private var sendLoop: Task<Void, Never>?

    init(supportFolder: String, databasePath: String = NSHomeDirectory() + "/Library/Messages/chat.db") {
        configURL = CompanionConfig.defaultURL(supportFolder: supportFolder)
        tokens = KeychainTokenStore()
        contacts = ContactNameResolver()
        service = CompanionService(databasePath: databasePath, configURL: configURL, tokens: tokens, names: contacts,
                                   makeUplink: { url, token in UplinkClient(baseURL: url, token: token) })
        sender = CompanionSendExecutor(
            databasePath: databasePath, configURL: configURL,
            ledgerFolder: configURL.deletingLastPathComponent().appendingPathComponent("companion-sends", isDirectory: true),
            tokens: tokens, makeUplink: { url, token in UplinkClient(baseURL: url, token: token) },
            runner: OsascriptRunner())
        let config = CompanionConfig.load(from: configURL)
        sendsEnabled = config.sendsEnabled
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
        startSendLoop()
    }

    /// Phase 3. Each cycle long-polls HomeChat, so the loop paces itself; idle states wait 5 s between checks.
    private func startSendLoop() {
        guard sendLoop == nil else { return }
        let sender = sender
        sendLoop = Task { [weak self] in
            while !Task.isCancelled {
                let status = await sender.cycle()
                await MainActor.run { self?.sendStatus = status }
                switch status.state {
                case .off, .paused, .notConfigured, .stopped: try? await Task.sleep(for: .seconds(5))
                case .offline(let retryIn): try? await Task.sleep(for: .seconds(max(1, retryIn)))
                case .waiting, .sending: try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    func setSendsEnabled(_ enabled: Bool) {
        var config = CompanionConfig.load(from: configURL)
        config.sendsEnabled = enabled
        do {
            try config.save(to: configURL)
            sendsEnabled = enabled
        } catch {
            settingsError = "Couldn't save the settings file."
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

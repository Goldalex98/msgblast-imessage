import SwiftUI
import msgblastCore

// iMessage companion (fork-only). One glanceable line, with everything else under Details.
struct CompanionStatusView: View {
    @ObservedObject var controller: CompanionController
    @ObservedObject var permissions: AppPermissions
    @State private var urlText = ""
    @State private var tokenText = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(stateText)
            Spacer()
            Toggle("Paused", isOn: Binding(get: { isPaused }, set: { controller.setPaused($0) }))
                .toggleStyle(.switch).controlSize(.small)
        }
        Text(lastUplinkText).font(.callout).foregroundStyle(.secondary)
        Toggle("Send approved replies", isOn: Binding(get: { controller.sendsEnabled },
                                                      set: { controller.setSendsEnabled($0) }))
            .toggleStyle(.switch).controlSize(.small)
        if controller.sendStatus.ambiguousCount > 0 {
            let count = controller.sendStatus.ambiguousCount
            Text("\(count) \(count == 1 ? "reply" : "replies") may or may not have sent: check Messages")
                .font(.callout).foregroundStyle(.red)
        }
        DisclosureGroup("Details") {
            LabeledContent("HomeChat host", value: controller.uplinkHost.isEmpty ? "Not set" : controller.uplinkHost)
            TextField("HomeChat address", text: $urlText, prompt: Text("https://…"))
            SecureField("Uplink token", text: $tokenText, prompt: Text(controller.tokenSaved ? "Saved" : "Not set"))
            HStack {
                if let error = controller.settingsError { Text(error).foregroundStyle(.red).font(.callout) }
                Spacer()
                Button("Save") {
                    controller.saveSettings(url: urlText.isEmpty ? currentURLPlaceholder : urlText, token: tokenText)
                    tokenText = ""
                }.disabled(urlText.isEmpty && controller.uplinkHost.isEmpty)
            }
            LabeledContent("Device ID", value: controller.deviceID ?? "Made on first save")
            LabeledContent("Cursor", value: controller.status.cursor.map(String.init) ?? "None yet")
            if let pending = controller.status.pendingEstimate, pending > 0 {
                LabeledContent("Waiting to send", value: "about \(pending)")
            }
            LabeledContent("Replies", value: sendStateText)
            LabeledContent("Last reply", value: lastSendText)
            LabeledContent("Full Disk Access", value: permissions.history.title)
            LabeledContent("Contacts names", value: controller.contacts.isAuthorized ? "Allowed" : "Off (names sent as unknown)")
        }
    }

    private var currentURLPlaceholder: String { controller.uplinkHost.isEmpty ? "" : "https://\(controller.uplinkHost)" }

    private var isPaused: Bool {
        if case .paused = controller.status.state { return true }
        return false
    }

    private var stateText: String {
        switch controller.status.state {
        case .paused: "Paused"
        case .notConfigured: "Not set up"
        case .noDatabaseAccess: "Needs Full Disk Access"
        case .idle: "Up to date"
        case .uplinking: "Uplinking"
        case .offline(let retryIn): "Mac offline, retrying in \(Int(retryIn.rounded(.up))) s"
        case .stopped(let reason): "Stopped: \(reason)"
        }
    }

    private var color: Color {
        switch controller.status.state {
        case .idle, .uplinking: .green
        case .paused, .notConfigured: .gray
        case .offline: .orange
        case .noDatabaseAccess, .stopped: .red
        }
    }

    private var sendStateText: String {
        switch controller.sendStatus.state {
        case .off: "Off"
        case .paused: "Paused"
        case .notConfigured: "Not set up"
        case .waiting: "Waiting"
        case .sending: "Sending"
        case .offline(let retryIn): "Mac offline, retrying in \(Int(retryIn.rounded(.up))) s"
        case .stopped(let reason): "Stopped: \(reason)"
        }
    }

    private var lastSendText: String {
        guard let last = controller.sendStatus.last else { return "None in the last 7 days" }
        let ago = RelativeDateTimeFormatter().localizedString(for: last.at, relativeTo: Date())
        let outcome = switch last.outcome {
        case .sent: "sent"
        case .notSent: "not sent"
        case .ambiguous: "may or may not have sent"
        }
        return "\(outcome), \(ago)"
    }

    private var lastUplinkText: String {
        guard let last = controller.status.lastUplinkAt else { return "No uplink yet this session" }
        let ago = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
        let count = controller.status.lastBatchCount
        return "Last uplink \(ago) · \(count) message\(count == 1 ? "" : "s")"
    }
}

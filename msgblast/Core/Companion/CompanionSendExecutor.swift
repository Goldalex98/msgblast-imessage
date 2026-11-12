import CryptoKit
import Foundation

// iMessage companion (fork-only), phase 3. Fetches sends Alex approved on HomeChat, checks them again, sends each
// at most once and reports the outcome (design §4.1, §5.5; phase 3 plan Task 8). The central rule: a send_id
// with any ledger record is never dispatched again.

public struct CompanionSendStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case off, paused, notConfigured, waiting, sending, offline(retryIn: TimeInterval), stopped(String)
    }
    public struct LastSend: Sendable, Equatable {
        public let outcome: SendOutcome
        public let at: Date
    }
    public var state: State
    public var last: LastSend?
    /// Ambiguous results in the last 7 days: "may or may not have sent: check Messages".
    public var ambiguousCount: Int

    public init(state: State, last: LastSend? = nil, ambiguousCount: Int = 0) {
        self.state = state; self.last = last; self.ambiguousCount = ambiguousCount
    }
}

public actor CompanionSendExecutor {
    public static let fetchWait = 25
    public static let scriptTimeout: TimeInterval = 35
    /// Read-back after the script returns: one poll now, then one a second for 20 s (Alex, 2026-11-11).
    public static let readbackPolls = 20
    public static let retention: TimeInterval = 90 * 86_400
    static let ambiguousWindow: TimeInterval = 7 * 86_400
    static let initialBackoff: TimeInterval = 5
    static let maxBackoff: TimeInterval = 300

    private let databasePath: String
    private let configURL: URL
    private let ledger: CompanionSendLedger
    private let tokens: any CompanionTokenStoring
    private let makeUplink: @Sendable (URL, String) -> any CompanionSendUplinking
    private let runner: any CompanionScriptRunning
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var backoff: TimeInterval = 0
    private var retryAt: Date?
    /// Set by a 401, a 409 on a result or another rejection; cleared when the URL or token changes.
    private var stop: (key: String, reason: String)?
    private var inFlight = false
    private var current = CompanionSendStatus(state: .off)

    public init(databasePath: String, configURL: URL, ledgerFolder: URL, tokens: any CompanionTokenStoring,
                makeUplink: @escaping @Sendable (URL, String) -> any CompanionSendUplinking,
                runner: any CompanionScriptRunning, now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.databasePath = databasePath; self.configURL = configURL
        self.ledger = CompanionSendLedger(folder: ledgerFolder); self.tokens = tokens; self.makeUplink = makeUplink
        self.runner = runner; self.now = now; self.sleep = sleep
    }

    /// One pass: recover, report, fetch, send. The caller loops.
    public func cycle() async -> CompanionSendStatus {
        if inFlight { return current }
        inFlight = true
        defer { inFlight = false }
        let config = CompanionConfig.load(from: configURL)
        guard config.sendsEnabled else { return status(.off) }
        if config.paused { return status(.paused) }
        guard let url = config.uplinkURL, let token = tokens.read() else { return status(.notConfigured) }
        let key = SHA256.hash(data: Data("\(url.absoluteString)\n\(token)".utf8)).map { String(format: "%02x", $0) }.joined()
        if let stop {
            if stop.key == key { return status(.stopped(stop.reason)) }
            self.stop = nil
        }
        if let retryAt, retryAt > now() { return status(.offline(retryIn: retryAt.timeIntervalSince(now()))) }
        let uplink = makeUplink(url, token)

        if let blocked = recover() { return status(.stopped(blocked)) }
        if let halted = await reportUnreported(uplink, key: key) { return status(halted) }

        let sends: [ApprovedSend]
        do throws(SendsError) {
            sends = try await uplink.fetchSends(wait: Self.fetchWait)
        } catch {
            return status(handle(error, key: key))
        }
        clearBackoff()
        for send in sends {
            if let record = ledger.record(send.sendID), record.state == .finished {
                // HomeChat handed it out again: post what happened, never dispatch it again.
                if let halted = await report(record, uplink, key: key) { return status(halted) }
                continue
            }
            if ledger.exists(send.sendID) { continue }
            guard let record = await process(send) else { return status(.stopped(Self.unreadable)) }
            if let halted = await report(record, uplink, key: key) { return status(halted) }
        }
        ledger.prune(finishedBefore: now() - Self.retention)
        return status(.waiting)
    }

    static let unreadable = "Can't read the Messages database"

    // MARK: - Recovery

    /// Resolves records a crash left in progress, never by sending: `sent` only on exactly one confirmed row with
    /// the approved text after the baseline, else `ambiguous` (Alex, 2026-11-11). Returns a reason when chat.db
    /// can't be read, so nothing new is fetched until it can.
    private func recover() -> String? {
        let pending = ledger.inProgress()
        guard !pending.isEmpty else { return nil }
        guard let reader = try? CompanionReader(path: databasePath) else { return Self.unreadable }
        for var record in pending {
            let rows = (try? reader.outgoingRows(chatGUID: record.threadGUID, after: record.baselineRowID ?? Int64.max))
            guard let rows else { return Self.unreadable }
            let decision = CompanionSendDecision.decide(script: .uncertain(code: 0), rows: rows, deadlinePassed: true) {
                $0.body.map(CompanionTextHash.of) == record.textSHA256
            }
            if case .final(.sent, _, let anchor) = decision {
                finish(&record, .sent, .recoveredAfterRestart, anchor: anchor)
            } else {
                finish(&record, .ambiguous, .recoveredAfterRestart, anchor: nil)
            }
        }
        return nil
    }

    // MARK: - One send

    /// nil when chat.db couldn't be read before dispatch: nothing is recorded, so HomeChat hands the send out
    /// again until it expires.
    private func process(_ send: ApprovedSend) async -> SendRecord? {
        let hash = CompanionTextHash.of(send.text)
        let started = now()
        var record = SendRecord(sendID: send.sendID, threadGUID: send.threadGUID, textLength: send.text.count,
                                textSHA256: hash, baselineRowID: nil, createdAt: started)
        if let refusal = CompanionSendRules.refusal(for: send, now: started,
                                                    attemptsLast24h: ledger.attempts(since: started - 86_400)) {
            return refuse(record, refusal)
        }
        let config = CompanionConfig.load(from: configURL)
        if !config.sendsEnabled { return refuse(record, .sendsOff) }
        if config.paused { return refuse(record, .paused) }

        guard let reader = try? CompanionReader(path: databasePath) else { return nil }
        let identity: CompanionSendIdentity?
        let baseline: Int64
        do throws(CompanionReaderError) {
            identity = try reader.sendIdentity(chatGUID: send.threadGUID)
            baseline = try reader.maxRowID(chatGUID: send.threadGUID)
        } catch {
            return nil
        }
        guard let identity else { return refuse(record, .threadMissing) }
        guard identity.service == "iMessage" else { return refuse(record, .notIMessage) }
        guard identity.participantsFingerprint == send.participantsFingerprint else { return refuse(record, .threadChanged) }
        let arguments: [String]
        do throws(CompanionSendScriptError) {
            arguments = try CompanionSendScript.arguments(threadGUID: send.threadGUID, handles: identity.handles,
                                                          text: send.text)
        } catch {
            return refuse(record, .badTarget)
        }
        if now() >= send.expiresAt { return refuse(record, .expired) }

        // Recorded before anything runs; if either write fails, nothing is dispatched.
        record = SendRecord(sendID: send.sendID, threadGUID: send.threadGUID, textLength: send.text.count,
                            textSHA256: hash, baselineRowID: baseline, createdAt: started)
        do { try ledger.begin(record) } catch { return nil }
        record.dispatchedAt = now()
        do { try ledger.update(record) } catch { return nil }

        current.state = .sending
        let script = CompanionSendScript.result(of: await runner.run(source: CompanionSendScript.source,
                                                                     arguments: arguments, timeout: Self.scriptTimeout))
        for poll in 0...Self.readbackPolls {
            if poll > 0 { await sleep(1) }
            guard let rows = try? reader.outgoingRows(chatGUID: send.threadGUID, after: baseline) else {
                finish(&record, .ambiguous, .databaseUnreadable, anchor: nil)
                return record
            }
            let decision = CompanionSendDecision.decide(script: script, rows: rows, text: send.text,
                                                        deadlinePassed: poll == Self.readbackPolls)
            if case .final(let outcome, let detail, let anchor) = decision {
                finish(&record, outcome, detail, anchor: anchor)
                return record
            }
        }
        finish(&record, .ambiguous, .noReadback, anchor: nil)  // not reached: the last poll is always final
        return record
    }

    private func refuse(_ record: SendRecord, _ detail: SendDetail) -> SendRecord? {
        var record = record
        do { try ledger.begin(record) } catch { return ledger.record(record.sendID) }
        finish(&record, .notSent, detail, anchor: nil)
        return record
    }

    private func finish(_ record: inout SendRecord, _ outcome: SendOutcome, _ detail: SendDetail, anchor: String?) {
        record.state = .finished; record.outcome = outcome; record.detail = detail; record.anchorGUID = anchor
        record.finishedAt = now()
        try? ledger.update(record)
    }

    // MARK: - Reporting

    private func reportUnreported(_ uplink: any CompanionSendUplinking, key: String) async -> CompanionSendStatus.State? {
        for record in ledger.unreported() {
            if let halted = await report(record, uplink, key: key) { return halted }
        }
        return nil
    }

    /// nil when reported (or nothing to report); otherwise the state that stops this cycle.
    private func report(_ record: SendRecord, _ uplink: any CompanionSendUplinking,
                        key: String) async -> CompanionSendStatus.State? {
        guard record.state == .finished, let outcome = record.outcome, let detail = record.detail else { return nil }
        let result = SendResult(sendID: record.sendID, outcome: outcome, anchorGUID: record.anchorGUID,
                                textSHA256: record.textSHA256, detail: detail)
        do throws(SendsError) {
            try await uplink.postResult(result)
        } catch .unknownSend {
            markReported(record)
            return nil
        } catch {
            return handle(error, key: key)
        }
        clearBackoff()
        markReported(record)
        return nil
    }

    private func markReported(_ record: SendRecord) {
        guard var stored = ledger.record(record.sendID), stored.reportedAt == nil else { return }
        stored.reportedAt = now()
        try? ledger.update(stored)
    }

    private func handle(_ error: SendsError, key: String) -> CompanionSendStatus.State {
        switch error {
        case .retryable, .badResponse:
            backoff = backoff == 0 ? Self.initialBackoff : min(backoff * 2, Self.maxBackoff)
            retryAt = now() + backoff
            return .offline(retryIn: backoff)
        case .unauthorized: return halt("token rejected", key: key)
        case .conflict: return halt("HomeChat holds a different result for a send", key: key)
        case .notHTTPS: return halt("the HomeChat address must be https", key: key)
        case .unknownSend: return halt("HomeChat doesn't know a send", key: key)
        case .rejected(let code): return halt("HomeChat refused (\(code))", key: key)
        }
    }

    private func halt(_ reason: String, key: String) -> CompanionSendStatus.State {
        stop = (key, reason)
        return .stopped(reason)
    }

    private func clearBackoff() { backoff = 0; retryAt = nil }

    private func status(_ state: CompanionSendStatus.State) -> CompanionSendStatus {
        let recent = ledger.finished(since: now() - Self.ambiguousWindow)
        let last = recent.max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
        current = CompanionSendStatus(
            state: state,
            last: last.flatMap { record in record.outcome.map { .init(outcome: $0, at: record.finishedAt ?? now()) } },
            ambiguousCount: recent.filter { $0.outcome == .ambiguous }.count)
        return current
    }
}

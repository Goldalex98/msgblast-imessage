import Foundation

// iMessage companion (fork-only). One read-and-uplink cycle per tick(); the caller owns the timer.

public protocol CompanionNameResolving: Sendable {
    /// Contact names by handle; handles with no known name are left out.
    func names(for handles: [String]) async -> [String: String]
}

public protocol CompanionUplinking: Sendable {
    func post(_ batch: UplinkBatch) async throws(UplinkError) -> UplinkAck
}

extension UplinkClient: CompanionUplinking {}

public struct CompanionStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case paused, notConfigured, noDatabaseAccess, idle, uplinking
        case offline(retryIn: TimeInterval)
        /// Carries only an HTTP status or an error kind, never message text or handles.
        case stopped(String)
    }
    public var state: State
    public var lastUplinkAt: Date?
    public var lastBatchCount: Int
    public var cursor: Int64?
    public var pendingEstimate: Int64?
    public init(state: State, lastUplinkAt: Date? = nil, lastBatchCount: Int = 0, cursor: Int64? = nil,
                pendingEstimate: Int64? = nil) {
        self.state = state; self.lastUplinkAt = lastUplinkAt; self.lastBatchCount = lastBatchCount
        self.cursor = cursor; self.pendingEstimate = pendingEstimate
    }
}

public actor CompanionService {
    public static let batchLimit = 200
    public static let firstRunWindow: TimeInterval = 3 * 86_400
    static let initialBackoff: TimeInterval = 5
    static let maxBackoff: TimeInterval = 300

    private let databasePath: String
    private let configURL: URL
    private let tokens: any CompanionTokenStoring
    private let names: any CompanionNameResolving
    private let makeUplink: @Sendable (URL, String) -> any CompanionUplinking
    private let now: @Sendable () -> Date

    // One connection for the service's life: PRAGMA data_version is only comparable on the same connection.
    private var reader: CompanionReader?
    private var lastDataVersion: Int64?
    private var caughtUp = false
    private var backoff: TimeInterval = 0
    private var retryAt: Date?
    /// Set by a 401 or rejection; cleared when the URL or token changes.
    private var stop: (key: String, reason: String)?
    /// While nothing has been accepted yet, the first-run start lives here, not in the config.
    private var firstRunCursor: Int64?
    public private(set) var status = CompanionStatus(state: .idle)

    public init(databasePath: String, configURL: URL, tokens: any CompanionTokenStoring,
                names: any CompanionNameResolving, makeUplink: @escaping @Sendable (URL, String) -> any CompanionUplinking,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.databasePath = databasePath; self.configURL = configURL; self.tokens = tokens; self.names = names
        self.makeUplink = makeUplink; self.now = now
    }

    public func setPaused(_ paused: Bool) async -> CompanionStatus {
        var config = CompanionConfig.load(from: configURL)
        config.paused = paused
        try? config.save(to: configURL)
        if paused { closeReader() }
        return update(paused ? .paused : .idle, config: config)
    }

    public func tick() async -> CompanionStatus {
        var config = CompanionConfig.load(from: configURL)
        if config.paused { closeReader(); return update(.paused, config: config) }
        guard let url = config.uplinkURL, let token = tokens.read() else { return update(.notConfigured, config: config) }
        let key = "\(url.absoluteString)\n\(token)"
        if let stop {
            if stop.key == key { return update(.stopped(stop.reason), config: config) }
            self.stop = nil
            lastDataVersion = nil
        }
        if let retryAt, retryAt > now() {
            return update(.offline(retryIn: retryAt.timeIntervalSince(now())), config: config)
        }

        let reader: CompanionReader
        do throws(CompanionReaderError) {
            reader = try openReader()
            let version = try reader.dataVersion()
            if version == lastDataVersion, caughtUp, retryAt == nil { return update(.idle, config: config) }
            lastDataVersion = version
        } catch {
            return databaseFailure(error, config: config)
        }

        let firstRun = config.cursor == nil
        let start: Int64
        let read: CompanionReadResult
        let threads: [CompanionThread]
        do throws(CompanionReaderError) {
            if let cursor = config.cursor {
                start = cursor
            } else if let cursor = firstRunCursor {
                start = cursor
            } else {
                if let recent = try reader.firstRowID(since: now() - Self.firstRunWindow) {
                    start = recent - 1
                } else {
                    start = try reader.maxRowID()
                }
                firstRunCursor = start
            }
            read = try reader.rows(after: start, limit: Self.batchLimit)
            threads = try reader.threads(guids: Set(read.messages.map(\.threadGUID)))
        } catch {
            return databaseFailure(error, config: config)
        }

        if read.messages.isEmpty {
            if read.lastScannedRowID > start { advance(to: read.lastScannedRowID, firstRun: firstRun, config: &config) }
            caughtUp = isCaughtUp(reader, cursor: read.lastScannedRowID)
            return update(.idle, config: config)
        }

        let handles = Array(Set(threads.flatMap { $0.participants.map(\.handle) })).sorted()
        let known = handles.isEmpty ? [:] : await names.names(for: handles)
        let named = threads.map { thread -> CompanionThread in
            var thread = thread
            thread.participants = thread.participants.map { CompanionParticipant(handle: $0.handle, name: known[$0.handle]) }
            return thread
        }
        let batch = UplinkBatch(deviceID: config.deviceID, batchID: UUID(), cursor: read.lastScannedRowID,
                                firstRun: firstRun, threads: named, messages: read.messages.map(CompanionScrubber.apply))
        status.state = .uplinking

        do throws(UplinkError) {
            let ack = try await makeUplink(url, token).post(batch)
            // Never past this batch, never back behind where it started.
            let accepted = min(max(ack.acceptedCursor, start), batch.cursor)
            advance(to: accepted, firstRun: false, config: &config)
            backoff = 0
            retryAt = nil
            caughtUp = isCaughtUp(reader, cursor: accepted)
            status.lastUplinkAt = now()
            status.lastBatchCount = batch.messages.count
            return update(.idle, config: config)
        } catch {
            switch error {
            case .unauthorized:
                return halt("token rejected", key: key, config: config)
            case .rejected(let code):
                return halt("rejected (HTTP \(code))", key: key, config: config)
            case .notHTTPS:
                return halt("uplink URL must be https", key: key, config: config)
            case .retryable, .badResponse:
                backoff = backoff == 0 ? Self.initialBackoff : min(backoff * 2, Self.maxBackoff)
                retryAt = now() + backoff
                return update(.offline(retryIn: backoff), config: config)
            }
        }
    }

    // MARK: - Helpers

    private func openReader() throws(CompanionReaderError) -> CompanionReader {
        if let reader { return reader }
        let opened = try CompanionReader(path: databasePath)
        reader = opened
        lastDataVersion = nil
        return opened
    }

    private func closeReader() {
        reader = nil
        lastDataVersion = nil
    }

    private func databaseFailure(_ error: CompanionReaderError, config: CompanionConfig) -> CompanionStatus {
        closeReader()
        switch error {
        case .unreadable: return update(.noDatabaseAccess, config: config)
        case .unsupportedSchema: return update(.stopped("unsupported Messages database"), config: config)
        case .query: return update(.stopped("Messages database busy"), config: config)
        }
    }

    private func halt(_ reason: String, key: String, config: CompanionConfig) -> CompanionStatus {
        stop = (key, reason)
        backoff = 0
        retryAt = nil
        return update(.stopped(reason), config: config)
    }

    /// While nothing has been accepted, an orphan-only stretch moves the in-memory start only, so first_run holds.
    private func advance(to cursor: Int64, firstRun: Bool, config: inout CompanionConfig) {
        if firstRun {
            firstRunCursor = cursor
            return
        }
        config.cursor = cursor
        firstRunCursor = nil
        try? config.save(to: configURL)
    }

    private func isCaughtUp(_ reader: CompanionReader, cursor: Int64) -> Bool {
        guard let max = try? reader.maxRowID() else { return false }
        return max <= cursor
    }

    private func update(_ state: CompanionStatus.State, config: CompanionConfig) -> CompanionStatus {
        status.state = state
        status.cursor = config.cursor
        if let reader, let max = try? reader.maxRowID(), let cursor = config.cursor ?? firstRunCursor {
            status.pendingEstimate = Swift.max(0, max - cursor)
        } else {
            status.pendingEstimate = nil
        }
        return status
    }
}

import Foundation

// iMessage companion (fork-only), phase 3. One file per send, written before anything is dispatched, so a send is
// never dispatched twice and a crash mid-send is found on the next launch (send notes, Borrow 1). Records hold no
// message text: only its length and hash (Alex, 2026-11-11). The exact text stays on HomeChat.

public struct SendRecord: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case inProgress = "in_progress", finished }

    public let sendID: String
    public let threadGUID: String
    public let textLength: Int
    public let textSHA256: String
    public let baselineRowID: Int64?
    public let createdAt: Date
    public var state: State
    public var dispatchedAt: Date?
    public var outcome: SendOutcome?
    public var detail: SendDetail?
    public var anchorGUID: String?
    public var finishedAt: Date?
    public var reportedAt: Date?

    public init(sendID: String, threadGUID: String, textLength: Int, textSHA256: String, baselineRowID: Int64?,
                createdAt: Date) {
        self.sendID = sendID; self.threadGUID = threadGUID; self.textLength = textLength; self.textSHA256 = textSHA256
        self.baselineRowID = baselineRowID; self.createdAt = createdAt; state = .inProgress
    }

    enum CodingKeys: String, CodingKey {
        case sendID = "send_id", threadGUID = "thread_guid", textLength = "text_length", textSHA256 = "text_sha256",
             baselineRowID = "baseline_rowid", createdAt = "created_at", state, dispatchedAt = "dispatched_at", outcome,
             detail, anchorGUID = "anchor_guid", finishedAt = "finished_at", reportedAt = "reported_at"
    }
}

public enum CompanionSendLedgerError: Error, Equatable { case exists, writeFailed }

/// Used only from the executor actor.
public final class CompanionSendLedger: @unchecked Sendable {
    private let folder: URL
    private var lockFD: Int32?

    public init(folder: URL) { self.folder = folder }

    deinit { if let lockFD { close(lockFD) } }

    /// An exclusive `flock` on `.lock` in the folder, held for this instance's life, so a second copy of the app
    /// can't recover or finish another copy's sends. False when another instance holds it.
    public func lockExclusively() -> Bool {
        if lockFD != nil { return true }
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                         attributes: [.posixPermissions: 0o700])) != nil else { return false }
        let fd = open(folder.appendingPathComponent(".lock").path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        lockFD = fd
        return true
    }

    /// The file name is the hash of the server's id, so a `send_id` never becomes a path.
    private func file(_ sendID: String) -> URL { folder.appendingPathComponent(CompanionTextHash.of(sendID) + ".json") }

    /// True when any file exists for this id, even one that can't be read.
    public func exists(_ sendID: String) -> Bool { FileManager.default.fileExists(atPath: file(sendID).path) }

    public func record(_ sendID: String) -> SendRecord? { load(file(sendID)) }

    /// Exclusive create: throws `.exists` if this send has ever been recorded.
    public func begin(_ record: SendRecord) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try CompanionJSON.encoder.encode(record)
        let fd = open(file(record.sendID).path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw errno == EEXIST ? CompanionSendLedgerError.exists : .writeFailed }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            throw CompanionSendLedgerError.writeFailed
        }
    }

    /// Atomic replace, mode 0600.
    public func update(_ record: SendRecord) throws {
        let target = file(record.sendID)
        let temporary = folder.appendingPathComponent(".send-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: try CompanionJSON.encoder.encode(record),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CompanionSendLedgerError.writeFailed
        }
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw CompanionSendLedgerError.writeFailed
        }
    }

    public func inProgress() -> [SendRecord] { all().filter { $0.state == .inProgress } }

    public func unreported() -> [SendRecord] { all().filter { $0.state == .finished && $0.reportedAt == nil } }

    /// Finished records whose `finishedAt` is at or after `since`, oldest first.
    public func finished(since: Date) -> [SendRecord] {
        all().filter { $0.state == .finished && ($0.finishedAt ?? .distantPast) >= since }
    }

    public func attempts(since: Date) -> Int { all().filter { ($0.dispatchedAt ?? .distantPast) >= since }.count }

    /// Deletes reported records that finished before `finishedBefore`; keeps everything else.
    public func prune(finishedBefore: Date) {
        for (url, record) in allWithURLs() where record.reportedAt != nil && (record.finishedAt ?? .distantFuture) < finishedBefore {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func all() -> [SendRecord] { allWithURLs().map(\.1) }

    private func allWithURLs() -> [(URL, SendRecord)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { url in load(url).map { (url, $0) } }
            .sorted { ($0.1.createdAt, $0.1.sendID) < ($1.1.createdAt, $1.1.sendID) }
    }

    private func load(_ url: URL) -> SendRecord? {
        (try? Data(contentsOf: url)).flatMap { try? CompanionJSON.decoder.decode(SendRecord.self, from: $0) }
    }
}

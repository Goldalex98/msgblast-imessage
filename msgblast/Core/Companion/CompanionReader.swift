import Foundation
import SQLite3

// iMessage companion (fork-only). Reads every thread, groups included, from chat.db. Read-only: the database is
// opened with SQLITE_OPEN_READONLY and only SELECT and PRAGMA statements run.

public struct CompanionReadResult: Sendable, Equatable {
    /// Decoded but not yet scrubbed.
    public var messages: [CompanionMessage]
    /// The highest ROWID the query looked at, including rows it dropped, so the cursor can pass them.
    public var lastScannedRowID: Int64
    public init(messages: [CompanionMessage], lastScannedRowID: Int64) {
        self.messages = messages; self.lastScannedRowID = lastScannedRowID
    }
}

public enum CompanionReaderError: Error, Equatable {
    /// The SQLite result code. SQLITE_CANTOPEN, SQLITE_AUTH and SQLITE_PERM mean no permission or no file.
    case unreadable(Int32)
    case unsupportedSchema(String)
    case query(String)
}

/// Which file a path pointed at when the reader opened it: device and inode from `stat`.
public struct CompanionFileIdentity: Sendable, Equatable {
    public let device: Int64
    public let inode: UInt64

    /// nil when the path can't be stat'ed (missing file, no permission).
    public static func of(path: String) -> CompanionFileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return CompanionFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }
}

public final class CompanionReader {
    private var db: OpaquePointer?
    /// The file identity taken just before the database was opened; compare it with `CompanionFileIdentity.of`
    /// to notice that the path now points at a different file.
    public let fileIdentity: CompanionFileIdentity?

    private static let required: [String: Set<String>] = [
        "message": ["guid", "text", "attributedBody", "date", "is_from_me", "handle_id", "associated_message_type",
                    "thread_originator_guid", "cache_has_attachments", "item_type"],
        "chat": ["guid", "style", "display_name"],
        "handle": ["id"],
        "chat_handle_join": ["chat_id", "handle_id"],
        "chat_message_join": ["chat_id", "message_id"],
        "message_attachment_join": ["message_id", "attachment_id"],
    ]

    /// NSUnarchiver can raise an uncatchable exception on a corrupt blob. The row being decoded is written here
    /// first; if the app dies mid-decode, the next read finds it and treats that row as unreadable for good
    /// (kept in a "-poisoned" file beside it), so one bad row can't crash every launch.
    private let decodeMarker: URL?
    private var poisonedFile: URL? { decodeMarker.map { $0.appendingPathExtension("poisoned") } }

    public init(path: String, decodeMarker: URL? = nil) throws(CompanionReaderError) {
        self.decodeMarker = decodeMarker
        // Before the open: a swap in between then shows as a mismatch on the next check, never as a missed one.
        self.fileIdentity = CompanionFileIdentity.of(path: path)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw .unreadable(result)
        }
        db = handle
        sqlite3_busy_timeout(handle, 1500)
        do throws(CompanionReaderError) {
            for (table, columns) in Self.required.sorted(by: { $0.key < $1.key }) {
                var present = Set<String>()
                try each("PRAGMA table_info(\(table))") { present.insert(Self.text($0, 1) ?? "") }
                let missing = columns.subtracting(present)
                guard missing.isEmpty else { throw CompanionReaderError.unsupportedSchema("\(table): \(missing.sorted().joined(separator: ","))") }
            }
        } catch {
            sqlite3_close(handle); db = nil
            throw error
        }
    }

    deinit { if let db { sqlite3_close(db) } }

    public func dataVersion() throws(CompanionReaderError) -> Int64 {
        var version: Int64 = 0
        try each("PRAGMA data_version") { version = sqlite3_column_int64($0, 0) }
        return version
    }

    public func maxRowID() throws(CompanionReaderError) -> Int64 {
        var value: Int64 = 0
        try each("SELECT COALESCE(MAX(ROWID), 0) FROM message") { value = sqlite3_column_int64($0, 0) }
        return value
    }

    /// The highest ROWID `message` has ever handed out. chat.db's message table uses AUTOINCREMENT, whose
    /// `sqlite_sequence` entry stays put when the newest messages are deleted, unlike MAX(ROWID). Falls back to
    /// MAX(ROWID) when the database has no such entry.
    public func highWaterRowID() throws(CompanionReaderError) -> Int64 {
        var hasSequence = false
        try each("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence'") { _ in hasSequence = true }
        var sequence: Int64 = 0
        if hasSequence {
            try each("SELECT seq FROM sqlite_sequence WHERE name = 'message'") { sequence = sqlite3_column_int64($0, 0) }
        }
        let top = try maxRowID()
        return max(sequence, top)
    }

    /// The lowest ROWID dated at or after `since`, or nil when there is none.
    public func firstRowID(since: Date) throws(CompanionReaderError) -> Int64? {
        var value: Int64?
        let sql = "SELECT MIN(ROWID) FROM message WHERE (CASE WHEN date > 1000000000000 THEN date / 1000000000.0 ELSE date END) >= ?"
        try each(sql, [.double(since.timeIntervalSinceReferenceDate)]) {
            if sqlite3_column_type($0, 0) != SQLITE_NULL { value = sqlite3_column_int64($0, 0) }
        }
        return value
    }

    /// `holdOrphansAfter`: a row in no chat dated at or after this stops the scan before it, since Messages may
    /// not have linked it to its chat yet. Older chat-less rows are passed over.
    public func rows(after rowID: Int64, limit: Int, holdOrphansAfter: Date? = nil) throws(CompanionReaderError) -> CompanionReadResult {
        let poisoned = loadPoisoned()
        defer { if let decodeMarker { try? FileManager.default.removeItem(at: decodeMarker) } }
        // One row per message; a message joined to several chats goes under the lowest chat ROWID.
        let sql = """
        SELECT m.ROWID, m.guid, m.text, m.attributedBody, m.date, m.is_from_me, h.id, m.associated_message_type,
            m.thread_originator_guid, m.cache_has_attachments,
            (SELECT COUNT(*) FROM message_attachment_join ma WHERE ma.message_id = m.ROWID),
            (SELECT c.guid FROM chat_message_join cm JOIN chat c ON c.ROWID = cm.chat_id
                WHERE cm.message_id = m.ROWID ORDER BY c.ROWID LIMIT 1),
            m.item_type
        FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE m.ROWID > ? ORDER BY m.ROWID LIMIT ?
        """
        var messages: [CompanionMessage] = []
        var last = rowID
        var held = false
        try each(sql, [.int(rowID), .int(Int64(max(limit, 0)))]) { s in
            guard !held else { return }
            let rowid = sqlite3_column_int64(s, 0)
            // A group event or other system row: non-zero item_type with no text, body or attachments. A row that
            // carries any of those is read as usual, so an ordinary message is never dropped on item_type alone.
            if sqlite3_column_int64(s, 12) != 0, Self.text(s, 2) == nil, Self.blob(s, 3) == nil,
               sqlite3_column_int64(s, 9) == 0, sqlite3_column_int64(s, 10) == 0 {
                last = rowid
                return
            }
            let raw = Double(sqlite3_column_int64(s, 4))
            let sentAt = Date(timeIntervalSinceReferenceDate: raw > 1e12 ? raw / 1e9 : raw)
            guard let thread = Self.text(s, 11), let guid = Self.text(s, 1) else {  // no chat, no thread
                if let holdOrphansAfter, sentAt >= holdOrphansAfter { held = true } else { last = rowid }
                return
            }
            last = rowid
            let fromMe = sqlite3_column_int64(s, 5) != 0
            let associated = sqlite3_column_int64(s, 7)
            let attachments = max(Int(sqlite3_column_int64(s, 10)), sqlite3_column_int64(s, 9) != 0 ? 1 : 0)
            var kind = CompanionMessage.Kind.text
            var body: String?
            if (2000...3999).contains(associated) {
                kind = .reaction
            } else if let text = Self.clean(Self.text(s, 2)) ?? Self.clean(decode(Self.blob(s, 3), rowid: rowid, poisoned: poisoned)) {
                body = text
            } else {
                kind = attachments > 0 ? .attachmentOnly : .unreadable
            }
            messages.append(CompanionMessage(
                guid: guid, rowid: rowid, threadGUID: thread, fromMe: fromMe,
                senderHandle: fromMe ? nil : Self.text(s, 6).flatMap { $0.isEmpty ? nil : $0 },
                sentAt: sentAt,
                kind: kind, text: body,
                replyToGUID: Self.text(s, 8).flatMap { $0.isEmpty ? nil : $0 },
                attachmentCount: attachments))
        }
        return CompanionReadResult(messages: messages, lastScannedRowID: last)
    }

    public func threads(guids: Set<String>) throws(CompanionReaderError) -> [CompanionThread] {
        guard !guids.isEmpty else { return [] }
        let ordered = guids.sorted()
        let marks = Array(repeating: "?", count: ordered.count).joined(separator: ",")
        var chats: [(rowid: Int64, guid: String, style: Int64, name: String?)] = []
        try each("SELECT ROWID, guid, style, display_name FROM chat WHERE guid IN (\(marks)) ORDER BY ROWID",
                 ordered.map { .text($0) }) { s in
            guard let guid = Self.text(s, 1) else { return }
            chats.append((sqlite3_column_int64(s, 0), guid, sqlite3_column_int64(s, 2), Self.text(s, 3)))
        }
        var seen = Set<String>()
        var threads: [CompanionThread] = []
        for chat in chats where seen.insert(chat.guid).inserted {
            var handles: [String] = []
            var normalized = Set<String>()
            try each("""
                SELECT h.id FROM chat_handle_join ch JOIN handle h ON h.ROWID = ch.handle_id
                WHERE ch.chat_id = ? ORDER BY h.ROWID
                """, [.int(chat.rowid)]) { s in
                // One handle row per service, so the same person can appear twice.
                guard let id = Self.text(s, 0), !id.isEmpty, normalized.insert(ChatResolver.normalize(id)).inserted else { return }
                handles.append(id)
            }
            threads.append(CompanionThread(
                guid: chat.guid, kind: chat.style == 43 ? .group : .direct,
                displayName: chat.name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
                participants: handles.map { CompanionParticipant(handle: $0, name: nil) },
                participantsFingerprint: CompanionFingerprint.of(handles: handles)))
        }
        return threads
    }

    // MARK: - Crash-safe decoding

    private func decode(_ blob: Data?, rowid: Int64, poisoned: Set<Int64>) -> String? {
        guard let blob, !poisoned.contains(rowid) else { return nil }
        if let decodeMarker { try? Data(String(rowid).utf8).write(to: decodeMarker) }
        return AttributedBodyDecoder.text(from: blob)
    }

    /// Moves a marker left by a crash into the poisoned list, then returns that list.
    private func loadPoisoned() -> Set<Int64> {
        guard let decodeMarker, let poisonedFile else { return [] }
        let existing = (try? String(contentsOf: poisonedFile, encoding: .utf8)) ?? ""
        var rows = Set(existing.split(whereSeparator: \.isNewline).compactMap { Int64($0) })
        if let crashed = (try? String(contentsOf: decodeMarker, encoding: .utf8)).flatMap({ Int64($0) }),
           rows.insert(crashed).inserted {
            try? Data(rows.sorted().map(String.init).joined(separator: "\n").utf8).write(to: poisonedFile, options: .atomic)
        }
        try? FileManager.default.removeItem(at: decodeMarker)
        return rows
    }

    // MARK: - SQLite

    private enum Binding { case int(Int64), double(Double), text(String) }

    private func each(_ sql: String, _ bindings: [Binding] = [], _ row: (OpaquePointer) -> Void) throws(CompanionReaderError) {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw failure(prepared) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .double(let value): sqlite3_bind_double(statement, index, value)
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, transient)
            }
        }
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return }
            guard code == SQLITE_ROW else { throw failure(code) }
            row(statement)
        }
    }

    private func failure(_ code: Int32) -> CompanionReaderError {
        let primary = code & 0xff
        if [SQLITE_CANTOPEN, SQLITE_AUTH, SQLITE_PERM, SQLITE_NOTADB].contains(primary) { return .unreadable(primary) }
        return .query(String(cString: sqlite3_errmsg(db)))
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    /// Strips U+FFFC (the attachment placeholder) and surrounding whitespace; empty becomes nil.
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

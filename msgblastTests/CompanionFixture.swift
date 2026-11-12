import Foundation
import SQLite3
import XCTest

/// A synthetic `chat.db` with the columns the companion reader uses. No real data, ever.
final class CompanionFixture {
    let url: URL
    private var db: OpaquePointer?
    private let sendColumns: Bool

    /// `sendColumns: false` leaves out the columns only phase 3's send read-back uses.
    init(sendColumns: Bool = true) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("companion-\(UUID().uuidString).db")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "fixture", code: 1) }
        self.sendColumns = sendColumns
        let chatSend = sendColumns ? ", service_name TEXT DEFAULT 'iMessage'" : ""
        let messageSend = sendColumns ? ", error INTEGER DEFAULT 0, is_sent INTEGER DEFAULT 0, is_delivered INTEGER DEFAULT 0" : ""
        try exec("""
        CREATE TABLE chat(ROWID INTEGER PRIMARY KEY, guid TEXT, style INTEGER, display_name TEXT\(chatSend));
        CREATE TABLE handle(ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join(chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE chat_message_join(chat_id INTEGER, message_id INTEGER);
        CREATE TABLE message(ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, text TEXT, attributedBody BLOB, date INTEGER,
            is_from_me INTEGER, handle_id INTEGER, associated_message_type INTEGER, thread_originator_guid TEXT,
            cache_has_attachments INTEGER, item_type INTEGER DEFAULT 0\(messageSend));
        CREATE TABLE attachment(ROWID INTEGER PRIMARY KEY, guid TEXT, filename TEXT);
        CREATE TABLE message_attachment_join(message_id INTEGER, attachment_id INTEGER);
        """)
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: url)
    }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    /// Style 43 is a group, 45 a 1:1. Returns the chat ROWID.
    @discardableResult
    func addChat(guid: String, style: Int, displayName: String?, handles: [String], service: String = "iMessage") throws -> Int64 {
        if sendColumns {
            try run("INSERT INTO chat(guid, style, display_name, service_name) VALUES(?, ?, ?, ?)",
                    [guid, style, displayName, service])
        } else {
            try run("INSERT INTO chat(guid, style, display_name) VALUES(?, ?, ?)", [guid, style, displayName])
        }
        let chat = sqlite3_last_insert_rowid(db)
        for handle in handles {
            try run("INSERT INTO chat_handle_join(chat_id, handle_id) VALUES(?, ?)", [chat, try handleRowID(handle)])
        }
        return chat
    }

    /// Returns the message ROWID.
    @discardableResult
    func addMessage(chats: [Int64], guid: String = UUID().uuidString, text: String? = nil, attributedBody: Data? = nil,
                    date: Date = Date(), fromMe: Bool = false, handle: String? = nil, associatedType: Int = 0,
                    threadOriginator: String? = nil, attachments: Int = 0, itemType: Int = 0, error: Int = 0,
                    isSent: Bool = false) throws -> Int64 {
        let handleID: Int64 = try handle.map(handleRowID) ?? 0
        let nanos = Int64(date.timeIntervalSinceReferenceDate * 1e9)
        try run("""
            INSERT INTO message(guid, text, attributedBody, date, is_from_me, handle_id, associated_message_type,
                thread_originator_guid, cache_has_attachments, item_type) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [guid, text, attributedBody, nanos, fromMe ? 1 : 0, handleID, associatedType, threadOriginator,
                  attachments > 0 ? 1 : 0, itemType])
        let message = sqlite3_last_insert_rowid(db)
        if sendColumns {
            try run("UPDATE message SET error = ?, is_sent = ? WHERE ROWID = ?", [error, isSent ? 1 : 0, message])
        }
        for chat in chats { try run("INSERT INTO chat_message_join(chat_id, message_id) VALUES(?, ?)", [chat, message]) }
        for index in 0..<attachments {
            try run("INSERT INTO attachment(guid, filename) VALUES(?, ?)", ["att-\(message)-\(index)", "~/fixture.bin"])
            try run("INSERT INTO message_attachment_join(message_id, attachment_id) VALUES(?, ?)",
                    [message, sqlite3_last_insert_rowid(db)])
        }
        return message
    }

    private func handleRowID(_ id: String) throws -> Int64 {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT ROWID FROM handle WHERE id = ?", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        bind(statement, [id])
        if sqlite3_step(statement) == SQLITE_ROW { return sqlite3_column_int64(statement, 0) }
        try run("INSERT INTO handle(id) VALUES(?)", [id])
        return sqlite3_last_insert_rowid(db)
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "fixture", code: 3) }
        defer { sqlite3_finalize(statement) }
        bind(statement, values)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw NSError(domain: "fixture", code: 4) }
    }

    private func bind(_ statement: OpaquePointer?, _ values: [Any?]) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let v as String: sqlite3_bind_text(statement, index, v, -1, transient)
            case let v as Int: sqlite3_bind_int64(statement, index, Int64(v))
            case let v as Int64: sqlite3_bind_int64(statement, index, v)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(v.count), transient) }
            default: sqlite3_bind_null(statement, index)
            }
        }
    }
}

import CryptoKit
import Foundation

// iMessage companion (fork-only). Wire format for docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md.

public struct CompanionParticipant: Codable, Sendable, Equatable {
    public var handle: String
    public var name: String?
    public init(handle: String, name: String?) { self.handle = handle; self.name = name }
    enum CodingKeys: String, CodingKey { case handle, name }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
    }
}

public struct CompanionThread: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case direct, group }
    public var guid: String
    public var kind: Kind
    public var displayName: String?
    public var participants: [CompanionParticipant]
    public var participantsFingerprint: String
    public init(guid: String, kind: Kind, displayName: String?, participants: [CompanionParticipant],
                participantsFingerprint: String) {
        self.guid = guid; self.kind = kind; self.displayName = displayName
        self.participants = participants; self.participantsFingerprint = participantsFingerprint
    }
    enum CodingKeys: String, CodingKey {
        case guid, kind, displayName = "display_name", participants, participantsFingerprint = "participants_fingerprint"
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(guid, forKey: .guid)
        try c.encode(kind, forKey: .kind)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(participants, forKey: .participants)
        try c.encode(participantsFingerprint, forKey: .participantsFingerprint)
    }
}

public struct CompanionMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text, reaction, attachmentOnly = "attachment_only", unreadable, skipped
    }
    public var guid: String
    public var rowid: Int64
    public var threadGUID: String
    public var fromMe: Bool
    public var senderHandle: String?
    public var sentAt: Date
    public var kind: Kind
    public var text: String?
    public var replyToGUID: String?
    public var attachmentCount: Int
    public init(guid: String, rowid: Int64, threadGUID: String, fromMe: Bool, senderHandle: String?, sentAt: Date,
                kind: Kind, text: String?, replyToGUID: String?, attachmentCount: Int) {
        self.guid = guid; self.rowid = rowid; self.threadGUID = threadGUID; self.fromMe = fromMe
        self.senderHandle = senderHandle; self.sentAt = sentAt; self.kind = kind; self.text = text
        self.replyToGUID = replyToGUID; self.attachmentCount = attachmentCount
    }
    enum CodingKeys: String, CodingKey {
        case guid, rowid, threadGUID = "thread_guid", fromMe = "from_me", senderHandle = "sender_handle",
             sentAt = "sent_at", kind, text, replyToGUID = "reply_to_guid", attachmentCount = "attachment_count"
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(guid, forKey: .guid)
        try c.encode(rowid, forKey: .rowid)
        try c.encode(threadGUID, forKey: .threadGUID)
        try c.encode(fromMe, forKey: .fromMe)
        try c.encode(senderHandle, forKey: .senderHandle)
        try c.encode(sentAt, forKey: .sentAt)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encode(replyToGUID, forKey: .replyToGUID)
        try c.encode(attachmentCount, forKey: .attachmentCount)
    }
}

public struct UplinkBatch: Codable, Sendable, Equatable {
    public var deviceID: String
    public var batchID: UUID
    public var cursor: Int64
    public var firstRun: Bool
    public var threads: [CompanionThread]
    public var messages: [CompanionMessage]
    public init(deviceID: String, batchID: UUID, cursor: Int64, firstRun: Bool, threads: [CompanionThread],
                messages: [CompanionMessage]) {
        self.deviceID = deviceID; self.batchID = batchID; self.cursor = cursor; self.firstRun = firstRun
        self.threads = threads; self.messages = messages
    }
    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id", batchID = "batch_id", cursor, firstRun = "first_run", threads, messages
    }
}

public struct UplinkAck: Codable, Sendable, Equatable {
    public var acceptedCursor: Int64
    public init(acceptedCursor: Int64) { self.acceptedCursor = acceptedCursor }
    enum CodingKeys: String, CodingKey { case acceptedCursor = "accepted_cursor" }
}

/// Lowercase hex SHA-256 of the normalized handles, sorted and joined with "\n" (contract: participants_fingerprint).
public enum CompanionFingerprint {
    public static func of(handles: [String]) -> String {
        let joined = handles.map(ChatResolver.normalize).sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum CompanionJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

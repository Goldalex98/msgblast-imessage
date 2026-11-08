# Phase 1, Mac side: read and uplink — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the fork app reads every new iMessage (1:1 and group) from `chat.db`, scrubs it on the Mac, and uplinks it to HomeChat over outbound HTTPS, with a persisted cursor, a pause switch and a status section. No sending.

**Architecture:** new files only, under `msgblast/Core/Companion/` (framework target, testable, no UI) and `msgblast/Companion/` (app target: Contacts names, status model, SwiftUI section). A `CompanionService` actor polls its own read-only SQLite connection, reads rows after the cursor, decodes `attributedBody` with `NSUnarchiver`, scrubs, attaches Contacts names, posts one batch and advances the cursor only on HomeChat's acknowledgement. Two upstream files get one small hook each.

**Tech Stack:** Swift 6.0 language mode, macOS 15.0 target, Xcode 27; raw `SQLite3` (as `MessagesDatabase` does); Foundation `NSUnarchiver`; `URLSession` async/await; Security (`SecItem*`); Contacts (`CNContactStore`); SwiftUI with `ObservableObject`; XCTest.

**Spec:** `docs/superpowers/specs/2026-11-07-imessage-companion-design.md` (§3, §4.1, §4.2, §5.1–5.2, §6, §7 phase 1, §10.1, §10.9). Phase 0 decisions: `docs/superpowers/spikes/2026-11-phase0-results.md` ("Phase 1 decisions from phase 0").

## Global Constraints

- Never write to `chat.db`, mark messages read, send typing indicators or touch Messages' UI state. Open it `SQLITE_OPEN_READONLY` only.
- No sending of any kind in phase 1: no AppleScript, no `osascript`, no Messages automation calls in new code.
- Public repo: no names, phone numbers, emails, chat GUIDs, message text, the HomeChat host or tokens in code, tests, fixtures, docs, commits or PR text. Test data is synthetic: handles `+15550100001`-style and `test@example.invalid`.
- The HomeChat URL and `device_id` live in a local config file in the app's support folder (outside the repo); the bearer token lives in the Keychain. Neither is logged or shown in full in the UI.
- Outbound HTTPS only: no listening port, no tunnel, redirects rejected, `https` scheme required.
- First run uplinks only the last 3 days (§4.1).
- Scrubber: anything shaped like a US SSN becomes `[SSN removed]` before it leaves the Mac (§4.1).
- New code in new files; every edited upstream file is listed in `FORK.md`. Xcode project changes only via `python3 scripts/generate_project.py`, regenerated `msgblast.xcodeproj` committed.
- Core types are `public`, `Sendable` structs where they cross actors; app-side models are `@MainActor ObservableObject` (upstream style, no `@Observable`).
- Gate before calling any task done (from `.claude/agents/quality-gate.md`, on the MacBook): `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v` and `xcodebuild -project msgblast.xcodeproj -scheme msgblast -configuration Debug -derivedDataPath build/contributor-tests -destination 'platform=macOS,arch=arm64' MSGBLAST_APP_BUNDLE_IDENTIFIER=com.msgblast.contributor-tests ASSETCATALOG_COMPILER_APPICON_NAME=AppIconDemo -only-testing:msgblastTests test`. Single test classes: append `-only-testing:msgblastTests/<Class>` instead.

## Review Focus

1. **An SSN that exists only in `attributedBody`.** The scrubber must run after decoding, on the final text. Test: `CompanionServiceTests.test_ssnInAttributedBodyOnlyIsScrubbed` (Task 7).
2. **The app quits or the network drops after HomeChat stored a batch but before the cursor was saved.** The replay must be harmless and nothing may be skipped: the cursor advances only to `accepted_cursor`, and the batch is rebuilt from the saved cursor. Test: `CompanionServiceTests.test_failedPostKeepsCursorAndReplaysSameRows` (Task 7).
3. **Full Disk Access revoked, or `chat.db` missing, while running.** No crash, the cursor is unchanged, and the status says why. Test: `CompanionServiceTests.test_unreadableDatabaseReportsPermission` (Task 7).
4. **A long offline stretch leaves thousands of new rows.** Batches stay ≤ 200 messages and the cursor advances batch by batch. Test: `CompanionServiceTests.test_backlogIsBatched` (Task 7).
5. **A group with no display name while Contacts access is denied.** Handles are still sent, names are `null`, and the status shows Contacts as off. Tests: `ContactNameResolverTests.test_deniedReturnsNoNames` (Task 8) and `CompanionReaderTests.test_groupWithoutDisplayName` (Task 4).

Known gap, out of scope for phase 1: edits and unsends rewrite existing rows, so a ROWID cursor doesn't see them. Recorded in the contract (Task 1).

---

### Task 1: The uplink contract

**Files:**
- Create: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`

**Interfaces:**
- Produces: the wire format Tasks 2 and 6 encode, and HomeChat's amendment implements.

- [ ] **Step 1: Write the contract** with these decisions (field names final):
  - Base URL: `uplink_url` from the local config (the bot hostname, never written in this repo). All routes are under `/imsg/`. Auth: `Authorization: Bearer <token>`. The token is a per-device secret issued by HomeChat, stored hashed on OVH and compared in constant time (spec §4.2). `Content-Type: application/json`, UTF-8.
  - `POST /imsg/messages`, body `UplinkBatch`:
    `{"device_id": str, "batch_id": uuid-str, "cursor": int (highest ROWID in this batch), "first_run": bool, "threads": [Thread], "messages": [Message]}`.
    `Thread = {"guid": str, "kind": "direct"|"group", "display_name": str|null, "participants": [{"handle": str, "name": str|null}], "participants_fingerprint": hex-str}`.
    `Message = {"guid": str, "rowid": int, "thread_guid": str, "from_me": bool, "sender_handle": str|null, "sent_at": ISO-8601 UTC str, "kind": "text"|"reaction"|"attachment_only"|"unreadable"|"skipped", "text": str|null, "reply_to_guid": str|null, "attachment_count": int}`.
    `threads` lists each thread referenced by this batch's messages, once.
  - Response `200 {"accepted_cursor": int}`. The server is idempotent on message `guid`, so a replayed batch is harmless. `401` bad or revoked token (stop until the token changes), `413` too large, `422` schema error (both stop and show the error), `429`/`5xx`/transport errors retry with backoff.
  - Limits: ≤ 200 messages per batch; `text` ≤ 4000 characters (longer is cut, ending `…[truncated]`); body ≤ 1 MB.
  - Text rules: `text` has SSNs replaced by `[SSN removed]`. `kind: "skipped"` (short-code senders, verification codes) carries `text: null`, so codes never leave the Mac. Reactions carry `text: null`. Attachments are a count only, never names or files.
  - `participants_fingerprint`: lowercase hex SHA-256 of the participants' normalized handles (`ChatResolver.normalize`), sorted, joined with `\n`. Phase 3 compares it before a send.
  - Reserved for phase 3, shape only: `GET /imsg/sends?wait=25` and `POST /imsg/send-results`, as in spec §4.2.
  - Known gaps: edited and unsent messages, and delivery-state changes, aren't uplinked (the cursor sees new rows only). Times are the Mac's database times.
- [ ] **Step 2: Scan for personal data.** Run `grep -nE '[0-9]{10}|@[a-z]+\.(com|net)|https?://' docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`. Expected: no output.
- [ ] **Step 3: Commit** `docs: add the imsg uplink contract`.

### Task 2: Wire models and the fingerprint

**Files:**
- Create: `msgblast/Core/Companion/CompanionModels.swift`
- Test: `msgblastTests/CompanionModelsTests.swift`

**Interfaces:**
- Produces (all `public struct … : Codable, Sendable, Equatable`, snake_case keys via `CodingKeys`):
  - `CompanionParticipant { handle: String; name: String? }`
  - `CompanionThread { guid: String; kind: Kind; displayName: String?; participants: [CompanionParticipant]; participantsFingerprint: String }` with `enum Kind: String { case direct, group }`
  - `CompanionMessage { guid: String; rowid: Int64; threadGUID: String; fromMe: Bool; senderHandle: String?; sentAt: Date; kind: Kind; text: String?; replyToGUID: String?; attachmentCount: Int }` with `enum Kind: String { case text, reaction, attachmentOnly = "attachment_only", unreadable, skipped }`
  - `UplinkBatch { deviceID: String; batchID: UUID; cursor: Int64; firstRun: Bool; threads: [CompanionThread]; messages: [CompanionMessage] }`
  - `UplinkAck { acceptedCursor: Int64 }`
  - `public enum CompanionFingerprint { static func of(handles: [String]) -> String }`
  - `public enum CompanionJSON { static let encoder: JSONEncoder; static let decoder: JSONDecoder }` (ISO-8601 dates, `.sortedKeys`)

- [ ] **Step 1: Write the failing tests.**
  - `test_batchEncodesContractKeys`: encode a one-thread, one-message batch; the JSON object's keys are exactly `device_id, batch_id, cursor, first_run, threads, messages`; the message has `thread_guid`, `from_me`, `sent_at` (string ending `Z`), `kind == "attachment_only"` for `.attachmentOnly`.
  - `test_fingerprintIsOrderAndFormatInsensitive`: `of(handles: ["+1 (555) 010-0001", "Test@Example.invalid"]) == of(handles: ["test@example.invalid", "+15550100001"])`, is 64 lowercase hex characters, and differs from `of(handles: ["+15550100001"])`.
  - `test_ackDecodes`: `{"accepted_cursor": 42}` decodes to `UplinkAck(acceptedCursor: 42)`.
- [ ] **Step 2: Regenerate and run them failing.** `python3 scripts/generate_project.py`, then the gate's `xcodebuild` with `-only-testing:msgblastTests/CompanionModelsTests`. Expected: build failure, types not found.
- [ ] **Step 3: Implement** the types. The fingerprint uses `ChatResolver.normalize`, sorts, joins with `"\n"`, hashes with `CryptoKit.SHA256`.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `CompanionModels.swift`, the test and the regenerated project: `Add companion wire models and participant fingerprint`.

### Task 3: The `attributedBody` decoder

**Files:**
- Create: `msgblast/Core/Companion/AttributedBodyDecoder.swift`
- Test: `msgblastTests/AttributedBodyDecoderTests.swift`

**Interfaces:**
- Produces: `public enum AttributedBodyDecoder { public static func text(from blob: Data?) -> String? }`

- [ ] **Step 1: Write the failing tests.** Blobs are made in the test with `NSArchiver.archivedData(withRootObject: NSAttributedString(string: s))` (the same typedstream format Messages stores).
  - `test_roundTrips`: `"hi"`, a 200-character string, a 70,000-character string and `"café 👋"` all decode back exactly.
  - `test_badInputReturnsNil`: `nil`, empty `Data`, 16 random bytes, an archived blob truncated to half its length, and an archived blob whose string length byte is raised past the end all return `nil` and don't crash.
  - `test_nonAttributedRootReturnsNil`: an archived `NSNumber` returns `nil`.
- [ ] **Step 2: Run them failing** (`-only-testing:msgblastTests/AttributedBodyDecoderTests`). Expected: build failure.
- [ ] **Step 3: Implement** with a gate, then the system reader. `NSUnarchiver` raises an `NSException` on corrupt input, which Swift can't catch and which would crash the whole app. The project has no Objective-C to host an `@try` shim, so every blob passes a structural pre-check before `NSUnarchiver.unarchiveObject(with:)` ever sees it:
  1. Bytes 1…12 are `\x0bstreamtyped`.
  2. The blob contains `NSAttributedString`, then `NSString`.
  3. The `+` string marker after `NSString` is followed by a length (1 byte; `0x81` + 2 bytes LE; `0x82` + 4 bytes LE) whose payload lies wholly inside the blob.

  Any failure returns `nil` without calling `NSUnarchiver`. Then return `(object as? NSAttributedString)?.string`. The deprecation warning is accepted. Comment that the gate mirrors the Python scanner in `companion/spikes/bodies.py`, which stays as the fixture oracle.
- [ ] **Step 4: Run the tests.** Expected: pass, with the truncated and random-bytes cases stopped by the gate. Residual risk, recorded in `FORK.md`: a blob that is structurally valid but internally corrupt could still raise. Spike (a) saw none in 14 days of real data.
- [ ] **Step 5: Commit** `Add attributedBody decoder using NSUnarchiver`.

### Task 4: The group-aware reader

**Files:**
- Create: `msgblast/Core/Companion/CompanionReader.swift`
- Create: `msgblastTests/CompanionFixture.swift` (synthetic `chat.db` builder)
- Test: `msgblastTests/CompanionReaderTests.swift`

**Interfaces:**
- Consumes: `AttributedBodyDecoder.text(from:)`, `CompanionThread`, `CompanionMessage`, `CompanionFingerprint`.
- Produces:
  - `public struct CompanionReadResult: Sendable, Equatable { messages: [CompanionMessage]; lastScannedRowID: Int64 }`. `messages[].text` is decoded but not yet scrubbed. `lastScannedRowID` is the highest ROWID the query looked at, including rows it dropped, so the cursor can pass them.
  - `public final class CompanionReader { public init(path: String) throws(CompanionReaderError); public func dataVersion() throws(CompanionReaderError) -> Int64; public func maxRowID() throws(CompanionReaderError) -> Int64; public func firstRowID(since: Date) throws(CompanionReaderError) -> Int64?; public func rows(after rowID: Int64, limit: Int) throws(CompanionReaderError) -> CompanionReadResult; public func threads(guids: Set<String>) throws(CompanionReaderError) -> [CompanionThread] }`
  - `public enum CompanionReaderError: Error, Equatable { case unreadable(Int32), unsupportedSchema(String), query(String) }` (`unreadable` carries the SQLite result code; `SQLITE_CANTOPEN`/`SQLITE_AUTH`/`SQLITE_PERM` mean permission or missing file)
  - Test helper: `struct CompanionFixture { static func make() throws -> URL; func addChat(guid:style:displayName:handles:) ; func addMessage(...) }`, with real columns: `message(ROWID, guid, text, attributedBody, date, is_from_me, handle_id, associated_message_type, thread_originator_guid, cache_has_attachments)`, `chat(ROWID, guid, style, display_name)`, `handle(ROWID, id)`, `chat_handle_join`, `chat_message_join`, `attachment`, `message_attachment_join`. Dates in nanoseconds since 2001-01-01.

- [ ] **Step 1: Write the failing tests.**
  - `test_rowsAfterCursorInRowIDOrder`: 5 messages across a 1:1 (style 45) and a group (style 43); `rows(after: 2, limit: 10).messages` are ROWIDs 3, 4, 5 in order, each with its `threadGUID`, and `lastScannedRowID == 5`.
  - `test_limitCaps`: 250 rows, `rows(after: 0, limit: 200)` has 200 messages and `lastScannedRowID == 200`.
  - `test_orphanRowsAdvanceScan`: ROWIDs 6 and 7 are in no chat; `rows(after: 5, limit: 10)` has no messages and `lastScannedRowID == 7`.
  - `test_messageInTwoChatsAppearsOnce`: a row joined to two chats appears once, under the chat with the lower chat ROWID.
  - `test_groupSenderAndDirection`: an inbound group row has `senderHandle` equal to its handle and `fromMe == false`; an outgoing row has `fromMe == true` and `senderHandle == nil`.
  - `test_bodyFallsBackToAttributedBody`: `text` NULL plus an archived `attributedBody` gives `kind == .text` and the decoded text; both NULL with `cache_has_attachments = 1` gives `.attachmentOnly` and `attachmentCount == 1`; both NULL without attachments gives `.unreadable`; a corrupt `attributedBody` gives `.unreadable`.
  - `test_objectReplacementStripped`: `text` `"\u{FFFC}see this"` becomes `"see this"`.
  - `test_reactionsAreKindReactionWithoutText`: `associated_message_type = 2001` gives `kind == .reaction` and `text == nil`.
  - `test_threadsFor`: `threads(guids:)` returns a group with `kind == .group`, its `displayName`, both participants (names `nil`), and the fingerprint of its handles; a style-45 chat gives `.direct`.
  - `test_groupWithoutDisplayName`: empty `display_name` gives `displayName == nil`.
  - `test_firstRowIDSince`: rows dated 5, 2 and 1 days ago; `firstRowID(since: now − 3 d)` is the 2-days-ago row's ROWID; with nothing newer it returns `nil`.
  - `test_missingFileIsUnreadable`: a path that doesn't exist throws `.unreadable`.
  - `test_readOnly`: after reading, the fixture file's modification date and size are unchanged.
- [ ] **Step 2: Run them failing.**
- [ ] **Step 3: Implement** with its own `sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)` plus `busy_timeout` 1500 ms, as `MessagesDatabase` does. The query joins `chat_message_join` → `chat` (guid, style) and left-joins `handle` for the sender, `WHERE m.ROWID > ? ORDER BY m.ROWID LIMIT ?`, with one row per message (the lowest chat ROWID when a message is joined to several chats). Dates: `raw > 1e12 ? raw / 1e9 : raw` seconds since the reference date (same as `MessagesDatabase.messageDate`). Strip U+FFFC and trim whitespace. Messages in no chat are skipped (they have no thread). Check required columns with `PRAGMA table_info` and throw `.unsupportedSchema` if any are missing.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `Add group-aware companion reader`.

### Task 5: The scrubber

**Files:**
- Create: `msgblast/Core/Companion/CompanionScrubber.swift`
- Test: `msgblastTests/CompanionScrubberTests.swift`

**Interfaces:**
- Consumes: `CompanionMessage`, `CompanionParticipant`.
- Produces: `public enum CompanionScrubber { public static func scrub(_ text: String) -> String; public static func isSkipped(senderHandle: String?, text: String?) -> Bool; public static func apply(to message: CompanionMessage) -> CompanionMessage }`. `apply` truncates text to 4000 characters (ending `…[truncated]`), scrubs SSNs, and turns skipped messages into `kind: .skipped, text: nil`.

- [ ] **Step 1: Write the failing tests.**
  - `test_ssnShapes`: `"123-45-6789"`, `"123 45 6789"` and `"my ssn is 123456789."` all become `[SSN removed]` in place. Unchanged: a 10-digit phone `"5550100001"`, `"call 555-010-0001"`, `"order 1234567890123"`, a date `"2026-11-08"`, and `"$123.45"`.
  - `test_shortCodeSenderSkipped`: `isSkipped(senderHandle: "72975", text: "hello")` and `isSkipped(senderHandle: "262966", text: nil)` are true; `"+15550100001"` is false.
  - `test_verificationCodeSkipped`: true for `"Your verification code is 482913"`, `"123456 is your login code"`, `"Use passcode 4829 to sign in"`, `"Your OTP: 902113"`; false for `"the code review is at 3"` and `"meet at 1234 Main St"`.
  - `test_applySkippedDropsText`: a skipped message keeps its guid, thread and `fromMe`, with `kind == .skipped` and `text == nil`.
  - `test_applyTruncates`: 5000 characters become 4000, ending `…[truncated]`.
- [ ] **Step 2: Run them failing.**
- [ ] **Step 3: Implement.** SSN: `NSRegularExpression` `(?<![0-9])[0-9]{3}[- ]?[0-9]{2}[- ]?[0-9]{4}(?![0-9])`, which over-removes bare 9-digit numbers on purpose (spec: "anything shaped like" an SSN). Short code: all digits, 3–6 long. Verification code: case-insensitive `\b(code|passcode|otp|verification|one[- ]time)\b` within 40 characters of a standalone 4–8 digit number, in either order.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `Add companion scrubber`.

### Task 6: Config, token and uplink client

**Files:**
- Create: `msgblast/Core/Companion/CompanionConfig.swift`
- Create: `msgblast/Core/Companion/CompanionTokenStore.swift`
- Create: `msgblast/Core/Companion/UplinkClient.swift`
- Test: `msgblastTests/CompanionConfigTests.swift`, `msgblastTests/UplinkClientTests.swift`

**Interfaces:**
- Consumes: `UplinkBatch`, `UplinkAck`, `CompanionJSON`.
- Produces:
  - `public struct CompanionConfig: Codable, Sendable, Equatable { uplinkURL: URL?; deviceID: String; paused: Bool; cursor: Int64? }`, with `public static func load(from: URL) -> CompanionConfig` (missing or corrupt file gives a fresh config with a new `deviceID` of the form `mac-<8 hex>`, `paused: false`, `cursor: nil`) and `public func save(to: URL) throws` (atomic, mode 0600). `public static func defaultURL(supportFolder: String) -> URL` is `~/Library/Application Support/<supportFolder>/companion.json`.
  - `public protocol CompanionTokenStoring: Sendable { func read() -> String?; func write(_ token: String?) -> Bool }`, with `public struct KeychainTokenStore: CompanionTokenStoring` (generic password, service `"<bundle id>.companion-uplink"`, accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, tolerant of `errSecMissingEntitlement` like `GrokBotService`).
  - `public struct UplinkClient: Sendable { public init(baseURL: URL, token: String, session: URLSession = .companionEphemeral); public func post(_ batch: UplinkBatch) async throws(UplinkError) -> UplinkAck }`
  - `public enum UplinkError: Error, Equatable { case notHTTPS, unauthorized, rejected(Int), retryable(Int?), badResponse }` (`rejected` for 413/422/other 4xx; `retryable(nil)` for transport errors)
  - `extension URLSession { public static let companionEphemeral: URLSession }`: ephemeral, 30 s request timeout, a delegate that rejects every redirect (like `NoTelemetryRedirects`).

- [ ] **Step 1: Write the failing tests.**
  - `CompanionConfigTests.test_missingFileGivesFreshConfig`, `test_roundTripAndMode0600`, `test_corruptFileGivesFreshConfig`.
  - `UplinkClientTests` with a `URLProtocol` stub injected through a test `URLSession`:
    - `test_postsToImsgMessagesWithBearer`: method `POST`, path `/imsg/messages`, header `Authorization: Bearer test-token`, `Content-Type: application/json`, and a body that decodes back to the batch.
    - `test_200ReturnsAck`, `test_401IsUnauthorized`, `test_422IsRejected`, `test_503IsRetryable`, `test_transportErrorIsRetryable`, `test_garbage200IsBadResponse`.
    - `test_httpBaseURLRefused`: `http://` throws `.notHTTPS` and makes no request.
- [ ] **Step 2: Run them failing.**
- [ ] **Step 3: Implement.** `post` builds the URL with `appendingPathComponent("imsg/messages")` and encodes with `CompanionJSON.encoder`. The token store isn't unit-tested against the real Keychain; a fake `CompanionTokenStoring` is used by Task 7.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `Add companion config, Keychain token store and uplink client`.

### Task 7: The companion service

**Files:**
- Create: `msgblast/Core/Companion/CompanionService.swift`
- Test: `msgblastTests/CompanionServiceTests.swift`

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - `public protocol CompanionNameResolving: Sendable { func names(for handles: [String]) async -> [String: String] }`
  - `public protocol CompanionUplinking: Sendable { func post(_ batch: UplinkBatch) async throws(UplinkError) -> UplinkAck }` (`UplinkClient` conforms)
  - `public struct CompanionStatus: Sendable, Equatable { state: State; lastUplinkAt: Date?; lastBatchCount: Int; cursor: Int64?; pendingEstimate: Int64? }` with `enum State: Sendable, Equatable { case paused, notConfigured, noDatabaseAccess, idle, uplinking, offline(retryIn: TimeInterval), stopped(String) }`
  - `public actor CompanionService { public init(databasePath: String, configURL: URL, tokens: any CompanionTokenStoring, names: any CompanionNameResolving, makeUplink: @Sendable (URL, String) -> any CompanionUplinking, now: @Sendable () -> Date = Date.init); public func tick() async -> CompanionStatus; public func setPaused(_ paused: Bool) async -> CompanionStatus; public var status: CompanionStatus { get } }`
- `tick()` is one cycle and holds no timer, so it's testable. Per cycle: paused → `.paused`; no URL or token → `.notConfigured`; inside a backoff window → `.offline`; open the reader (failure → `.noDatabaseAccess`, cursor untouched); if `config.cursor == nil`, set the start to `(firstRowID(since: now − 3 days) ?? maxRowID + 1) − 1` and mark `firstRun`; skip the cycle when `dataVersion` is unchanged and the last post succeeded; read `rows(after: cursor, limit: 200)`; if it has no messages but `lastScannedRowID > cursor`, save `cursor = lastScannedRowID` without posting; otherwise build the batch with `cursor = lastScannedRowID`, apply the scrubber, resolve names for every participant handle in the batch's threads, and post; on success save `cursor = ack.acceptedCursor` (never higher than the batch's own cursor), and if the batch was full, run again on the next tick without waiting for `dataVersion`; on `.retryable` back off 5 s doubling to 300 s; on `.unauthorized` or `.rejected` stop (`.stopped`) until the config or token changes.

- [ ] **Step 1: Write the failing tests**, using `CompanionFixture`, a fake token store, a fake name resolver and a recording fake uplink:
  - `test_firstRunUplinksLastThreeDaysOnly`: rows 5, 2 and 1 days old; the first post contains only the 2- and 1-day rows, with `firstRun == true`; the next batch has `firstRun == false`.
  - `test_cursorAdvancesOnlyOnAck` and `test_failedPostKeepsCursorAndReplaysSameRows`: a 503 leaves `config.cursor` unchanged, and after the backoff the next post has the same message GUIDs.
  - `test_ackBelowBatchCursorIsRespected`: an ack of 3 for a batch ending at 5 saves 3.
  - `test_orphanOnlyStretchAdvancesWithoutPost`: only chat-less rows are new; the cursor moves past them and nothing is posted.
  - `test_backlogIsBatched`: 450 new rows give posts of 200, 200 and 50 on three ticks, with the cursor at each batch's end.
  - `test_ssnInAttributedBodyOnlyIsScrubbed`: an `attributedBody`-only row containing `123-45-6789` is posted with `[SSN removed]` and no digits.
  - `test_unreadableDatabaseReportsPermission`: a missing database path gives `.noDatabaseAccess` and no post, and the cursor is unchanged.
  - `test_pausedDoesNothing`: after `setPaused(true)`, `tick()` doesn't open the database or post, and the `paused` flag persists in the config.
  - `test_unauthorizedStops`: a 401 gives `.stopped`, and later ticks don't post until a new token is written.
  - `test_namesAttached`: the resolver's names land in `threads[].participants[].name`.
  - `test_notConfigured`: no `uplinkURL` gives `.notConfigured` and no database open.
- [ ] **Step 2: Run them failing.**
- [ ] **Step 3: Implement** `CompanionService` per the cycle above. Errors never include message text or handles: `.stopped` carries only the HTTP status or error kind.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `Add companion service: cursor, batching, backoff, pause`.

### Task 8: Contacts names (app target)

**Files:**
- Create: `msgblast/Companion/ContactNameResolver.swift`
- Test: `msgblastTests/ContactNameResolverTests.swift` (add `msgblast/Companion/ContactNameResolver.swift` to the tests target in `scripts/generate_project.py` beside the existing `MessagesAccessGuide.swift` special case; list that edit in `FORK.md`)

**Interfaces:**
- Consumes: `CompanionNameResolving`, `ChatResolver.normalize`.
- Produces: `final class ContactNameResolver: CompanionNameResolving, @unchecked Sendable { init(store: ContactSource = CNContactStore(), refreshEvery: TimeInterval = 600); var isAuthorized: Bool { get } }`, with `protocol ContactSource { func authorized() -> Bool; func allHandles() -> [(name: String, handles: [String])] }` so tests use a fake.
- Matching key: emails lowercased; phone numbers by their last 10 digits. The display name is `CNContactFormatter` full name, falling back to the organization name.

- [ ] **Step 1: Write the failing tests:** `test_matchesPhoneAcrossFormats` (`"+1 (555) 010-0001"` in Contacts matches handle `+15550100001`), `test_matchesEmailCaseInsensitive`, `test_unknownHandleHasNoName`, `test_deniedReturnsNoNames` (not authorized gives `[:]` and `isAuthorized == false`).
- [ ] **Step 2: Run them failing.**
- [ ] **Step 3: Implement.** It never requests access itself; the existing onboarding already asks for Contacts.
- [ ] **Step 4: Run the tests.** Expected: pass.
- [ ] **Step 5: Commit** `Add Contacts name resolver for the companion`.

### Task 9: Status section and app wiring

**Files:**
- Create: `msgblast/Companion/CompanionController.swift` (`@MainActor final class CompanionController: ObservableObject`)
- Create: `msgblast/Companion/CompanionStatusView.swift`
- Modify: `msgblast/App/msgblastApp.swift` (`AppStartup.init`: create and start one `CompanionController` when `model` exists; pass it to `Settings`)
- Modify: `msgblast/Windows/Views.swift` (`AppSettingsView`: add `Section("iMessage companion") { CompanionStatusView(controller:) }`; raise the fixed frame height only if the section doesn't fit)
- Modify: `FORK.md` (both upstream edits, plus Task 8's generator edit)

**Interfaces:**
- Consumes: `CompanionService`, `KeychainTokenStore`, `ContactNameResolver`, `UplinkClient`, `CompanionConfig.defaultURL`, `SupportDirectory.folderName(demo:override:bundleIdentifier:)` with the Info.plist key `msgblastSupportDirectory`.
- Produces: `CompanionController { @Published private(set) var status: CompanionStatus; @Published var uplinkHost: String (host only, for display); func start(); func setPaused(_:); func saveSettings(url: String, token: String?) }`. `start()` ticks every 2 s with a `Timer` hopping to `Task { @MainActor in … }`, the same pattern as `AppModel`.

- [ ] **Step 1: Write the view**, compact, with drill-down detail. One status line: a coloured dot and the state in words ("Uplinking", "Paused", "Mac offline, retrying in 40 s", "Needs Full Disk Access", "Not set up", "Stopped: token rejected"). A pause toggle. "Last uplink 2 min ago · 14 messages". Below, a `DisclosureGroup("Details")` with the HomeChat host (host only), a token field (`SecureField`, write-only, shows "Saved" when set), the device ID, the cursor, the permission rows (Full Disk Access from the existing `AppPermissions.history`, Contacts from `ContactNameResolver.isAuthorized`) and a "Save" button.
- [ ] **Step 2: Wire** `AppStartup` and `AppSettingsView` as listed. Add nothing else to upstream files.
- [ ] **Step 3: Regenerate the project and run the full Mac gate.** Expected: Python tests OK; `TEST SUCCEEDED` with every previous test still passing.
- [ ] **Step 4: Build the fork app** (`python3 -I companion/build_fork_app.py --sha $(git rev-parse HEAD) --output ~/msgblast-imessage-builds`), install it over the old copy, open Settings, and screenshot the section in its "Not set up" state. Expected: the section renders, the pause toggle persists across a relaunch, and Full Disk Access shows as allowed (kept from spike (g)).
- [ ] **Step 5: Commit** `Add the companion status section and start the service`.

### Task 10: Mac-side acceptance and handoff to HomeChat

**Files:**
- Create: `docs/superpowers/runbooks/phase1-mac-acceptance.md`
- Modify: `.claude/STATUS.md`, `.claude/LOG.md`

- [ ] **Step 1: Write the runbook.** Alex pastes the HomeChat URL and a device token (issued by HomeChat's phase 1 work) into the section. Then:
  1. The status reaches "Uplinking", then "Idle".
  2. HomeChat's store shows the last 3 days' threads, re-read on OVH by HomeChat's own tooling, not from here.
  3. A text from a test contact appears in HomeChat within 10 s.
  4. Toggling pause stops uplinks, and unpausing catches up.
  5. Quitting the app for 5 minutes and reopening misses nothing (cursor replay).
  6. Turning Wi-Fi off shows "Mac offline", and turning it back on recovers.
- [ ] **Step 2: Hand off.** Record in STATUS that phase 1's acceptance ("a real unanswered text shows up on the desk and in the update, and a real reply clears it, seen on Alex's phone and re-read on the desk") needs HomeChat's half: `/imsg/messages`, token issuance, the store, the flagger, the update and desk items. Those are built in `homechat-bot` against `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`.
- [ ] **Step 3: Commit** `Add phase 1 Mac acceptance runbook`. Then a fork PR; merge on green fork CI (standing rule).

## Not in this plan

- HomeChat's half (routes, token issuing, store, flagger, desk, update): `homechat-bot`, under its rules and Alex's 2026-11-07 pre-approval (spec §9).
- Sending (phase 3), calendar (phase 2), Duet tools (phase 4).
- Edits, unsends and delivery-state uplinks.

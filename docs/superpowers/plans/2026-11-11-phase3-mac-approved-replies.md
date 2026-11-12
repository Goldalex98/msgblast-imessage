# Phase 3 (Approved replies), Mac side: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The fork app fetches sends Alex approved on HomeChat, re-checks them, sends each one at most once to its existing iMessage thread, and reports `sent` / `not_sent` / `ambiguous` with the history anchor.

**Architecture:** A new `CompanionSendExecutor` actor in `msgblast/Core/Companion/` runs beside `CompanionService`, with its own long-poll loop. It is built from small pure parts: wire models, send rules, a fixed AppleScript that takes everything as `argv`, a read-back over `chat.db` with a ROWID baseline, an outcome decision and an on-disk send ledger (no message text). `CompanionController` starts it; a Settings toggle (off by default) gates it.

**Tech Stack:** Swift 6.4, SwiftUI, SQLite (read-only), `/usr/bin/osascript` via `Process`, CryptoKit SHA-256, XCTest with synthetic `chat.db` fixtures.

**Spec:** `docs/superpowers/specs/2026-11-07-imessage-companion-design.md` (§4.1 send executor, §4.2, §5.5, §6, §7 phase 3, §10.8). Input notes: `docs/superpowers/specs/2026-11-10-phase3-send-notes.md`. Contract: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`.

**Out of scope here:** HomeChat's half (the send queue, `N yes` / `N edit:` approval, the confirmation echo, expiry notice, the 30/day cap on its side, its audit with exact text, the WhatsApp outcome messages). It is built in `homechat-bot` under that repo's rules against the contract fixed in Task 1. Phase 2 (calendar) needs nothing on the Mac, so this phase can go first.

## Decisions (Alex, 2026-11-11)

| Question (send notes) | Answer |
|---|---|
| 1. A send record still `in_progress` at launch | Resolve to `sent` when **exactly one** outgoing row in that chat after the baseline matches the approved text exactly, with `error` = 0 and `is_sent` = 1; otherwise `ambiguous`. Never re-sent either way. |
| 2. Read-back wait after the script returns | **20 s**, polling every 1 s. |
| 3. Is "delivered" worth a WhatsApp message | No (default, not asked): `sent` is enough. `is_delivered` is not read. |
| 4. Mac-side audit | **Hash and length only.** The exact text lives only on HomeChat. |
| 5. Scope | **iMessage only, 1:1 and group** threads. SMS and RCS refused. |

## Global Constraints

- Never write `chat.db`, mark messages read, send typing indicators or touch Messages' UI state; all reads are read-only SQLite (CLAUDE.md).
- One approval sends one message: text only, to an existing thread, participant set unchanged since approval (§5.5). Never retry an `ambiguous` or uncertain send (CLAUDE.md, §5.5).
- A `send_id` that has any ledger record is never dispatched again, whatever HomeChat sends back.
- Expiry: refuse when `now >= expires_at`, checked at fetch and again immediately before dispatch; also refuse when `expires_at - approved_at > 600 s` (§5.5's 10 minutes).
- Text rules (send notes Borrow 3): non-empty after trimming whitespace and newlines; at most 4000 `Character`s; no control characters other than tab, LF and CR. The text is sent exactly as approved (no trimming).
- Text binding (Borrow 5): `text_sha256` is lowercase hex SHA-256 of the UTF-8 text; the Mac recomputes it from the fetched text and refuses on mismatch; the Mac's result echoes its own hash.
- Mac cap: at most 30 dispatch attempts in any rolling 24 h, counted from the ledger (attempts, not successes; Borrow 7).
- Text and target reach AppleScript only as `argv` of a fixed script source, never inside the source (Borrow 2). Refuse a chat GUID or handle that starts with `-` or contains a control character.
- The Mac's ledger and logs hold no message text: send id, thread GUID, length, hash, times, baseline ROWID, outcome, anchor GUID, detail code. Thread GUIDs are stored only in the app's support folder, never in the repo.
- Result `detail` is one of the fixed codes in Task 1, never free text from Messages.
- Sends are off until Alex turns on "Send approved replies" in Settings; Paused also stops fetching and sending (§4.1).
- Public repo: tests use synthetic `chat.db` fixtures and invented handles only. No real sends in development; real sends happen only in the Task 10 acceptance, to a test contact, with Alex's yes.
- New files only under `msgblast/Core/Companion/`, `msgblast/Companion/` and `msgblastTests/Companion*.swift`, so the CI companion scope applies. After adding files run `python3 scripts/generate_project.py` and review the project diff. Each new test class is added to `COMPANION_SUITES` in `scripts/ci_native_scope.py` in the same task.
- Focused test run (Mac): `xcodebuild -project msgblast.xcodeproj -scheme msgblast -configuration Debug -derivedDataPath build/contributor-tests -destination 'platform=macOS,arch=arm64' MSGBLAST_APP_BUNDLE_IDENTIFIER=com.msgblast.contributor-tests ASSETCATALOG_COMPILER_APPICON_NAME=AppIconDemo -only-testing:msgblastTests/<Suite> test`. Below this is written `run <Suite>`.

## Review Focus

1. **Messages stores the text slightly differently** (a trailing space or newline). Exact match fails, so a send that went out reads as `ambiguous`; it must never be retried or read as `not_sent`. Pinned in Task 5 (`test_nearMatchIsAmbiguousNotNotSent`).
2. **Alex sends the same words from his phone in the same 20 s window.** That gives two matching rows, so the result is `ambiguous`, never the newer row. Task 5 (`test_twoMatchesAreAmbiguous`).
3. **HomeChat hands out the same `send_id` again** after a lost result post. The Mac must not dispatch it again; it re-posts the outcome it recorded. Task 8 (`test_redeliveredSendIsNotDispatchedAgain`).
4. **The Mac sleeps between fetch and dispatch** past `expires_at`. Expiry is re-checked right before the script runs. Task 8 (`test_expiryRecheckedBeforeDispatch`).
5. **A group's members change after approval**, or the thread became SMS. Refused as `not_sent` (`thread_changed` / `not_imessage`) before any script runs. Task 8 (`test_changedParticipantsRefusedBeforeDispatch`), Task 4 for the identity read.

---

### Task 1: Fix the send contract and wire models

**Files:**
- Modify: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md` (replace "Reserved for phase 3 (shape only)")
- Create: `msgblast/Core/Companion/CompanionSendModels.swift`
- Test: `msgblastTests/CompanionSendModelsTests.swift`; add `CompanionSendModelsTests` to `COMPANION_SUITES`

**Interfaces:**
- Produces:
  ```swift
  public struct ApprovedSend: Codable, Sendable, Equatable {
      public let sendID: String            // send_id (server-issued)
      public let threadGUID: String        // thread_guid
      public let participantsFingerprint: String  // participants_fingerprint (CompanionFingerprint.of)
      public let text: String
      public let textSHA256: String        // text_sha256
      public let approvedAt: Date          // approved_at
      public let expiresAt: Date           // expires_at
  }
  public struct SendsPage: Codable, Sendable, Equatable { public let sends: [ApprovedSend] }
  public enum SendOutcome: String, Codable, Sendable { case sent, notSent = "not_sent", ambiguous }
  public enum SendDetail: String, Codable, Sendable, CaseIterable {
      case confirmed, expired, approvalTooLong = "approval_too_long", textRules = "text_rules",
           hashMismatch = "hash_mismatch", dailyCap = "daily_cap", paused, sendsOff = "sends_off",
           threadMissing = "thread_missing", threadChanged = "thread_changed", notIMessage = "not_imessage",
           badTarget = "bad_target", automationDenied = "automation_denied", scriptRefused = "script_refused",
           messagesError = "messages_error", noReadback = "no_readback", multipleMatches = "multiple_matches",
           notConfirmed = "not_confirmed", scriptUncertain = "script_uncertain", databaseUnreadable = "database_unreadable",
           recoveredAfterRestart = "recovered_after_restart"
  }
  public struct SendResult: Codable, Sendable, Equatable {
      public let sendID: String; public let outcome: SendOutcome; public let anchorGUID: String?
      public let textSHA256: String; public let detail: SendDetail
  }
  public enum CompanionTextHash { public static func of(_ text: String) -> String }  // lowercase hex SHA-256 of UTF-8
  ```
  Coding keys snake_case as commented; encode and decode with `CompanionJSON.encoder` / `.decoder`.

- [ ] **Step 1: Write the contract section.** Replace the reserved section with:
  - `GET /imsg/sends?wait=25`: long-poll up to 25 s. `200` with `{"sends": [ApprovedSend…]}` (0 to 5 items, oldest first; only unexpired, not-yet-resulted sends for the token's device). `401` stop; `429`/5xx retry with the uplink backoff (5 s doubling to 300 s); anything else stop.
  - `POST /imsg/send-results` body `SendResult`. `200` accepted (same body again also `200`). `409` a different result is already stored for this `send_id`: the Mac stops the executor and shows it. `404` unknown `send_id`: the Mac marks the record reported and shows it. `401` stop; `429`/5xx retry.
  - Field list and the `detail` codes with one line each. `detail` is never free text. HomeChat must treat `ambiguous` as final (no re-queue) and must not re-issue a `send_id`.
  - HomeChat recomputes `text_sha256` from its stored approved text when it issues the send.
- [ ] **Step 2: Write failing tests** `test_approvedSendDecodesContractExample` (decode the contract's JSON example, ISO-8601 `Z` dates), `test_sendResultEncodesSnakeCaseAndOmitsNilAnchor`, `test_textHashKnownVector` (`CompanionTextHash.of("hello") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"`), `test_textHashIsOverExactUTF8` (`of("hi") != of("hi ")`).
- [ ] **Step 3: Run `CompanionSendModelsTests`.** Expected: build fails, types missing.
- [ ] **Step 4: Implement `CompanionSendModels.swift`;** regenerate the project; add the suite to `COMPANION_SUITES`.
- [ ] **Step 5: Run `CompanionSendModelsTests`.** Expected: all pass.
- [ ] **Step 6: Commit** `Companion sends: contract and wire models`.

### Task 2: Send rules

**Files:**
- Create: `msgblast/Core/Companion/CompanionSendRules.swift`
- Test: `msgblastTests/CompanionSendRulesTests.swift` (+ suite name)

**Interfaces:**
- Consumes: `ApprovedSend`, `SendDetail`, `CompanionTextHash` (Task 1).
- Produces: `public enum CompanionSendRules { public static let maxCharacters = 4000; public static let maxApproval: TimeInterval = 600; public static let dailyCap = 30; public static func refusal(for send: ApprovedSend, now: Date, attemptsLast24h: Int) -> SendDetail? }`. It returns nil when the send may go ahead. Checks run in this order: `expired`, `approvalTooLong`, `hashMismatch`, `textRules`, `dailyCap`.

- [ ] **Step 1: Write failing tests**, one per rule with its boundary:
  - expired at `now == expiresAt`, allowed at `expiresAt - 1 s`;
  - `approvalTooLong` at 601 s, allowed at 600 s;
  - hash mismatch;
  - empty, `" \n\t"`;
  - 4000 characters (allowed) and 4001 (refused), counting emoji as one `Character` each;
  - a `\u{0007}` or `\u{001B}` character refused, while tab, LF and CR are allowed;
  - `dailyCap` at `attemptsLast24h == 30`, allowed at 29;
  - `test_textIsNotTrimmed`: `"hi "` with the hash of `"hi "` passes.
- [ ] **Step 2: Run `CompanionSendRulesTests`.** Expected: fail to build.
- [ ] **Step 3: Implement `refusal(for:now:attemptsLast24h:)`.**
- [ ] **Step 4: Run `CompanionSendRulesTests`.** Expected: pass.
- [ ] **Step 5: Commit** `Companion sends: rules (expiry, hash, text, cap)`.

### Task 3: Fixed AppleScript with argv, and the osascript runner

**Files:**
- Create: `msgblast/Core/Companion/CompanionSendScript.swift`
- Test: `msgblastTests/CompanionSendScriptTests.swift` (+ suite name)

**Interfaces:**
- Produces:
  ```swift
  public enum CompanionSendScript {
      public static let source: String     // fixed; `on run argv`; `with timeout of 20 seconds`
      public static func arguments(threadGUID: String, handles: [String], text: String) throws(CompanionSendScriptError) -> [String]
      public static func parse(_ output: String) -> ScriptResult
  }
  public enum CompanionSendScriptError: Error, Equatable { case badTarget }
  public enum ScriptResult: Equatable, Sendable {
      case submitted, notSubmitted(code: Int), uncertain(code: Int), timedOut, failedToStart, exitNonZero, unexpected
  }
  public protocol CompanionScriptRunning: Sendable {
      func run(source: String, arguments: [String], timeout: TimeInterval) async -> ScriptRunOutput
  }
  public enum ScriptRunOutput: Equatable, Sendable { case output(String), timedOut, failedToStart, exitNonZero }
  public struct OsascriptRunner: CompanionScriptRunning { public init() }  // timeout used: 35 s by the executor
  ```
- Argument layout: `[threadGUID, String(handles.count), handles…, text]`. The script reads `item 1`, the count, then the handles, and takes `item -1` as the text.
- Script checks, in the same order as `send_probe.py`: chat `id` exists and equals the GUID (9001); service is iMessage (9003); participant count equals the count passed (9002); every handle passed is a participant (9004). A `submissionAttempted` flag is set just before `send`. The script returns `SUBMITTED`, `NOT_SUBMITTED:<code>` or `UNCERTAIN:<code>`. Error -1743 becomes `notSubmitted(code: -1743)`. Activating or focusing Messages is not allowed.
- `OsascriptRunner`: `Process` runs `/usr/bin/osascript` with `["-"] + arguments`, and the source goes in on stdin. On timeout it terminates, waits 2 s, then sends SIGKILL and returns `.timedOut`. Upstream's `MessageSender.execute` has the same shape; it is not reused, because it is in the app target.

- [ ] **Step 1: Write failing tests.**
  - `test_sourceHasNoPlaceholders`: `source` contains `on run argv` and no `%@` or `\(`.
  - `test_sourceCompiles`: compile-only, the same way `MessagesSendScriptTests` does it.
  - `test_argumentsLayout`: a 1:1 and a 3-handle group.
  - `test_badTargetRefused`: a GUID or handle that starts with `-`, or contains `\n` or `\u{0}`, throws `.badTarget`. The same characters in `text` are allowed.
  - `test_parse`: every prefix, including `NOT_SUBMITTED:-1743`.
  - `test_runnerPassesArgvVerbatim`: run `OsascriptRunner` on a test-only echo script (`on run argv` returns the items joined by a sentinel, with no Messages reference). Pass texts `"-x"`, `"\" & (do shell script \"echo pwned\") & \""`, `"line1\nline2"`, `"émoji 👍🏽"` and `"back\\slash"`. Each one must come back byte for byte, and nothing may be evaluated.
  - `test_runnerTimesOut`: a `delay 10` script with timeout 1 s returns `.timedOut` within 4 s.
- [ ] **Step 2: Run `CompanionSendScriptTests`.** Expected: the build fails.
- [ ] **Step 3: Implement the script, `arguments`, `parse` and `OsascriptRunner`.**
- [ ] **Step 4: Run `CompanionSendScriptTests`.** Expected: pass. No test touches Messages.
- [ ] **Step 5: Commit** `Companion sends: fixed argv AppleScript and runner`.

### Task 4: Read-back and thread identity from chat.db

**Files:**
- Modify: `msgblast/Core/Companion/CompanionReader.swift` (new methods, in the same file so they can use its private `each`)
- Modify: `msgblastTests/CompanionFixture.swift`. Add the columns `message.error`, `message.is_sent` and `message.is_delivered` (INTEGER, default 0), and `chat.service_name` if it's missing. Add the parameters `error: Int = 0, isSent: Bool = false` to `addMessage` and `service: String = "iMessage"` to `addChat`.
- Test: `msgblastTests/CompanionSendReadTests.swift` (+ suite name)

**Interfaces:**
- Produces:
  ```swift
  public struct CompanionSendIdentity: Equatable, Sendable { public let service: String; public let kind: CompanionThread.Kind
      public let handles: [String]; public let participantsFingerprint: String }
  public struct CompanionOutgoingRow: Equatable, Sendable { public let rowID: Int64; public let guid: String
      public let body: String?; public let error: Int; public let isSent: Bool }
  extension CompanionReader {
      public func sendIdentity(chatGUID: String) throws(CompanionReaderError) -> CompanionSendIdentity?
      public func maxRowID(chatGUID: String) throws(CompanionReaderError) -> Int64      // 0 when the chat has no rows
      public func outgoingRows(chatGUID: String, after rowID: Int64) throws(CompanionReaderError) -> [CompanionOutgoingRow]
  }
  ```
- `handles` are `handle.id` values as stored, in `chat_handle_join` order. They are what the script is passed. The fingerprint is `CompanionFingerprint.of(handles:)`, the same value phase 1 uploads.
- `body` is `text`, or the `AttributedBodyDecoder` text when `text` is NULL or empty. It is not scrubbed and not cleaned beyond what decoding returns, and it stays in memory.
- `outgoingRows` returns rows with `is_from_me = 1` and `ROWID > rowID` (strictly greater), joined through `chat_message_join` to that chat. Rows from other chats and incoming rows are excluded.
- The send columns (`error`, `is_sent`, `service_name`) are checked only by these methods. A schema without them gives `CompanionReaderError.unsupportedSchema` from these calls only. The phase 1 `rows(after:)` must keep working.

- [ ] **Step 1: Write failing tests.**
  - `test_identityDirectAndGroup`: the handles, the kind and a fingerprint equal to `threads(guids:)`.
  - `test_identityMissingChatIsNil`.
  - `test_identityReportsSMSService`.
  - `test_maxRowIDPerChat`: a newer row in another chat doesn't count.
  - `test_outgoingRowsStrictlyAfterBaseline`.
  - `test_outgoingRowsDecodeAttributedBodyOnly`: `text` is NULL and the body is decoded.
  - `test_outgoingRowsReadErrorAndIsSent`.
  - `test_outgoingRowsSkipIncomingAndOtherChats`.
  - `test_missingSendColumnsDoesNotBreakPhase1Rows`: a fixture without `is_sent`. `rows(after:)` succeeds and `outgoingRows` throws `.unsupportedSchema`.
- [ ] **Step 2: Run `CompanionSendReadTests`.** Expected: fail.
- [ ] **Step 3: Implement the three methods.**
- [ ] **Step 4: Run `CompanionSendReadTests` and `CompanionReaderTests`.** Expected: both pass. The fixture change must not break the phase 1 tests.
- [ ] **Step 5: Commit** `Companion sends: identity and read-back queries`.

### Task 5: Outcome decision

**Files:**
- Create: `msgblast/Core/Companion/CompanionSendDecision.swift`
- Test: `msgblastTests/CompanionSendDecisionTests.swift` (+ suite name)

**Interfaces:**
- Consumes: `ScriptResult` (Task 3), `CompanionOutgoingRow` (Task 4), `SendOutcome`, `SendDetail` (Task 1).
- Produces:
  ```swift
  public enum CompanionSendDecision: Equatable, Sendable {
      case final(SendOutcome, SendDetail, anchorGUID: String?), keepWaiting
      public static func decide(script: ScriptResult, rows: [CompanionOutgoingRow], text: String, deadlinePassed: Bool) -> CompanionSendDecision
  }
  ```
- Rules, in order. "Matches" are rows whose `body == text`, compared exactly.
  1. `script` is `.notSubmitted(-1743)`: `not_sent`, `automationDenied`. Any other `.notSubmitted` or `.failedToStart`: `not_sent`, `scriptRefused`. The rows aren't consulted.
  2. More than one match: `ambiguous`, `multipleMatches` (whether or not the deadline has passed).
  3. Exactly one match with `error != 0`: `not_sent`, `messagesError`, anchor = that row's GUID.
  4. Exactly one match with `isSent`: `sent`, `confirmed`, anchor = that row's GUID. This applies whatever `script` said, so a timed-out script whose row confirms counts as sent.
  5. Before the deadline, anything else: `keepWaiting`.
  6. At the deadline with one match and `!isSent`: `ambiguous`, `notConfirmed`. With no match: `ambiguous`, `noReadback` when `script == .submitted`, otherwise `scriptUncertain`.

- [ ] **Step 1: Write failing tests**, one per rule. Also:
  - `test_nearMatchIsAmbiguousNotNotSent`: the row body is `"hi "` and the text is `"hi"`, at the deadline. The result is `ambiguous`.
  - `test_twoMatchesAreAmbiguous`.
  - `test_timedOutScriptWithConfirmedRowIsSent`.
  - `test_nonMatchingRowsIgnored`: Alex's other outgoing text in the window.
  - `test_neverNotSentAfterSubmittedWithoutEvidence`: a property-style loop over every `ScriptResult` that isn't `notSubmitted` or `failedToStart`, crossed with row sets that have no match and no error. The outcome is never `not_sent`.
- [ ] **Step 2: Run `CompanionSendDecisionTests`.** Expected: fail.
- [ ] **Step 3: Implement `decide`.**
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `Companion sends: outcome decision`.

### Task 6: Send ledger (no message text)

**Files:**
- Create: `msgblast/Core/Companion/CompanionSendLedger.swift`
- Test: `msgblastTests/CompanionSendLedgerTests.swift` (+ suite name)

**Interfaces:**
- Produces:
  ```swift
  public struct SendRecord: Codable, Sendable, Equatable {
      public enum State: String, Codable, Sendable { case inProgress = "in_progress", finished }
      public let sendID: String; public let threadGUID: String; public let textLength: Int; public let textSHA256: String
      public let baselineRowID: Int64?; public let createdAt: Date
      public var state: State; public var dispatchedAt: Date?; public var outcome: SendOutcome?; public var detail: SendDetail?
      public var anchorGUID: String?; public var finishedAt: Date?; public var reportedAt: Date?
  }
  public final class CompanionSendLedger: @unchecked Sendable {
      public init(folder: URL)                                   // <support>/companion-sends/, 0700
      public func record(_ sendID: String) -> SendRecord?
      public func begin(_ record: SendRecord) throws             // exclusive create, 0600; throws if one exists
      public func update(_ record: SendRecord) throws            // atomic replace, 0600
      public func inProgress() -> [SendRecord]
      public func unreported() -> [SendRecord]                   // finished, reportedAt == nil
      public func attempts(since: Date) -> Int                   // records with dispatchedAt >= since
      public func prune(finishedBefore: Date)                    // deletes reported records only
  }
  ```
- There is one JSON file per send, named by the hex SHA-256 of `sendID`, so a server-chosen id never becomes a path. `begin` uses `open(O_CREAT|O_EXCL)`. A refused send is also recorded: `begin` followed by `update(state: .finished)`, with no `dispatchedAt`. The executor prunes records 90 days after they finish.

- [ ] **Step 1: Write failing tests.**
  - `test_beginIsExclusive`.
  - `test_roundTripAndModes`: folder 0700, files 0600.
  - `test_fileHoldsNoText`: build the record from a send whose text is `"SECRET-PHRASE"`. No file byte sequence contains it.
  - `test_fileNameIsHashedSendID`: a send id of `"../x"` stays inside the folder.
  - `test_inProgressAndUnreported`.
  - `test_attemptsCountsDispatchedOnly`.
  - `test_pruneKeepsUnreported`.
  - `test_corruptFileIsTreatedAsInProgressForItsName`: a garbled file blocks re-dispatch of that id rather than vanishing. `record` returns nil, but `begin` still throws.
- [ ] **Step 2: Run `CompanionSendLedgerTests`.** Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `Companion sends: ledger`.

### Task 7: Sends client

**Files:**
- Modify: `msgblast/Core/Companion/UplinkClient.swift`
- Test: `msgblastTests/UplinkClientTests.swift`. It's already a companion suite. Reuse `UplinkStub`.

**Interfaces:**
- Produces:
  ```swift
  public enum SendsError: Error, Equatable { case notHTTPS, unauthorized, conflict, unknownSend, rejected(Int), retryable(Int?), badResponse }
  public protocol CompanionSendUplinking: Sendable {
      func fetchSends(wait: Int) async throws(SendsError) -> [ApprovedSend]
      func postResult(_ result: SendResult) async throws(SendsError)
  }
  extension UplinkClient: CompanionSendUplinking {}
  ```
- `GET <base>/imsg/sends?wait=<wait>`, with a request timeout of `wait + 15` s. `POST <base>/imsg/send-results`. Both use the same bearer, the HTTPS-only check, the no-redirect session and the JSON coders as `post(_:)`. Status mapping follows the Task 1 contract: 409 gives `.conflict` and 404 on results gives `.unknownSend`. A page with more than 5 sends gives `.badResponse`.

- [ ] **Step 1: Write failing tests.**
  - `test_fetchSendsRequestShape`: path, query, method and the `Authorization` header.
  - `test_fetchSendsEmptyAndPage`.
  - `test_fetchSendsMoreThanFiveIsBadResponse`.
  - `test_postResultBody`.
  - `test_statusMapping`: 401, 404, 409, 429, 500, 302 refused, transport error.
  - `test_httpBaseRefused`.
- [ ] **Step 2: Run `UplinkClientTests`.** Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: pass, and the existing uplink tests stay green.
- [ ] **Step 5: Commit** `Companion sends: sends client`.

### Task 8: Send executor

**Files:**
- Create: `msgblast/Core/Companion/CompanionSendExecutor.swift`
- Test: `msgblastTests/CompanionSendExecutorTests.swift` (+ suite name)

**Interfaces:**
- Consumes: all of Tasks 1–7, `CompanionConfig`, `CompanionTokenStoring`.
- Produces:
  ```swift
  public struct CompanionSendStatus: Sendable, Equatable {
      public enum State: Sendable, Equatable { case off, paused, notConfigured, waiting, sending, offline(retryIn: TimeInterval), stopped(String) }
      public struct LastSend: Sendable, Equatable { public let outcome: SendOutcome; public let at: Date }
      public var state: State; public var last: LastSend?
      public var ambiguousCount: Int   // finished records with outcome ambiguous in the last 7 days
  }
  public actor CompanionSendExecutor {
      public init(databasePath: String, configURL: URL, ledgerFolder: URL, tokens: any CompanionTokenStoring,
                  makeUplink: @escaping @Sendable (URL, String) -> any CompanionSendUplinking,
                  runner: any CompanionScriptRunning, now: @escaping @Sendable () -> Date = Date.init,
                  sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) })
      public func cycle() async -> CompanionSendStatus   // one recover/report/fetch/send pass; the caller loops
  }
  ```
- `cycle()`, in order:
  1. Reload the config. If `sendsEnabled == false`, return `.off`. If paused, return `.paused`. With no URL or token, return `.notConfigured`. These do nothing else.
  2. **Recover:** for each `inProgress` record, open the reader and call `outgoingRows(chatGUID:after: baselineRowID ?? Int64.max)`. Then call `decide` with `.uncertain(code: 0)` and `deadlinePassed: true`. Map `sent`/`confirmed` to detail `recoveredAfterRestart`; every other outcome is `ambiguous`, `recoveredAfterRestart`. A recovery never yields `not_sent`. Finish the record.
  3. **Report** each `unreported` record with `postResult`:
     - `200` sets `reportedAt`.
     - `.unknownSend` sets `reportedAt` and adds a log line.
     - `.conflict` and `.unauthorized` stop the executor (`stopped`) until the URL or token changes, the same key rule as `CompanionService`.
     - `.retryable` and `.badResponse` back off 5 s, doubling to 300 s.
  4. **Fetch** with `fetchSends(wait: 25)`.
  5. **For each send, one at a time:**
     - If a ledger record exists, re-post its result if one is finished; dispatch nothing.
     - Run `CompanionSendRules.refusal`.
     - Re-check that sends are on and not paused (`sendsOff` / `paused`).
     - Run `sendIdentity` and require all of: present (`threadMissing`), service `iMessage` (`notIMessage`), a fingerprint equal to the send's (`threadChanged`), and `CompanionSendScript.arguments` that don't throw (`badTarget`).
     - Any refusal: `begin` plus `finish` as `not_sent`, then report.
     - Otherwise:
       - Take `baseline = maxRowID(chatGUID:)`.
       - Re-check expiry against `now()`.
       - `begin` the record with the baseline. Set `dispatchedAt` and `update` before running the script.
       - Run the script with a 35 s timeout.
       - Poll: call `outgoingRows` and `decide` once straight away, then once a second until 20 s after the script returned (`deadlinePassed` on the last poll).
       - A reader error during polling gives `ambiguous`, `databaseUnreadable`.
       - `finish`, then report.
  6. Prune records that finished more than 90 days ago.
- The executor never calls `runner.run` twice for one `send_id`, in this cycle or any later one. This is the central invariant.

- [ ] **Step 1: Write failing tests** with a fixture `chat.db`, a temp ledger, a fake uplink that records results and a fake runner. The runner's closure can insert the outgoing row into the fixture, which simulates Messages, and returns a scripted output. The clock and `sleep` are injected, so the tests don't wait in real time.
  - `test_happyPath1to1`: `sent` and `confirmed`, the anchor is the inserted row's GUID, and exactly one runner call is made with the argument layout from Task 3.
  - `test_happyPathGroup`.
  - `test_offAndPausedDoNotFetch`.
  - `test_redeliveredSendIsNotDispatchedAgain`: the same `send_id` arrives in two cycles. The runner is called once and the second cycle re-posts the same `SendResult`.
  - `test_expiryRecheckedBeforeDispatch`: the clock moves past `expiresAt` during the identity read. The result is `not_sent`, `expired`, with 0 runner calls.
  - `test_changedParticipantsRefusedBeforeDispatch`, `test_smsThreadRefused`, `test_missingThreadRefused`.
  - `test_hashMismatchRefused`, `test_dailyCapCountsAttempts`: 30 earlier dispatched records, including ambiguous ones, mean the 31st is refused.
  - `test_ambiguousNeverRetried`: the runner times out and no row ever appears. The result is `ambiguous`; later cycles make no runner call and re-post that result only if it wasn't reported.
  - `test_notConfirmedWithinTwentySeconds`: a row appears with `is_sent = 0`, giving `ambiguous`, `notConfirmed`, after the 21st poll at most.
  - `test_recoveryResolvesToSentOnOneExactMatch`, `test_recoveryAmbiguousOnZeroOrTwoMatches`: an `inProgress` record left in the ledger plus fixture rows. No runner call is made.
  - `test_resultConflictStops`, `test_resultRetryBacksOff`, `test_unknownSendMarkedReported`.
  - `test_pausedBetweenFetchAndDispatch`: gives `not_sent`, `paused`.
- [ ] **Step 2: Run `CompanionSendExecutorTests`.** Expected: fail.
- [ ] **Step 3: Implement `CompanionSendExecutor`.**
- [ ] **Step 4: Run `CompanionSendExecutorTests` plus every companion suite.** Expected: all pass.
- [ ] **Step 5: Commit** `Companion sends: executor`.

### Task 9: Config switch, controller loop and status section

**Files:**
- Modify: `msgblast/Core/Companion/CompanionConfig.swift`. Add `public var sendsEnabled: Bool`, key `sends_enabled`, default `false`. Decode it with `decodeIfPresent`, so older files still load, and keep the device-ID validation.
- Modify: `msgblast/Companion/CompanionController.swift`. Build the executor with `ledgerFolder` = the support folder's `companion-sends`, `OsascriptRunner()` and the same token store. `start()` launches one `Task` loop: `while !Task.isCancelled { sendStatus = await executor.cycle(); if sendStatus is off/paused/notConfigured/stopped { sleep 5 s } }`. Add `@Published sendStatus`, and `setSendsEnabled(_:)`, which writes the config.
- Modify: `msgblast/Companion/CompanionStatusView.swift`:
  - Add a toggle, "Send approved replies", off by default.
  - Under Details, show "Replies: Off / Waiting / Sending / Stopped: … / Mac offline, retrying in N s" and "Last reply: sent / not sent / may or may not have sent, N min ago".
  - When `ambiguousCount > 0`, show a red line: "N replies may or may not have sent: check Messages". No message text or recipient is shown.
- Test: `msgblastTests/CompanionConfigTests.swift`:
  - `test_sendsEnabledDefaultsOffAndOldFilesLoad`: a phase 1 JSON with no key loads as `false`, keeping its cursor and device ID.
  - `test_sendsEnabledRoundTrip`.
- [ ] **Step 1: Write the config tests.** Run `CompanionConfigTests`: they fail.
- [ ] **Step 2: Implement the config field.** Run: pass.
- [ ] **Step 3: Wire the controller and view.** Build the app scheme (the focused run builds it). Expected: compiles, and every companion suite passes.
- [ ] **Step 4: Commit** `Companion sends: Settings switch and status`.

### Task 10: Review, docs, acceptance runbook

**Files:**
- Create: `docs/superpowers/runbooks/phase3-mac-acceptance.md`
- Modify: `FORK.md`. Update the companion paragraph; no upstream files are changed. Also update `.claude/STATUS.md` and `.claude/LOG.md`.

- [ ] **Step 1: Run the `send-safety-reviewer` agent** on the branch diff against the Global Constraints. Fix Critical and Important findings test-first, then record any that are declined, with reasons, in the PR.
- [ ] **Step 2: Run the Mac gate** exactly as `.claude/agents/quality-gate.md` gives it. Expected: Python and native suites, 0 failures.
- [ ] **Step 3: Write the runbook.** Each check states its evidence and stays counts-only on HomeChat. Real sends happen only after Alex's typed yes in chat, to a test contact and a test group. The build is installed only after quitting the old copy, with a rollback copy kept and the designated requirement matched.
  - **A** (sends off): an approved send waits, then expires on HomeChat as "not sent, Mac offline", and nothing is dispatched.
  - **B** (1:1): `yes` sends; the test contact receives it once; HomeChat stores `sent` with an anchor; the uplink stores the outgoing row; the flag clears.
  - **C** (group): the same, in the test group.
  - **D** (offline): Mac offline past expiry gives "not sent".
  - **E** (restart): quit the app during the 20 s read-back. On relaunch the record resolves to `sent` (`recovered_after_restart`), and the contact still has exactly one copy.
  - **F** (changed group): a member changes after approval, giving `not_sent` (`thread_changed`) and nothing sent.
  - **G** (focus): Messages and Terminal frontmost state before and after B, as in spike (d).
  - **Not covered at runtime:** SMS refusal, unless a test SMS thread exists, and Automation denied.
- [ ] **Step 4: Open the PR** in the fork with `--repo Goldalex98/msgblast-imessage`. Merge on green fork CI under the standing rule. That merge isn't an approval for any real send.
- [ ] **Step 5: Commit** the docs with the PR.

## Cross-repo dependency

Acceptance B–F needs HomeChat's half in `homechat-bot`:
- the `/imsg/sends` and `/imsg/send-results` routes per Task 1;
- the queue, with `send_id`, `text_sha256` and a 10-minute `expires_at`;
- the `N yes` / `N edit:` flow with its exact-text echo;
- the `CLAUDE.md` reply exception (design §6);
- outcome messages to Alex's 1:1.

Tasks 1–9 here don't wait for it: they are proven on fakes. Phase 3 is accepted only when B–F pass end to end.

# Standalone iMessage companion agent: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A small signed launchd agent, `ImsgCompanion.app`, in the new public repo `Goldalex98/imsg-companion`. It reads `chat.db` through `IMsgCore` 0.21.0, uplinks and sends exactly as the fork companion did on every route, reports status to HomeChat, and updates itself nightly from green `main`.

**Architecture:** A SwiftPM package with one library target, `CompanionCore` (the lifted safety core plus the new reading, status, control and updater code, all testable without a Mac session), and one executable target, `imsg-companion` (commands and the run loop). `IMsgCore` supplies message paging and the edit/unsend watcher. Our own read-only SQLite queries supply what it doesn't: system rows, the from-me thread set, send identity, twin chats and read-back facts. A shell script assembles, signs and verifies the `.app`, and launchd starts the agent and the updater.

**Tech Stack:** Swift 6.4 (Xcode 27.2 on the MacBook; GitHub `xcode-27` runner), SwiftPM, `IMsgCore` (`openclaw/imsg` tag `v0.21.0`, commit `1bc0679`), SQLite3 (read-only), Contacts, `/usr/bin/osascript`, XCTest on synthetic `chat.db` fixtures, launchd, GitHub Actions and Dependabot.

**Spec:** `docs/superpowers/specs/2026-11-14-imsg-standalone-agent-design.md` (approved 2026-11-15). Also: the uplink contract `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`, and the companion design `2026-11-07-imessage-companion-design.md` §4–§6 where the agent design doesn't override it. Both docs move to the new repo in Task 2.

**Out of scope:** HomeChat's half (design §7, `homechat-bot`'s own session and PRs); running cutover and acceptance (Task 13's runbooks are written here and run later with Alex); archiving the fork; edits (deferred); new conversations, attachments and tapbacks as replies.

## Global Constraints

- Never write `chat.db`, mark messages read, send typing indicators or touch Messages' UI. Every SQLite open is read-only (`SQLITE_OPEN_READONLY`); `IMsgCore`'s `MessageStore` is read-only by construction.
- Link only the `IMsgCore` product. Never call `MessageSender`, `MessagesLauncher`, `IMCoreBridge`, `IMsgBridgeClient`, `TypingIndicator`, `IMsgEventTailer`, `AudioMessagePreparer` or `ContactResolver.create`. Task 3 adds a test that greps `Sources/` for these names and fails on any hit.
- Messages go out only through the executor: an approved send whose text hashes to `text_sha256`, unexpired, non-blank with no control characters, thread present, fingerprint match, script checks 9001/9002/9004, an exclusive ledger record before dispatch, read-back after. An `ambiguous` send is never retried; a `send_id` with any ledger record never runs again.
- `sends_enabled` defaults to false and is set only by the local `sends on` command. Nothing received from HomeChat can set it.
- No service gate anywhere: no `chat.service_name` check, no 9003 account check, no `iMessage;` prefix rule. Service is reported per message (`IMsgCore`'s `Message.service`) and per sent row (`sent_service`), never per thread.
- Public repo: no names, numbers, handles, chat GUIDs, message text, HomeChat host, tokens or private paths in code, tests, fixtures, docs, commits or PR text. Test handles and GUIDs are invented (`+15555550100`, `any;-;+15555550100`, `any;+;chat-test`). Synthetic fixtures only. Logs, ledger, status and health files carry counts and states, never text.
- Dev and debug runs against the real `chat.db` print only counts and shapes. No real send in development. Real sends happen only in Stage S, with Alex's typed yes per send, to test contacts.
- Names: repo `Goldalex98/imsg-companion` (MIT); app `ImsgCompanion.app`; bundle ID `io.github.goldalex98.imsg-companion`; executable `imsg-companion`; support folder `~/Library/Application Support/imsg-companion/`; Keychain generic password service `io.github.goldalex98.imsg-companion.companion-uplink`, account `uplink-token`; launchd labels `io.github.goldalex98.imsg-companion` (agent) and `io.github.goldalex98.imsg-companion.updater`; the fork's bundle ID for the single-uploader check is `io.github.goldalex98.msgblast-imessage` (read from the installed fork app's `Info.plist`).
- `device_id` matches `^mac-[0-9a-f]{8}$`.
- Git: in the new repo, a feature branch per task group and a PR (`--repo Goldalex98/imsg-companion`), merged by Claude with a merge commit on a green CI run; no auto-merge except the Dependabot job in Task 12. Nothing aimed at `mgalpert/msgblast` or `openclaw/imsg`.
- The gate in the new repo: `swift build` then `swift test` from the repo root on the MacBook, plus `scripts/build-app.sh --verify-only` once Task 10 exists. Say which host ran what.

## Decided here (from reading the code)

- **`IMsgCore` facts used** (v0.21.0): `MessageStore(path:)` opens read-only with `busyTimeout = 5`. `messagesAfterPage(afterRowID:chatID:limit:includeReactions:) -> MessagesAfterPage` returns `messages`, `nextRowID` (the last *physical* row scanned, including dropped URL-preview rows) and `hasMore`. With `chatID: nil` a row with no `chat_message_join` has `chatID == 0`; a row in two chats gets the lower chat id. `Message` is `Sendable, Equatable` (not `Codable`); `service` is a `String`; `text` is non-optional and is `""` for unsent, empty, undecodable and non-typedstream-garbled rows. `MessageWatcher(store:).stream(chatID:sinceRowID:configuration:filter:)` yields `Message`; edits and unsends arrive as a `Message` with `mutationEvent` `.edited` / `.unsent`. The stream throws `MessageWatcherOverflowError(resumeAfterRowID:)` when the consumer falls behind. Edits and unsends are not replayed after a restart. `Chat` has no guid or group flag; the agent uses its own queries for threads.
- **Unreadable:** `IMsgCore` has no signal for it, so our per-page `RowFacts` query reports `hasBody` (`text IS NOT NULL OR attributedBody IS NOT NULL`) and `itemType`. The kind is `unreadable` when `hasBody`, the decoded `text` is empty, there are 0 attachments, and the row is neither a reaction nor unsent.
- **`AttributedBodyDecoder` is dropped.** Read-back gets decoded text from `IMsgCore` (`messagesAfterPage` from the global baseline, paged to the end), and `error`/`is_sent` from `RowFacts`.
- **Handle normalization** (feeds `participants_fingerprint`; HomeChat stores the Mac's value and compares later ones to it (`sends.py:123`), so a change would break every flag and send opened under the fork): trim whitespace and newlines, lowercase; keep as-is if it contains `@`; keep as-is if any character is not a digit or one of `+()- .`; otherwise keep only digits and `+`. It is rewritten from this rule (not copied) and pinned by Task 3's vectors.
- **No expiry ceiling:** the fork's approval-length rule (`expiresAt − approvedAt > 600`, `CompanionSendRules.swift:15`) is dropped, as design §5.4 says, and nothing replaces it. A `now`-based ceiling was considered and rejected (Fable plan review): HomeChat sets `expires_at = now + 600`, so any Mac clock behind the server would refuse every send, and a compromised HomeChat forges both timestamps anyway. So §5.1's "expiry ceiling" tunable has no rule left to tune. The tunables are the daily cap and the backoff. Expiry itself (`expiresAt <= now` → `expired`) stays.
- **Unsent re-post shape:** `{guid, rowid, thread_guid, from_me, sender_handle, sent_at, kind: "text", text: null, reply_to_guid: null, attachment_count: 0, service, unsent: true}` in an ordinary `POST /imsg/messages` batch whose `cursor` is the current saved cursor (it never advances the cursor). Task 2 writes this into the contract.
- **Paused:** `effectivePaused = config.paused || remotePaused`. `remotePaused` lives in memory only and is set by every `GET /imsg/sends` response (absent `control` = false). It is never written to config, so a remote resume can't undo a local pause. Known gap, accepted: after a restart the agent may uplink for up to one poll (≤ 25 s) before a remote pause comes back, and with no token set up a remote pause can't arrive at all. `stage-u.md` U7 says so, so it isn't read as a bug.

## Review Focus

1. **`chat.db` replaced or restored** (ROWIDs restart below the saved cursor): the agent must not silently re-read from 0 or skip forever, and deleting the newest texts in Messages must not look like a replacement. Expected: `highWaterRowID()` (from `sqlite_sequence`, as the fork's reader hardening does) `< cursor` → no uplink, status `last_error: "database_replaced"`, cursor unchanged until Alex acts; deleting the newest rows (lower `MAX(ROWID)`, same sequence) → reading carries on. Tests in Tasks 4 and 5.
2. **The watcher stream throws or overflows** (`MessageWatcherOverflowError`, or `chat.db` briefly unreadable): unsends must keep flowing after it. Expected: restart the stream from `maxRowID()` after the backoff, count the restart in status, never crash-loop under launchd. Test in Task 6.
3. **The Mac wakes with an approved send whose expiry passed during sleep:** it must be refused (`expired`), never sent, and never retried. Test in Task 7.
4. **Contacts denied or never asked:** reading and uplink go on with null names, and status says `contacts: denied` / `unknown` so HomeChat doesn't count senders as unsaved. Test in Task 8.
5. **Control mixed with sends off or a local pause:** a `GET /imsg/sends` with sends off must not run a send, a remote `paused: false` must not lift a local pause, and a remote pause must stop uplink too. Test in Task 8.

---

### Task 1: Prove `IMsgCore` 0.21.0 as a pinned SwiftPM dependency (STOP GATE)

Done on the MacBook, in a scratch folder outside both repos (`~/dev/imsg-dep-probe/`), before the new repo exists.

**Files:**
- Create: `~/dev/imsg-dep-probe/Package.swift`, `Sources/Probe/main.swift`, `Tests/ProbeTests/ProbeTests.swift`, `Tests/ProbeTests/Fixture.swift` (a copy of the fork's `msgblastTests/CompanionFixture.swift`, synthetic only)

- [ ] **Step 1: Write the manifest.** `swift-tools-version: 6.1`, `platforms: [.macOS(.v14)]`, dependency `.package(url: "https://github.com/openclaw/imsg.git", exact: "0.21.0")`, an executable target `Probe` depending on `.product(name: "IMsgCore", package: "imsg")`, and a test target `ProbeTests` depending on `Probe`'s library half (put the probe code in a `ProbeKit` library target if `@testable import` of an executable fails).
- [ ] **Step 2: Resolve.** Run `swift package resolve`. Expected: success, with `Package.resolved` pinning `imsg` at `0.21.0` / `1bc0679663bf3978a744a61a5a9161d9ba518764`. **If SwiftPM refuses because of `unsafeFlags` (any error naming unsafe flags or the `imsg` target), stop the plan here and report the exact error to Alex.** Don't work around it (no branch or revision pin, no fork, no vendoring) without his decision.
- [ ] **Step 3: Build debug and release.** `swift build` and `swift build -c release`. Expected: both succeed, and `.build/release/` holds no `imsg` executable (only the library product is built). Same stop rule.
- [ ] **Step 4: Prove it reads our synthetic fixture.** A test opens `MessageStore(path:)` on the fixture, adds 3 messages to one `any;-;+15555550100` chat plus 1 orphan row (no join), and asserts `messagesAfterPage(afterRowID: 0, chatID: nil, limit: 10, includeReactions: true)` returns the three with the right `rowID`s and texts, `nextRowID == 4`, and the orphan with `chatID == 0`. The fork fixture lacks `message.service`, which `IMsgCore` selects unconditionally (`MessageStore+MessageRows.swift:142`), so add at least that. If anything else is missing, add it too to the copy and **write down every added column**: Task 4 carries the list. Run: `swift test`. Expected: pass.
- [ ] **Step 5: Prove signing works with hardened runtime.** Wrap `.build/release/Probe` in a minimal `Probe.app` (`Contents/MacOS/Probe`, an `Info.plist` with `CFBundleIdentifier` `io.github.goldalex98.imsg-dep-probe`) and sign it with `codesign --force --options runtime --entitlements probe.entitlements --sign "$(cat ~/.config/msgblast-imessage/signing-identity)" Probe.app`, where `probe.entitlements` is exactly Task 10's (`com.apple.security.automation.apple-events` true), so the proof covers the real signature shape. Then run `codesign --verify --strict --verbose=2 Probe.app` and `codesign -d -r- Probe.app`. Expected: valid; the requirement names the identifier and the Apple Development certificate, with no `cdhash`. Run `Probe.app/Contents/MacOS/Probe --version-only` (`main.swift` prints `ok` for that argument and returns before opening anything). Expected: `ok`, with no dyld or library-validation error.
- [ ] **Step 6: Record.** Append the commands, outcomes, `Package.resolved` pins (names and versions only) and added fixture columns to this repo's `.claude/LOG.md`, update STATUS, then delete `~/dev/imsg-dep-probe/` with Alex's yes. Commit in the fork via a docs PR, or fold the record into the Task 2 PR. Nothing in the probe touches the real `chat.db`.

### Task 2: New repo, scaffold, CI and the contract amendment

**Files (new repo `~/dev/imsg-companion`):**
- Create: `Package.swift`, `Package.resolved`, `Sources/CompanionCore/Placeholder.swift` (removed in Task 3), `Sources/imsg-companion/main.swift`, `Tests/CompanionCoreTests/SmokeTests.swift`, `LICENSE` (MIT), `README.md`, `.gitignore`, `CLAUDE.md`, `.claude/settings.json`, `.claude/STATUS.md`, `.claude/LOG.md`, `.claude/agents/quality-gate.md`, `.claude/agents/send-safety-reviewer.md`, `.github/workflows/ci.yml`
- Move: the design → `docs/specs/2026-11-14-imsg-standalone-agent-design.md`; the contract → `docs/specs/2026-11-08-imsg-uplink-contract.md`; this plan → `docs/plans/2026-11-15-imsg-standalone-agent.md` (copies; the fork keeps its originals with a one-line pointer)

- [ ] **Step 1: Create the repo** with Alex's approved name: `gh repo create Goldalex98/imsg-companion --public --description "Standalone iMessage companion agent for HomeChat" --clone` in `~/dev`. Branch `scaffold` off the initial commit.
- [ ] **Step 2: Manifest.** As in Task 1, plus targets `CompanionCore` (library; depends on `IMsgCore`), `imsg-companion` (executable; depends on `CompanionCore`), `CompanionCoreTests`. Copy Task 1's `Package.resolved`.
- [ ] **Step 3: Project files.** Seed `CLAUDE.md`, the settings, the agents and STATUS/LOG from the fork's (use the user-level `project-starter-pack` layout where it fits). Carry over: the chat.db, send and public-data rules from Global Constraints; the read denies for `~/Library/Messages/**`, the AddressBook store, `.env*`, `*.local.json`, `.local/**`; pre-allows only the gate commands (`swift build`, `swift test`, and `scripts/build-app.sh --verify-only` once it exists); the merge rule (Claude merges its own PRs on green with a merge commit; only Task 12's job auto-merges). The fork's design-gate, upstream and generator rules don't apply (no GUI, no upstream).
- [ ] **Step 4: CI.** `ci.yml` on `pull_request`, `push` to `main` and `workflow_dispatch`: job `test` on `runs-on: xcode-27` with `DEVELOPER_DIR: /Applications/Xcode_27.0.app/Contents/Developer`, steps `xcodebuild -version`, `swift build`, `swift test`. No secrets, `permissions: contents: read`.
- [ ] **Step 5: Contract amendment.** In the moved contract, add a dated "2026-11-15 additions" section with exactly design §5.3 plus "Decided here": `messages[].service` (`"iMessage"`, `"SMS"`, `"RCS"` or other string as `IMsgCore` reports it); `messages[].unsent` (the re-post shape above, in a batch whose `cursor` is the current saved cursor; still one batch at a time; HomeChat upserts by `guid`, marks unsent, clears its flag); `send-results.sent_service` (string, or null when no row was read back); unknown `detail` codes accepted; `not_imessage` retired; `GET /imsg/sends` → `{"sends": [...], "control": {"paused": bool}}` with `control` optional; `POST /imsg/status` (body as Task 8's `AgentStatus`, response 204); deploy order HomeChat first.
- [ ] **Step 6: Verify and ship.** `swift build && swift test` pass on the MacBook; push; open the PR; wait on its run by head sha (`gh run list --repo Goldalex98/imsg-companion --commit <sha>`, then a background `gh run watch <id> --exit-status`). This first CI run is the design §9 proof that `IMsgCore` builds on the Xcode 27 runner. Merge on green. Tell the HomeChat session the amended contract's path.

### Task 3: Lift the pure safety core

**Files:**
- Create in `Sources/CompanionCore/`: `HandleNormalizer.swift` (new), and, lifted from the fork's `msgblast/Core/Companion/` with only the changes named here: `CompanionModels.swift`, `CompanionScrubber.swift`, `CompanionConfig.swift`, `CompanionTokenStore.swift`, `UplinkClient.swift`, `CompanionSendModels.swift`, `CompanionSendRules.swift`, `CompanionSendDecision.swift`, `CompanionSendLedger.swift`, `CompanionSendScript.swift`
- Create in `Tests/CompanionCoreTests/`: the matching lifted test files, `HandleNormalizerTests.swift`, `ForbiddenAPITests.swift`
- Delete: `Placeholder.swift`, `SmokeTests.swift`

**Interfaces:**
- Produces: `enum HandleNormalizer { static func normalize(_ value: String) -> String }`, used by `CompanionFingerprint.of(handles:)` in place of `ChatResolver.normalize`. Everything else keeps the fork's names and signatures.

- [ ] **Step 1: Normalizer vectors.** Write `HandleNormalizerTests.test_vectors` asserting `" +1 (555) 555-0100 "` → `"+15555550100"`, `"Test@Example.COM"` → `"test@example.com"`, `"555.555.0100"` → `"5555550100"`, `"abc-123"` → `"abc-123"`, `"\n+44 20 7946 0000\t"` → `"+442079460000"`, `""` → `""`. Add `test_fingerprintUnchanged`: `CompanionFingerprint.of(handles: ["+1 555 555 0100", "test@example.com"])` equals the hex value the fork produces today. Compute that value once by running the fork's `CompanionModelsTests` helper on the same input on the MacBook, and paste it in as a literal.
- [ ] **Step 2:** Run `swift test --filter HandleNormalizerTests`. Expected: FAIL (no type).
- [ ] **Step 3:** Implement `HandleNormalizer.normalize` from the rule in "Decided here". Copy the ten source files and their tests (XCTest, `@testable import CompanionCore`), replace `ChatResolver.normalize` with `HandleNormalizer.normalize`, and drop `msgblast`-specific imports.
- [ ] **Step 4: Changes inside the lift** (each with its test changed first):
  - `CompanionTokenStore`: service is the constant `io.github.goldalex98.imsg-companion.companion-uplink` (no `Bundle.main` default).
  - `CompanionConfig`: add `tunables: Tunables` (JSON key `tunables`, every field optional in JSON with defaults: `daily_send_cap` 30, `backoff_initial_seconds` 5, `backoff_max_seconds` 300). Add `static let supportFolder = "imsg-companion"`. A config with an unknown tunables key still loads. Test: missing `tunables` → defaults; `daily_send_cap: 5` round-trips.
  - `CompanionSendRules`: remove the approval-length rule (`approval_too_long` is no longer produced by this agent; the code stays decodable). Read the cap from `tunables.dailySendCap`. Tests: `approvedAt = now − 3600, expiresAt = now + 60` allowed; `expiresAt = now` refused `expired`; cap 2 refuses the third.
  - `CompanionSendScript`: delete the 9003 line. Add `static func source(dispatch: Bool) -> String`: `dispatch: false` replaces the `send` line with `return "READY"`. `ScriptResult` gains `.ready`. Tests: the source never contains `service type`; `dispatch: false` never contains `send `; `READY` parses to `.ready`.
  - `CompanionSendModels`: `SendsPage` gains `control: Control?` (`struct Control: Codable { var paused: Bool? }`). `SendResult` gains `sentService: String?` (`sent_service`, always encoded, null allowed). Tests: decode `{"sends":[]}` and `{"sends":[],"control":{"paused":true}}`; encode includes `"sent_service":null`.
  - `CompanionModels`: `CompanionMessage` gains `service: String?` (`service`, always encoded) and `unsent: Bool?` (`unsent`, encoded only when true). Test: the unsent re-post encodes exactly the "Decided here" key set.
- [ ] **Step 5: Forbidden API test.** `ForbiddenAPITests.test_noSendOrBridgeAPIs` reads every `.swift` file under `Sources/` (path from `#filePath`) and fails if any contains `MessageSender`, `MessagesLauncher`, `IMCoreBridge`, `IMsgBridgeClient`, `TypingIndicator`, `IMsgEventTailer`, `AudioMessagePreparer` or `ContactResolver.create`.
- [ ] **Step 6:** Run `swift test`. Expected: every lifted test and the new ones pass, with no lifted test deleted except those for the removed approval-length rule and the 9003 line.
- [ ] **Step 7:** Run `send-safety-reviewer` on the diff against the fork's originals (rules, script, token store, scrubber). Fix Critical and Important findings test-first.
- [ ] **Step 8:** Commit ("Lift the companion safety core"), PR, green, merge.

### Task 4: Our own read-only queries (`ChatQueries`) and the fixture

**Files:**
- Create: `Sources/CompanionCore/ChatQueries.swift`, `Tests/CompanionCoreTests/CompanionFixture.swift` (the fork fixture plus Task 1's added columns), `Tests/CompanionCoreTests/ChatQueriesTests.swift`
- Lift into `ChatQueries`: the fork reader's `threads(guids:)`, `sendIdentity(chatGUID:)`, `maxRowID()`, `highWaterRowID()` (`CompanionReader.swift:101-111`), `firstRowID(since:)`, the read-only open, `busy_timeout` and error type. Do not lift `rows`, `dataVersion`, the decode marker or `AttributedBodyDecoder`.

**Interfaces:**
- Produces:
  - `final class ChatQueries { init(path: String) throws(ChatQueryError) }`
  - `func threads(guids: Set<String>) throws(ChatQueryError) -> [CompanionThread]`
  - `func threads(chatRowIDs: Set<Int64>) throws(ChatQueryError) -> [Int64: CompanionThread]`
  - `func sendIdentity(chatGUID: String) throws(ChatQueryError) -> CompanionSendIdentity?` (no `service` field)
  - `func twinChatRowIDs(chatGUID: String) throws(ChatQueryError) -> Set<Int64>` (the chat itself plus every chat row with the same normalized participant set)
  - `func rowFacts(rowIDs: [Int64]) throws(ChatQueryError) -> [Int64: RowFacts]`, with `struct RowFacts { itemType: Int; hasBody: Bool; error: Int; isSent: Bool }`
  - `func fromMeChatRowIDs() throws(ChatQueryError) -> Set<Int64>`
  - `func maxRowID() throws(ChatQueryError) -> Int64`
  - `func highWaterRowID() throws(ChatQueryError) -> Int64` (`sqlite_sequence` for `message`, falling back to `maxRowID()` as the fork does)
  - `func firstRowID(since: Date) throws(ChatQueryError) -> Int64?`

- [ ] **Step 1: Failing tests** (fixture only): `test_sendIdentityIgnoresServiceName` (a chat with `service_name = 'SMS'` still returns its identity); `test_twinChats` (two chat rows with the same two handles in different formats → both IDs; a third with one extra handle excluded); `test_rowFacts` (a system row `item_type = 1`, a row with a body blob and null text → `hasBody`, a row with `error = 22`); `test_fromMeChats`; `test_highWaterSurvivesDeletingNewest` (delete the last fixture row: `maxRowID` drops, `highWaterRowID` doesn't); `test_openIsReadOnly` (an `UPDATE` through the connection fails with `SQLITE_READONLY`); the lifted `threads` and `sendIdentity` tests.
- [ ] **Step 2:** Run `swift test --filter ChatQueriesTests`. Expected: FAIL.
- [ ] **Step 3:** Implement. `sendIdentity` no longer selects or requires `chat.service_name`. The `sendColumns` requirement shrinks to `message: error, is_sent`. `twinChatRowIDs` compares `HandleNormalizer`-normalized handle sets.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit, PR, merge on green.

### Task 5: Reading through `IMsgCore` (`CompanionService`)

**Files:**
- Create: `Sources/CompanionCore/MessageSource.swift`, `Sources/CompanionCore/MessageMapper.swift`
- Lift and modify: `Sources/CompanionCore/CompanionService.swift`
- Modify: `CompanionScrubber.swift`
- Tests: `MessageMapperTests.swift`, `CompanionServiceTests.swift` (lifted, then changed), `CompanionScrubberTests.swift`

**Interfaces:**
- Consumes: `ChatQueries` (Task 4), `CompanionConfig.tunables` (Task 3).
- Produces:
  - `protocol MessagePaging: Sendable { func page(after rowID: Int64, limit: Int) throws -> MessagesAfterPage }`, with `struct IMsgCorePaging: MessagePaging` wrapping `MessageStore.messagesAfterPage(afterRowID:chatID: nil, limit:includeReactions: true)`
  - `enum MessageMapper { static func map(_ m: Message, facts: RowFacts?, thread: CompanionThread?, fromMeChats: Set<Int64>) -> MappedRow }`, with `enum MappedRow { case message(CompanionMessage), system, orphan }`
  - `CompanionScrubber.isSkipped(senderHandle: String?, text: String?, threadHasFromMe: Bool) -> Bool`
  - `CompanionService.tick() async -> CompanionStatus` (as the fork), plus `var isPaused: @Sendable () async -> Bool` injected (Task 8 supplies the effective pause)

- [ ] **Step 1: Mapper tests** on hand-built `Message` values (via its public init): `unsentAt != nil` → `.message` with `unsent: true` before any kind rule; `facts.itemType != 0` → `.system`; `chatID == 0` → `.orphan`; `isReaction` → `.reaction`; `""` text with `attachmentsCount 2` → `.attachmentOnly`; `""` with `hasBody` and 0 attachments → `.unreadable`; otherwise `.text`; `service` copied from `Message.service`; `fromMe` → `senderHandle` nil.
- [ ] **Step 2: Scrubber tests:** a code text from `+15555550100` in a thread with no from-me row → skipped; the same in a thread with one → not skipped (SSN still scrubbed); a 5-digit short-code sender → skipped either way.
- [ ] **Step 3: Service tests** on the fixture through `IMsgCorePaging`, keeping every lifted loop test (batch limit 200, body-size halving, first-run window 3 days, backoff from tunables, cursor clamp to the ack). New ones:
  - `test_cursorAdvancesToNextRowIDPastDroppedRows` (a URL-preview duplicate row at the end: cursor = its ROWID)
  - `test_recentOrphanHoldsCursorBelowIt` (orphan dated now: cursor = orphan ROWID − 1; dated 20 s ago: passed)
  - `test_systemRowsNotUplinked`
  - `test_databaseReplaced` (Review Focus 1: cursor 500, `highWaterRowID` 10 → nothing posted, status `last_error == "database_replaced"`, cursor still 500)
  - `test_deletingNewestIsNotReplacement` (cursor at the last row, that row deleted → no `database_replaced`, the next new row is uplinked)
  - `test_pausedSkipsUplink` (the `isPaused` closure returns true)
- [ ] **Step 4:** Run them. Expected: FAIL.
- [ ] **Step 5:** Implement. `tick()` loads the from-me set once at start, adds each page's from-me chat IDs, and takes `thread_guid` and participants from `ChatQueries.threads(chatRowIDs:)`. The orphan hold caps the batch cursor at `orphan.rowID − 1` and ends the page there when the orphan's date is within `orphanHold` (10 s) of `now`. Otherwise the cursor is `page.nextRowID`.
- [ ] **Step 6:** Run `swift test`. Expected: PASS.
- [ ] **Step 7:** Run `send-safety-reviewer` on the diff (reading, the kind map and the scrubber change). Fix Critical and Important findings test-first.
- [ ] **Step 8:** Commit, PR, merge on green.

### Task 6: Unsends from the watcher

**Files:**
- Create: `Sources/CompanionCore/UnsendRelay.swift`, `Tests/CompanionCoreTests/UnsendRelayTests.swift`

**Interfaces:**
- Consumes: `CompanionUplinking`, `ChatQueries.threads(chatRowIDs:)`, `MessageMapper`.
- Produces: `actor UnsendRelay { init(events: @escaping @Sendable () -> AsyncThrowingStream<Message, Error>, ...); func run() async }`, where the production `events` is `MessageWatcher(store:).stream(sinceRowID: nil, configuration: .init(includeReactions: false))`. Plus `var restarts: Int` and `var pending: Int` for status.

- [ ] **Step 1: Failing tests** with a fake stream:
  - a `Message` with `mutationEvent == .unsent` → one batch posted with one message, `unsent: true`, `text: nil`, the saved cursor unchanged
  - `.edited` and plain new rows → nothing posted
  - an uplink failure → the re-post stays pending and goes on the next try
  - Review Focus 2: the stream throws `MessageWatcherOverflowError`, then a second stream yields an unsend → `restarts == 1` and the unsend is posted
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. All `POST /imsg/messages` calls (the reading loop's and the relay's) go through one `UplinkSerializer` actor, so batches are posted one at a time, as the contract requires. Re-posts are held in memory (lost on restart, which the design accepts). Retry uses the tunables backoff. Nothing is posted while paused or while the fork is running (Task 8 closures).
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit, PR, merge on green.

### Task 7: The send path on every route

**Files:**
- Lift and modify: `Sources/CompanionCore/CompanionSendExecutor.swift`; tests `CompanionSendExecutorTests.swift`, `CompanionSendReadTests.swift`, `CompanionSendDecisionTests.swift`
- Run `send-safety-reviewer` (the new repo's copy) on this task's diff before merging.

**Interfaces:**
- Consumes: `ChatQueries.sendIdentity`, `twinChatRowIDs`, `rowFacts`, `maxRowID`; `CompanionSendScript.source(dispatch:)`; `IMsgCore` `MessageStore.messagesAfterPage(afterRowID:chatID:limit:includeReactions:)` for read-back text and service.
- Produces:
  - `CompanionSendExecutor.cycle() async -> CompanionSendStatus` (as the fork)
  - `func preflight(chatRowID: Int64) async -> PreflightResult` (`ready` or `refused(code: Int)`)
  - `var onControl: @Sendable (SendsPage.Control?) -> Void`

- [ ] **Step 1: Failing tests** (fake runner, fake uplink, fixture):
  - `test_smsLabelledChatSends` (`service_name 'SMS'` → dispatched)
  - `test_scriptHasNo9003`
  - `test_pollRunsWhenSendsOff` (one GET returning one send: `onControl` called, the runner never called, **no ledger record written, no send-result posted**, status `.off`; after `sends on` the same send, still unexpired, is dispatched)
  - `test_pollRunsWhenPaused` (the same with local or remote pause)
  - `test_readBackFindsTwinRow` (the sent row lands in a twin chat → `sent`, `sent_service` = that row's service)
  - `test_baselineIsGlobalMax` (a row in another chat between the baseline read and dispatch is ignored by the match)
  - `test_readBackPagesPastBusyRows` (60 rows in other chats land before the sent row → still `sent`)
  - `test_expiredAfterSleep` (Review Focus 3: `expiresAt = now − 1` → `not_sent`/`expired`, no ledger dispatch, never handed to the runner again)
  - `test_preflightNeverDispatches` (the runner gets `source(dispatch: false)`; the ledger is untouched)
  - Every lifted executor test that doesn't assert the removed service rule
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - Remove the `identity.service` guard.
  - Move the `sendsEnabled`/paused returns to after `fetchSends` and `onControl`, so control always arrives. When sends are off or paused, the fetched list is ignored: no ledger write and no result post, so a send waits for `sends on` (as today, when it isn't fetched at all) or expires on HomeChat's side. The lifted `refuse(record, .sendsOff)` path is no longer reached from a poll.
  - The baseline is `ChatQueries.maxRowID()`.
  - Read-back pages `messagesAfterPage(afterRowID: baseline, chatID: nil, limit: 50, includeReactions: false)` until `hasMore == false` (`messagesAfter` returns only the first non-empty batch, so a busy Mac could hide the sent row and wrongly report `no_readback`), keeps `isFromMe` rows whose `chatID ∈ twinChatRowIDs`, and joins `rowFacts` for `error`/`isSent`. `CompanionSendDecision` keeps its rules.
  - `sent_service` is the matched row's `service`, or nil.
  - The cap comes from tunables.
  - `preflight` uses `source(dispatch: false)` with the same arguments, and maps `READY` to `ready` and `NOT_SUBMITTED:<code>` to `refused`.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Run `send-safety-reviewer` on the diff. Fix Critical and Important findings test-first.
- [ ] **Step 6:** Commit, PR, merge on green.

### Task 8: Status, control, permissions and the single uploader

**Files:**
- Create: `Sources/CompanionCore/AgentStatus.swift`, `PauseState.swift`, `Permissions.swift`, `ForkGuard.swift`, `StatusReporter.swift`, `ContactsNameResolver.swift` (lifted from the fork's `msgblast/Companion/ContactNameResolver.swift`, a fork-added file)
- Tests: `PauseStateTests.swift`, `StatusReporterTests.swift`, `ForkGuardTests.swift`

**Interfaces:**
- Produces:
  - `struct AgentStatus: Codable, Equatable` with keys `device_id`, `agent_version` (git sha), `imsgcore_version` (`"0.21.0"`, a constant set alongside `Package.resolved`), `permissions {full_disk_access, automation_messages, contacts}` (each `granted|denied|unknown`), `paused`, `sends_enabled`, `last_uplink_at`, `last_error`, `last_update {result: installed|rolled_back|failed|none, version, at}`, `bump_pending_since`, `ci_red_since`, `watcher_restarts`, `fork_running`
  - `actor PauseState { func setRemote(_ paused: Bool?); func effective(local: Bool) -> Bool }`
  - `protocol ForkDetecting { func isForkRunning() -> Bool }` (production: `NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.goldalex98.msgblast-imessage").isEmpty == false`)
  - `actor StatusReporter { func tick(now: Date) async }`: posts when 900 s have passed since the last post or when the status (minus timestamps) changed
  - `enum Permissions { static func contacts() -> PermissionState; static func fullDiskAccess(path: String) -> PermissionState }` (automation comes from the last preflight or send runner code: −1743 → denied, a run → granted, else unknown)

- [ ] **Step 1: Failing tests:**
  - Review Focus 5: `setRemote(true)` → effective true; local true plus `setRemote(false)` → true; `setRemote(nil)` → follows local
  - Status posts at 900 s, and at once on a change of `paused`
  - Status JSON carries no field outside the key list (decode into a strict mirror)
  - Fork running → `CompanionService.tick` and `UnsendRelay` post nothing and status `fork_running: true`
  - Review Focus 4: the Contacts resolver with access denied → names nil, uplink proceeds, `permissions.contacts == "denied"`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Add `UplinkClient.postStatus(_ status: AgentStatus) async throws(UplinkError)` (`POST imsg/status`, the same auth, HTTPS-only and redirect rules as the other routes; 204 is success). Wire `PauseState` into `CompanionService.isPaused`, `UnsendRelay` and `CompanionSendExecutor.onControl`.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Run `send-safety-reviewer` on the diff (the new route, control and permissions). Fix Critical and Important findings test-first.
- [ ] **Step 6:** Commit, PR, merge on green.

### Task 9: Commands and the run loop

**Files:**
- Create: `Sources/CompanionCore/Commands.swift` (parsing and the config edits, testable), `Sources/CompanionCore/HealthMark.swift`, `Sources/imsg-companion/main.swift` (wiring only)
- Tests: `CommandsTests.swift`, `HealthMarkTests.swift`

**Interfaces:**
- Produces:
  - `enum Command { case run, setup(url: URL), status, pause, resume, sendsOn, sendsOff, preflight(chatRowID: Int64), promptContacts, update }`, with `static func parse(_ args: [String]) -> Command?`
  - `struct HealthMark: Codable { version: String; startedAt: Date; readOKAt: Date?; homechatOKAt: Date? }` written to `<support>/health.json`
  - `<support>/preflight-request.json` (`{chat_rowid}`) and `<support>/preflight-result.json` (`{chat_rowid, result, code?, at}`)

- [ ] **Step 1: Failing tests:**
  - `parse(["sends","on"]) == .sendsOn`
  - `pause` sets `paused: true` and leaves `sends_enabled` alone
  - `sends on` writes only `sends_enabled`
  - `setup` with the token on stdin saves it through `CompanionTokenStoring` and never writes it to config; an empty token → error, as fork PR #21 does
  - A preflight request file is consumed once and a result written
  - The health mark gets `readOKAt` after a successful tick and `homechatOKAt` after a 2xx
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - `run` starts `CompanionService` (2 s tick), `UnsendRelay`, `CompanionSendExecutor` (continuous cycle) and `StatusReporter`. It reloads config every cycle. On SIGTERM it stops taking new sends, lets an in-flight dispatch and read-back finish, then exits 0.
  - `setup <url>` saves config and token. If `CNContactStore.authorizationStatus(for: .contacts)` is `.notDetermined`, it runs `/usr/bin/open -n -a <own .app path> --args prompt-contacts`.
  - `prompt-contacts` calls `requestAccess` and exits.
  - `status` prints the local `AgentStatus` (counts and states only).
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Run `send-safety-reviewer` on the diff (the commands, the preflight request file and the SIGTERM path). Fix Critical and Important findings test-first.
- [ ] **Step 6:** Commit, PR, merge on green.

### Task 10: The app bundle, signing and launchd

**Files:**
- Create: `Resources/Info.plist` (`CFBundleIdentifier` `io.github.goldalex98.imsg-companion`, `CFBundleExecutable` `imsg-companion`, `CFBundleName` `ImsgCompanion`, `LSUIElement` true, `NSContactsUsageDescription`, `NSAppleEventsUsageDescription`, `CFBundleShortVersionString` from the build); `Resources/ImsgCompanion.entitlements` (`com.apple.security.automation.apple-events` true); `scripts/build-app.sh`; `scripts/install.sh`; `launchd/agent.plist.template` (`RunAtLoad`, `KeepAlive {SuccessfulExit: false}`, `ExitTimeOut 90`, `ProgramArguments [<app>/Contents/MacOS/imsg-companion, run]`); `launchd/updater.plist.template` (`StartCalendarInterval {Hour 3, Minute 30}`, `ProgramArguments [..., update]`)

- [ ] **Step 0:** Alex's existing identity hash is copied to `~/.config/imsg-companion/signing-identity` (outside the repo, the same value as the fork's file; never printed).
- [ ] **Step 1:** `build-app.sh [--verify-only] [--out DIR]` runs `swift build -c release` and assembles `ImsgCompanion.app`. It writes the git sha into `Info.plist`, signs with `codesign --force --options runtime --entitlements Resources/ImsgCompanion.entitlements --sign "$(cat ~/.config/imsg-companion/signing-identity)"`, then verifies (`codesign --verify --strict`; `codesign -d -r-` names the identifier and the certificate, with no `cdhash`; `plutil -lint`). `--verify-only` builds into a temp folder and signs ad hoc (`-`), so CI and the gate need no keychain.
- [ ] **Step 2:** `install.sh` copies the app to `~/Applications/`, fills the plist templates with `$HOME`, and `launchctl bootstrap gui/$(id -u)` both. Re-run: `bootout` first. It never starts sends and never runs `setup`.
- [ ] **Step 3:** Add `scripts/build-app.sh --verify-only` to CI and the gate. Run it on the MacBook. Expected: exit 0.
- [ ] **Step 4:** On the MacBook, build signed and install, with sends off and no token, so `run` idles in "not set up". Check: `launchctl print gui/$(id -u)/io.github.goldalex98.imsg-companion` shows it running, with parent pid 1; `status` reports `full_disk_access: denied` until Alex grants it. Alex makes the System Settings grant himself.
- [ ] **Step 5:** Commit, PR, merge on green.

### Task 11: The nightly updater

**Files:**
- Create: `Sources/CompanionCore/Updater.swift`, `Sources/CompanionCore/CommandRunning.swift` (a `Process` wrapper protocol), `Tests/CompanionCoreTests/UpdaterTests.swift`

**Interfaces:**
- Produces:
  - `struct UpdaterPaths { src, app, previous, state }`
  - `struct UpdateState: Codable { failedCommits: [String]; lastResult: AgentStatus.LastUpdate?; ciRedSince: Date?; bumpPendingSince: Date? }` at `<support>/update-state.json`
  - `actor Updater { func runOnce(now: Date) async -> AgentStatus.LastUpdate }`, with injected `CommandRunning`, a GitHub client (`headSHA()`, `isGreen(sha:)` from the public Actions API for workflow `ci.yml`, `oldestOpenDependabotPR()`), a HomeChat reachability check, a ledger in-progress check, and a health-mark reader

- [ ] **Step 1: Failing tests** with fakes, each asserting the exact `CommandRunning` call sequence:
  - head equals installed → `none`, no build
  - head not green → `none`, `ciRedSince` set; green later → cleared
  - green new head → `git -C src fetch/checkout <sha>`, `swift test`, `build-app.sh --out <tmp>`, then `launchctl bootout`, move to `previous/`, install, `launchctl bootstrap`, a health mark with the new version within 180 s → `installed`
  - no health mark in 180 s → restore `previous/`, `rolled_back`, sha added to `failedCommits`; the next night the same sha → `none`
  - HomeChat unreachable → `none`, nothing touched
  - a ledger record in progress for over 600 s → `none` (deferred)
  - at start, no app but `previous/` exists → restored
  - `swift test` fails → `failed`, sha recorded, nothing swapped
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. `src` is `<support>/src`, a clone of `https://github.com/Goldalex98/imsg-companion.git` made on first run. The commit checked green is the commit checked out (`git checkout --detach <sha>`). A lock file skips overlapping runs.
- [ ] **Step 4:** Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit, PR, merge on green. Live proof waits for acceptance U8.

### Task 12: Dependabot and the auto-merge job

**Files:**
- Create: `.github/dependabot.yml`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1:** `dependabot.yml`: `version: 2`, `updates: - package-ecosystem: swift, directory: "/", schedule: {interval: daily}, cooldown: {default-days: 3}, open-pull-requests-limit: 3`.
- [ ] **Step 2:** In `ci.yml`, add job `automerge` with `needs: test` and `if: github.event_name == 'pull_request' && github.event.pull_request.user.login == 'dependabot[bot]'`, `permissions: {contents: write, pull-requests: write, actions: write}`. Its steps, with `GH_TOKEN: ${{ github.token }}`:
  1. `gh pr diff ${{ github.event.pull_request.number }} --name-only`, and exit 0 without merging unless every line is `Package.swift` or `Package.resolved`
  2. `gh pr merge <n> --merge --match-head-commit ${{ github.event.pull_request.head.sha }}`
  3. `gh workflow run ci.yml --ref main`
- [ ] **Step 3:** Validate the YAML with `actionlint` if installed (`command -v actionlint`), else by the first real Dependabot PR. Commit, PR, merge on green.
- [ ] **Step 4 (live, later):** On the first Dependabot PR, check: it waited 3 days after the release; `automerge` ran only after `test`; the merge commit is a merge (not squash); a `workflow_dispatch` run on `main` followed and was green. GitHub documents that a Dependabot `pull_request` run gets a read-only `GITHUB_TOKEN` that the workflow's `permissions:` key can raise, and that cooldown supports `swift`: documented, live check pending. Still unverified: whether Dependabot's swift updater rewrites an `exact:` pin. If it doesn't open or doesn't merge, report it; don't add a PAT or other secret.

### Task 13: Runbooks for cutover and acceptance

**Files:**
- Create: `docs/runbooks/cutover.md`, `docs/runbooks/stage-u.md`, `docs/runbooks/stage-s.md`
- Modify: `.claude/STATUS.md` (both repos)

- [ ] **Step 1:** `cutover.md` follows design §5.7 exactly: HomeChat §7 deployed (checked by a `POST /imsg/status` returning 204 with the new token); HomeChat holds 0 unfinished sends; a new device token issued in HomeChat; the fork app quit and its Login Item off (Alex); the fork's `cursor` read from its `companion.json` (counts-only command) and written into the new config; `setup`; grants by Alex; start. Then the rollback steps, and "revoke the fork's token before Stage S".
- [ ] **Step 2:** `stage-u.md` covers U1–U9 (U7 notes the remote-pause gap from "Decided here") and `stage-s.md` covers S0–S5 from design §6. For each: the action, who does it (Alex or Claude), the counts-only check and the pass line. Stage S marks every real send "Alex's typed yes first, test contact only".
- [ ] **Step 3:** Update both repos' STATUS (the fork: frozen except cutover notes; the agent: ready for cutover, waiting on HomeChat's deploy). Commit, PR, merge on green.

---

## Review record

- Fable plan review 2026-11-15: sound with changes; all nine findings folded in (no expiry ceiling, `highWaterRowID` kept, sends ignored while off or paused, the send-safety reviewer on Tasks 3, 5, 7, 8 and 9, paged read-back, serialized uplink posts, the remote-pause gap noted, Task 1 signed with the real entitlements, Dependabot facts restated).

## Self-review notes

- Spec coverage:
  - §5.1 → Tasks 2, 9, 10
  - §5.2 → Tasks 4, 5, 6
  - §5.3 → Tasks 2, 3
  - §5.4 → Tasks 3, 7
  - §5.5 → Task 8
  - §5.6 → Tasks 11, 12
  - §5.7 → Tasks 8 (single uploader), 13
  - §5.8 → Global Constraints and Task 3's forbidden-API test
  - §6 → Task 13 (run later)
  - §9 → Task 1 (dependency), Task 2 (first CI run on Xcode 27), Task 12 Step 4 (Dependabot's `exact:` handling); the others are checked in acceptance
- Unproven after this plan, by design: signing from launchd (U8); the Contacts prompt through `open -n` and Automation under the agent (U9, S0); group, SMS and RCS through `IMsgCore` and decoder accuracy (U3–U6); identity checks on SMS and RCS (S0, S3); Dependabot's handling of an `exact:` pin (Task 12 Step 4).

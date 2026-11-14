# Phase 3 natural replies, Mac side: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac tells HomeChat each thread's service, reports plain, accurate codes when a send is refused, never started, or fell back to a green-bubble text, and is proven on `any;` chats as macOS 27 names them.

**Architecture:** Small additive changes to the phase 3 files in `msgblast/Core/Companion/`. The reader adds `service` to `CompanionThread` and to the outgoing read-back rows. The decision code maps script codes and the fallback. The executor reports a send it could not start instead of going silent. No new files, no new tests targets, no Xcode project change.

**Tech Stack:** Swift 6.4, SQLite (read-only), `/usr/bin/osascript`, XCTest with synthetic `chat.db` fixtures; Python 3 for the acceptance preflight probe.

**Spec:** HomeChat's natural-replies design (`homechat-bot`, 2026-11-14), §8 (thread service), §9 (this Mac half), §10 (acceptance) and §11.3 (deploy order); the plan it amends: `docs/superpowers/plans/2026-11-11-phase3-mac-approved-replies.md`. Contract: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`. Phase 3 acceptance stopped at check B on 2026-11-14 (`.claude/LOG.md`).

**Out of scope here:** everything in HomeChat's half (the reader's `send`/`change`/`skip`, the echo, the queue, the GUID-prefix gate, outcome wording). Also not here: a Mac-side change to what is sent or when (the send script, ledger, expiry and caps are unchanged), resolving an `in_progress` record that never reached dispatch after a crash (still `ambiguous` / `recovered_after_restart`).

## Global Constraints

- Never write `chat.db`, mark messages read, send typing indicators or touch Messages' UI state; reads stay read-only SQLite (CLAUDE.md).
- Never retry an `ambiguous` or uncertain send. A `send_id` with any ledger record is never dispatched again.
- The Mac keeps its own send-time check authoritative: a thread whose `chat.service_name` is not `iMessage` is refused `not_sent` / `not_imessage` before any script runs.
- `detail` is one of the fixed codes in `SendDetail`, never free text. New codes: `database_unreadable_before` (not_sent) and `confirmed_fallback` (sent). Both are rejected with 400 by a HomeChat that predates its natural-replies deploy, and the Mac halts on a rejection.
- **Deploy order:** Task 0 (the no-send identity preflight) runs first of all, before any build and before HomeChat deploys: HomeChat's deploy removes its `iMessage;` GUID gate, after which the old Mac build could send. Then HomeChat deploys. Merging this branch is safe (sends stay off by default); building, signing and installing the Mac app waits for Alex's confirmation that HomeChat's natural-replies change is deployed, and for a live check of that, not a remembered one. The `service` field is safe in either order (HomeChat ignores extra keys).
- No names, numbers, handles, chat GUIDs, message text, HomeChat host, tokens or private paths in code, tests, fixtures, docs, commits or PR text. Test GUIDs and handles are invented (`any;-;+15555550100`, `any;+;chat-test`). The GUID prefix shapes `any;-;` and `any;+;` are public.
- Fixtures are synthetic `chat.db` data only. No real send in development; real sends only in the Task 6 acceptance (Task 0 sends nothing), with Alex's typed yes, to a test contact and a test group.
- This plan adds no files, so `scripts/generate_project.py` is not run and `COMPANION_SUITES` in `scripts/ci_native_scope.py` is unchanged. If an executor does add a file, it runs the generator and adds the suite in the same task. Only companion files change, so the fork CI runs the companion suites.
- Test runs: `.claude/agents/quality-gate.md:20-23` allows only the two gate commands as written, so below, `run the native tests` means the gate's full native command (`xcodebuild ... -only-testing:msgblastTests test`, as `docs/testing.md` gives it), and `run the Python tests` its step 1. A per-suite `-only-testing:msgblastTests/<Suite>` run is faster but is not in the allow rules: it prompts, and a subagent that is denied it stops and reports (never improvises). Suite names in steps say which tests must go red then green, not which command to use.
- Branch `feat/natural-replies-mac` from `main`, PR in the fork (`--repo Goldalex98/msgblast-imessage`). One commit per task.

## Findings from reading the code (decided here)

- **Script codes** (`CompanionSendScript.swift:28-47`): 9001 chat id differs from the target; 9002 participant count differs; 9003 account service is not iMessage; 9004 a passed handle is not a participant; 9005 bad argument layout; −1743 Automation denied; −1728 is AppleScript's "can't get chat id …" (an unresolvable chat). They only reach the decision as `.notSubmitted` (before `submissionAttempted`). The spec's mapping is right for 9002, 9003, 9004. **−1728 is unverified**: it is AppleScript's generic "can't get", so it could also arise from the account lookup; the runbook's step 0 observes it. **9001 is not in the spec's mapping** (the chat resolved but under a different id): this plan leaves it `script_refused`, as the spec says "the rest", and flags it.
- **Where the mapping goes:** the spec says `CompanionSendDecision.swift` ~20-21; that is where `.notSubmitted(code: -1743)` is mapped today, so the new cases go beside it.
- **`service_name` and a missing column:** `COALESCE` alone does not survive a missing column (the SELECT fails). `CompanionReader.threads(guids:)` therefore checks `PRAGMA table_info(chat)` first and selects `''` when the column is absent. The existing `sendIdentity` already COALESCEs but requires the column (send methods only), which stays.
- **`threads()` re-built in `CompanionService.swift:150-154`** copies the struct and edits `participants`, so a `service` field on `CompanionThread` survives it with no change there.
- **One service normaliser:** `CompanionSendExecutor.swift:159` compares `identity.service == "iMessage"` exactly, while Task 1 maps case-insensitively. Task 1 defines `CompanionThread.Service(chatServiceName:)` as the only comparison; the executor (Task 4 step) and the read-back rule (Task 3) use it.
- **Why a failed read is retried, not failed at once:** the reader's busy timeout is 1.5 s (`CompanionReader.swift:70`), so one failed read can be transient. `cycle()` already treats it as "retry on the next hand-out"; that stays. HomeChat hands a send out only while unexpired, so the Mac reports `database_unreadable_before` after `expires_at`, from memory (HomeChat accepts a late real result: design §7.2).
- **A `dispatchedAt == nil` record cannot have run:** the runner is called only after `ledger.update` of `dispatchedAt` succeeds (`CompanionSendExecutor.swift:174-179`). An `in_progress` record without it, left by a failed update or a crash, therefore finishes as `not_sent` / `database_unreadable_before`, not `ambiguous`. Finishing it as ambiguous would clash with what HomeChat may already hold and turn into a 409, which halts the Mac (`:263`).
- **Read-back:** `outgoingRows` selects `error`, `is_sent` only (`CompanionReader.swift:344`). The sent row's `message.service` is not read today.

## Review Focus

1. **`service_name` column missing, NULL or empty** (an older macOS, a synthetic schema): reading and uplink must not stop; the thread is sent with `service` omitted (unknown). Task 1 (`test_threadsWithoutServiceColumnStillRead`, `test_emptyServiceIsOmitted`).
2. **Odd values** (`iMessage` in another case, a service the Mac has never seen): never an error. Known names map case-insensitively; anything else non-empty is `other`. Task 1 (`test_serviceMapping`).
3. **Messages falls back to SMS/RCS after the pre-check passed**, or the row's service flips between polls: the result is `sent` / `confirmed_fallback`, never `ambiguous` because of the service, and a `message.service` column that is missing reads as plain `confirmed`. Task 3.
4. **`chat.db` unreadable (or the ledger unwritable) for one read, or until expiry; an approved send hit by a refusal while the ledger is unwritable; a crash or failed write between `begin` and the `dispatchedAt` update:** one failed read never fails an approved send; after expiry it is `not_sent` / `database_unreadable_before`; a refusal is reported with its own detail; a never-dispatched record resolves `not_sent` (also after a restart), never `ambiguous`; none is dispatched later. Task 4.
5. **A thread that exists in `chat.db` but whose `any;+;` id AppleScript will not resolve** (−1728), or whose account is not "iMessage" in AppleScript's eyes for an `any;` chat: refused before any send; the mapping (−1728 → `thread_missing`) is only a guess until the runbook shows what Messages returns. Task 2 and Task 6 step 0 (the first live check; the unit tests prove only the mapping).

---

### Task 0: No-send identity preflight (before any build, before HomeChat deploys)

Why first: it asks whether Messages' AppleScript resolves an `any;-;` and an `any;+;` iMessage chat on macOS 27 at all. If not (−1728 or 9003 on a chat `chat.db` lists as iMessage), the send script itself needs a design change and nothing below is worth building. It must also run before HomeChat's deploy removes the `iMessage;` GUID gate. It sends nothing, builds nothing and installs nothing.

**What exists** (`companion/spikes/`): `pick_chat.py` writes one test chat's GUID and handles into `.local/spikes/config.json` (it needs Alex to give a test group's name or a test contact's handle; it matches exactly one chat and prints only a participant count). `send_probe.py --preflight` runs the same identity checks as the app's script (chat id, account service, participant count, members: `send_probe.py:53-70`) with `return "READY"` instead of `send`, prints the outcome word, and writes a counts-only report to `.local/spikes/` (outcome, code, timings, frontmost app; no GUID, handle, name or text). **Gaps today:** the report and the console do not say which GUID prefix or service the chosen chat has, so a pass proves nothing about `any;`; and the chats are chosen by what Alex types, which stays local.

**Files:**
- Modify: `companion/spikes/pick_chat.py` (save and print the chat's GUID prefix shape and `service_name`)
- Modify: `companion/spikes/send_probe.py` (add `guid_prefix` and `chat_service` to the report; extend `ALLOWED` by `any;-;`, `any;+;`, `iMessage;-;`, `iMessage;+;`, `SMS;-;`, `iMessage`, `SMS`, `RCS`, `other`)
- Test: `scripts/tests/test_companion_send_probe.py`, `scripts/tests/test_companion_groups.py` or the file that covers `pick_chat` (Python gate)

**Interfaces:**
- `pick_chat` stores `config[kind]["guid_prefix"]` (the GUID up to and including its second `;`, e.g. `any;-;`) and `config[kind]["service"]` (`service_name` normalised to `iMessage`/`SMS`/`RCS`/`other`), and prints `wrote <kind> target with N participants, prefix <shape>, service <name>`. Never the GUID, handles or names.
- `run_probe` copies both into its report dict (older configs without them report `unknown`).

- [ ] **Step 1: Write failing tests:** `test_pickChatRecordsPrefixShapeAndService` (an `any;-;` iMessage and an `any;+;` RCS fixture chat; console output contains the shape and service and none of the GUID tail or handles); `test_preflightReportCarriesPrefixAndService`; `test_reportStillCountsOnly` (`assert_counts_only` accepts the new fields and still rejects a GUID-shaped string).
- [ ] **Step 2: Run the Python tests** (gate step 1). Expected: fail.
- [ ] **Step 3: Implement** both changes.
- [ ] **Step 4: Run the Python tests.** Expected: pass.
- [ ] **Step 5: Commit** `Spikes: record GUID prefix shape and service in the no-send preflight`. (Merge this as its own small PR first if the rest isn't ready; it needs no Mac build.)
- [ ] **Step 6: Alex runs the preflight in Terminal.app** (Claude's shell lacks the Messages Automation and Full Disk Access grants Terminal has, per the project's Mac workflow; Claude doesn't run it). Needs from Alex: the name of a test group that is iMessage and one test contact's handle, typed into the two `pick_chat.py` commands in Terminal; then `send_probe.py --target one_to_one --label pre1 --preflight` and the same for `group`. He pastes back only the console lines and the report path's contents (counts-only). Prefix shapes must read `any;-;` and `any;+;` with service `iMessage`; if a chosen chat reads otherwise, pick another test chat.
- [ ] **Step 7: Decide.** Pass = both print `outcome: ready` with the right prefix shapes. A `not_sent` with code −1728 or 9003 on such a chat = stop; bring it back to Alex before anything else in this plan. Record the result (outcome words and codes only) in `.claude/LOG.md`. Other codes (9002, 9004) mean the chosen chat's participant list differs from `chat.db`'s: report and re-pick.

### Task 1: Thread `service` on the uplink

**Files:**
- Modify: `msgblast/Core/Companion/CompanionModels.swift:18-41` (`CompanionThread`)
- Modify: `msgblast/Core/Companion/CompanionReader.swift:181-218` (`threads(guids:)`)
- Modify: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md` (the `threads` field table and example)
- Test: `msgblastTests/CompanionModelsTests.swift`, `msgblastTests/CompanionReaderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension CompanionThread {
      public enum Service: String, Codable, Sendable { case iMessage, sms = "SMS", rcs = "RCS", other
          public init?(chatServiceName: String?)   // nil for nil/empty; case-insensitive iMessage/SMS/RCS; else .other
      }  // the ONLY service comparison in the companion: Tasks 3 and 4 call it, never `== "iMessage"`
  }
  // CompanionThread gains:  public var service: Service?   (init parameter `service: Service? = nil`, last)
  ```
  Wire key `service`, encoded only when non-nil (`encodeIfPresent`); the other keys keep today's explicit-null encoding.
- `threads(guids:)` selects `COALESCE(service_name, '')` when `PRAGMA table_info(chat)` lists `service_name`, else `''`, and sets `service` from `Service(chatServiceName:)`. The fingerprint is unaffected.

- [ ] **Step 1: Write failing tests.**
  - `CompanionModelsTests.test_threadEncodesServiceAndOmitsWhenUnknown`: `service: .sms` encodes `"service":"SMS"`; `nil` leaves the key out; `.iMessage` encodes `"iMessage"`, `.rcs` `"RCS"`, `.other` `"other"`.
  - `test_threadDecodesContractExampleWithAndWithoutService` (decode the updated contract JSON; an older shape without the key gives `service == nil`).
  - `CompanionReaderTests.test_serviceMapping`: threads for `service_name` `iMessage`, `imessage`, `SMS`, `RCS`, `Satellite` give `.iMessage, .iMessage, .sms, .rcs, .other`.
  - `test_emptyServiceIsOmitted`: `service_name` empty and NULL give `nil`.
  - `test_threadsWithoutServiceColumnStillRead`: `CompanionFixture(sendColumns: false)`; `threads(guids:)` returns the thread with `service == nil`, and `rows(after:)` still works.
  - `test_anyGUIDsReportTheirOwnService`: `any;-;` 1:1 with `SMS` and `any;+;` group with `RCS` report `.sms` / `.rcs` (the GUID prefix is never consulted).
- [ ] **Step 2: Run the native tests** (suites `CompanionModelsTests` and `CompanionReaderTests` go red/green). Expected: build fails.
- [ ] **Step 3: Implement** the enum, the field with `encodeIfPresent` in `CompanionThread.encode(to:)`, `CodingKeys.service`, and the reader change.
- [ ] **Step 4: Update the contract.** Add `threads[].service` to the table: `iMessage`, `SMS`, `RCS` or `other`, from the chat's `service_name`; omitted when the Mac can't tell (unknown); additive, older readers ignore it; added to the example thread. Note it is sent only with threads a batch references, so a quiet thread stays unknown until its next message.
- [ ] **Step 5: Run the native tests** (suites `CompanionModelsTests`, `CompanionReaderTests`, `CompanionServiceTests` go red/green). Expected: pass.
- [ ] **Step 6: Commit** `Companion: thread service on the uplink`.

### Task 2: Map the script's refusal codes

**Files:**
- Modify: `msgblast/Core/Companion/CompanionSendDecision.swift:20-21`
- Modify: contract, the `thread_changed`, `thread_missing`, `not_imessage`, `script_refused` rows.
- Test: `msgblastTests/CompanionSendDecisionTests.swift`

**Interfaces:**
- Consumes: `ScriptResult.notSubmitted(code:)` (`CompanionSendScript.swift:8-10`), `SendDetail` cases that already exist (`notIMessage`, `threadChanged`, `threadMissing`, `scriptRefused`).
- Produces: `decide(script:rows:deadlinePassed:isMatch:)` returns, for `.notSubmitted`: −1743 → `automationDenied`; 9003 → `notIMessage`; 9002, 9004 → `threadChanged`; −1728 → `threadMissing`; any other code (9001, 9005, unknown) → `scriptRefused`. All `not_sent`, anchor nil, rows not consulted. `.failedToStart` stays `scriptRefused`.

- [ ] **Step 1: Write failing tests** (replace `test_otherRefusalsAreNotSentWithoutReadingRows`):
  - `test_scriptCodeMapping`: a table of `(code, detail)` for 9003, 9002, 9004, −1728, −1743, 9001, 9005, 42, each `.final(.notSent, detail, anchorGUID: nil)`.
  - `test_mappedRefusalsIgnoreRows`: with a matching sent row present, `.notSubmitted(9003)` is still `not_sent`.
  - `test_uncertainCodesAreNeverMapped`: `.uncertain(code: 9003)` and `.uncertain(code: -1728)` stay on the `ambiguous` path (a code after `submissionAttempted` must never become `not_sent`).
- [ ] **Step 2: Run the native tests** (suite `CompanionSendDecisionTests` goes red/green). Expected: fail.
- [ ] **Step 3: Implement** the mapping as one `switch` on the code beside the existing −1743 case.
- [ ] **Step 4: Run the native tests** (suites `CompanionSendDecisionTests` and `CompanionSendExecutorTests` go red/green). Expected: pass.
- [ ] **Step 5: Contract:** list the script codes for each detail in its Meaning column (`not_imessage` also "Messages' account for the chat isn't iMessage"; `thread_changed` also "Messages saw a different participant list"; `thread_missing` also "Messages can't find the chat").
- [ ] **Step 6: Commit** `Companion sends: map identity-script codes to plain details`.

### Task 3: Read-back reports the sent row's service; `confirmed_fallback`

**Files:**
- Modify: `msgblast/Core/Companion/CompanionReader.swift:287-300,339-358` (`CompanionOutgoingRow`, `outgoingRows`)
- Modify: `msgblast/Core/Companion/CompanionSendDecision.swift` (rule for a confirmed match)
- Modify: `msgblast/Core/Companion/CompanionSendModels.swift:38-46` (`SendDetail`)
- Modify: `msgblastTests/CompanionFixture.swift`: with `sendColumns` add `message.service TEXT DEFAULT 'iMessage'`; `addMessage(... service: String = "iMessage")` writes it. `sendColumns: false` has none.
- Modify: contract (`confirmed_fallback` row; outcome `sent`)
- Test: `msgblastTests/CompanionSendReadTests.swift`, `CompanionSendDecisionTests.swift`, `CompanionSendModelsTests.swift`, `CompanionSendExecutorTests.swift`

**Interfaces:**
- Produces: `CompanionOutgoingRow.service: String?` (nil when the column is absent or NULL/empty; `init` parameter `service: String? = nil` last, so existing literals compile). `SendDetail.confirmedFallback = "confirmed_fallback"` (`allCases.count` becomes 22 here, 23 after Task 4).
- `outgoingRows` reads `message.service` only when `PRAGMA table_info(message)` lists it; it is not added to `sendColumns`, so a schema without it still reads (and reads as unknown).
- Decision rule 4 changes: exactly one match, `isSent`, `error == 0` and the row's `service` mapping (`CompanionThread.Service(chatServiceName:)`, Task 1) to anything but nil or `.iMessage` gives `.final(.sent, .confirmedFallback, anchor)`. Same match with `service` nil or `iMessage` stays `.confirmed`. Error and ambiguity rules run first and are unchanged.

- [ ] **Step 1: Write failing tests.**
  - `CompanionSendReadTests.test_outgoingRowsReportService`: rows with `iMessage`, `SMS`, `RCS` read back those strings; `test_outgoingRowsWithoutServiceColumn`: the `sendColumns: false` schema fails with `.unsupportedSchema` as before, and a send-columns fixture with the `message.service` column dropped (`ALTER TABLE ... DROP COLUMN` in the test) reads rows with `service == nil`.
  - `CompanionSendDecisionTests.test_smsOrRCSConfirmedRowIsSentFallback`, `test_iMessageAndUnknownServiceAreConfirmed`, `test_fallbackRowWithErrorIsStillNotSent`, `test_fallbackNeverMasksTwoMatches` (ambiguous).
  - `CompanionSendModelsTests`: the code-list test counts 22 and the contract lists every code.
  - `CompanionSendExecutorTests.test_fallbackToSMSIsSentAndConfirmedFallback`: the fake Messages writes the row with `service: "SMS"`; the posted result is `.sent` / `.confirmedFallback` with the row's anchor, and exactly one runner call. `test_serviceFlipDuringSettlePollsResolves`: the row shows `iMessage` on the first poll and `SMS` afterwards; the final result is `sent` (either detail), never `ambiguous`.
- [ ] **Step 2: Run the native tests** (the four named suites go red/green). Expected: fail.
- [ ] **Step 3: Implement** the column check, the row field, the code and the rule. The executor's recovery path needs no change (`recoveredAfterRestart` still wins there).
- [ ] **Step 4: Run the native tests** (every companion suite). Expected: pass.
- [ ] **Step 5: Contract:** `confirmed_fallback`: sent; as `confirmed`, but the new row's service was SMS or RCS (Messages delivered it as a green-bubble text). HomeChat treats it as sent.
- [ ] **Step 6: Commit** `Companion sends: report an SMS or RCS fallback as sent / confirmed_fallback`.

### Task 4: A send that never started is reported, never dispatched later

**Files:**
- Modify: `msgblast/Core/Companion/CompanionSendExecutor.swift:91-103,113-130,136-222` (`cycle`, `recover`, `process`, `refuse`)
- Modify: `msgblast/Core/Companion/CompanionSendModels.swift` (`SendDetail`)
- Modify: contract (`database_unreadable_before` row)
- Test: `msgblastTests/CompanionSendExecutorTests.swift`, `CompanionSendModelsTests.swift`

**Interfaces:**
- Produces: `SendDetail.databaseUnreadableBefore = "database_unreadable_before"` (count 23). `process(_:) async -> SendRecord?` keeps its type; `nil` now means only "not ready yet, no record, try again when handed out".
- Executor memory (lost on restart, which is safe: nothing was dispatched, and HomeChat hands an unresulted send out again until it expires):
  - `private var held: [String: SendRecord]`: finished records the ledger could not store, posted with their own outcome and detail until HomeChat answers `200` or `404`.
  - `private var deferred: [String: (record: SendRecord, expiresAt: Date)]`: sends that could not be prepared yet. `record` is the finished `not_sent` / `databaseUnreadableBefore` result, kept unposted.
- Behaviour, replacing today's returns at `:149`, `:156`, `:173`, `:175` and the nil in `refuse` (`:211`):
  1. **Read failure before dispatch** (the database won't open, or `sendIdentity` / `maxRowID` throws) **and `ledger.begin` throwing at `:173`:** no record, no dispatch, `deferred[send_id]` is set, the send is left for the next hand-out, and the cycle ends as `.stopped(Self.unreadable)` today. A later hand-out that gets past these steps removes the `deferred` entry and carries on normally. One failed read never fails an approved send.
  2. **`deferred` entries past `expiresAt`:** reported at the start of every cycle (`cycle()` before the fetch; backoff and halts as for any report) as `not_sent` / `database_unreadable_before` with the Mac's own hash and no anchor, then removed. A post that fails stays for the next cycle.
  3. **`ledger.update` of `dispatchedAt` throwing at `:175`:** the record stays `in_progress` with `dispatchedAt == nil`, and the send is not dispatched. `cycle` already skips it (`ledger.exists`).
  4. **`recover()`:** an `in_progress` record with `dispatchedAt == nil` finishes as `not_sent` / `databaseUnreadableBefore` with no anchor and no database read (the script cannot have run: `:174-179`). Records with `dispatchedAt` set resolve exactly as today (`sent` or `ambiguous` / `recoveredAfterRestart`). This holds across restarts; no per-process "never dispatch" set is needed.
  5. **`refuse(_:_:)`** returns the finished record even when `ledger.begin` throws: it goes into `held` with its own detail (`expired`, `hash_mismatch`, `thread_changed` ...) and is reported like any record. A fetched send whose id is in `held` is re-posted, never processed again.
  6. A refusal that has no ledger record and is not held can't occur after 5; `process` returns `nil` only for case 1.
- Service check: `identity.service == "iMessage"` at `:159` becomes `CompanionThread.Service(chatServiceName: identity.service) == .iMessage` (Task 1), so the executor and the uplink read one normaliser. An `identity.service` of `Satellite` is refused `not_imessage`.

- [ ] **Step 1: Write failing tests** (fixture `chat.db`, fake runner and uplink as the existing tests; "unreadable" means `chmod 000` on the fixture file, restored after; "unwritable ledger" means `chmod 0o500` on the ledger folder after the first, empty cycle has taken the lock):
  - `test_oneUnreadableCycleDoesNotFailTheSend`: unreadable, a send expiring in 120 s: cycle 1 posts nothing and runs nothing; restore; the same send handed out again is sent normally (`sent` / `confirmed`).
  - `test_unreadableUntilExpiryReportsNotSentDatabaseUnreadableBefore`: still unreadable, clock past `expiresAt`, an empty page: exactly one post, `.notSent` / `.databaseUnreadableBefore`, anchor nil, 0 runner calls; a further cycle posts nothing more.
  - `test_unwritableLedgerDefersThenReportsAfterExpiry`: the same with the ledger unwritable; restoring the mode and re-handing out before expiry sends it normally.
  - `test_refusalWithUnwritableLedgerIsReportedWithItsOwnDetail`: a hash-mismatch send with the ledger unwritable posts `.notSent` / `.hashMismatch` (not `database_unreadable_before`); a failed first post (503) is retried from `held`; a re-handout re-posts the same result and never runs the script.
  - `test_neverDispatchedRecordResolvesNotSent`: seed the ledger with `begin` of a record with `dispatchedAt == nil`, run a cycle: `.notSent` / `.databaseUnreadableBefore`, finished and reported, 0 runner calls, and it is not `ambiguous`.
  - `test_neverDispatchedRecordResolvesNotSentAfterRestart`: the same record, a second `CompanionSendExecutor` instance on the same ledger folder resolves it identically; a record with `dispatchedAt` set still resolves `recoveredAfterRestart` (the existing recovery tests stay green).
  - `test_executorUsesTheSharedServiceNormaliser`: a chat whose `service_name` is `imessage` sends; `Satellite` is refused `not_imessage`.
  - `CompanionSendModelsTests`: the code count is 23 and the contract lists every code.
- [ ] **Step 2: Run the native tests.** Expected: the new tests fail (the model test and executor tests do not build or do not pass).
- [ ] **Step 3: Implement** `held`, `deferred`, the `recover()` rule, the `refuse` change, the shared normaliser and the `cycle` changes. Reuse `report(_:_:key:)`; a held or deferred record is a `SendRecord` with `state == .finished` that is not in the ledger (`markReported` already no-ops then).
- [ ] **Step 4: Run the native tests.** Expected: all pass, including the unchanged `test_ambiguousNeverRetried`, `test_redeliveredSendIsNotDispatchedAgain` and the recovery tests.
- [ ] **Step 5: Contract:** `database_unreadable_before`: not_sent; the Mac never started the send (`chat.db` couldn't be read, or its send ledger couldn't be written, until the send expired; or a crash or write failure left a record that never reached dispatch). Nothing was sent and it is never dispatched later. It may arrive after `expires_at`. Distinct from `database_unreadable` (after dispatch, ambiguous). Add the deploy-order note: HomeChat must accept this code and `confirmed_fallback` before this Mac build is installed.
- [ ] **Step 6: Commit** `Companion sends: report a send that never started, never dispatch it later`.

### Task 5: `any;` and service fixtures across the suites

**Files:**
- Modify: `msgblastTests/CompanionSendExecutorTests.swift` (GUID constants at the top, `test_smsThreadRefused`)
- Modify: `msgblastTests/CompanionReaderTests.swift`, `CompanionSendReadTests.swift`, `CompanionModelsTests.swift`, `CompanionServiceTests.swift`, `UplinkClientTests.swift`, `CompanionScrubberTests.swift` (GUID literals)
- Modify: the contract's examples (`thread_guid` values) and the send example
- Test: the suites above

**Interfaces:** none new. Test-only plus contract examples. Default fixture chats become `any;-;<handle>` (1:1, `iMessage`) and `any;+;<id>` (group, `iMessage`); a few `iMessage;` GUIDs stay (a legacy one in the executor, the reader and the models test) so both prefixes are covered.

- [ ] **Step 1: Write the new tests first** (they fail or are trivially green against the old GUIDs; the point is the combinations):
  - Executor: `test_anyDirectIMessageSends`, `test_anyGroupIMessageSends` (arguments carry the `any;` GUID verbatim), `test_anySMSDirectRefusedNotIMessage`, `test_anyRCSDirectRefusedNotIMessage`, `test_anySMSGroupRefusedNotIMessage`, `test_anyRCSGroupRefusedNotIMessage` (each: 0 runner calls, `.notSent` / `.notIMessage`), `test_legacyIMessageGUIDStillSends`.
  - Reader/read: `test_anyThreadsMixedServicesUplinkTheirOwnService` (a batch with one `any;-;` iMessage, one `any;-;` SMS, one `any;+;` RCS), `test_sendIdentityOnAnyGUIDs`.
  - Contract/models: `test_contractExampleUsesAnyGUID`: the updated example JSON decodes (thread with `service`, send with an `any;` `thread_guid`).
- [ ] **Step 2: Run the native tests** (the suites named above). Expected: the new tests fail only where Tasks 1-4 aren't yet in (none should after them); fix test data until failures are real.
- [ ] **Step 3: Move the GUID literals** in the listed suites from `iMessage;` to `any;`, keeping the legacy cases named above.
- [ ] **Step 4: Run every companion suite.** Expected: pass.
- [ ] **Step 5: Commit** `Companion tests: any; GUIDs and service combinations`.

### Task 6: Rewrite the acceptance runbook

**Files:**
- Modify: `docs/superpowers/runbooks/phase3-mac-acceptance.md` (rewritten in place)

The runbook is a document; no tests. Its steps are written so each states its evidence and stays counts-only.

- [ ] **Step 1: Header and prerequisites.** Link HomeChat's natural-replies design and this plan. The HomeChat prerequisites become: the natural-replies change **deployed** (the echo, the `any;` GUID acceptance, the two new detail codes, the `service` field stored), checked live by Alex before the Mac build is installed. Keep the build, signing, install, rollback and focus-baseline sections. Keep "these checks send real iMessages: Alex's typed yes per check, test contact or test group only".
- [ ] **Step 2: Step 0 is Task 0's result.** The runbook opens with it: the no-send preflight (one `any;-;` and one `any;+;` iMessage chat, via `pick_chat.py` and `send_probe.py --preflight`, run by Alex in Terminal.app) was run before any build and before HomeChat's deploy; the runbook records its date and outcome words, and tells the reader to re-run it only if the Mac's macOS version changes. It also says what −1728 and 9003 would have meant (Task 2).
- [ ] **Step 3: Checks, in this order, wording per the new flow.** Each one: Alex replies to HomeChat's nudge in his own words; HomeChat shows the echo; he says yes in his own words; read the outcome in the three places already listed (WhatsApp line, Mac Details "Last reply", HomeChat counts-only readback of `outcome`, `detail`, anchor yes/no).
  - **B, 1:1:** a change with an accent and an emoji (`Café at 6 👍🏽`), then a plain "send it" on a suggested reply. Pass: each arrives once, the first intact; `sent` / `confirmed` with an anchor; the flag clears on his phone.
  - **C, group:** the same in the test group.
  - **D, Mac offline past expiry:** Mac network off, approve, wait over 10 minutes, network on. Pass: "No word from your Mac…" or "not sent, your Mac was asleep" (as HomeChat words it); the Mac never sends it later. Also pass: no `database_unreadable_before` result appears (nothing was fetched).
  - **E, quit during the read-back:** unchanged. Pass: `recovered_after_restart`, exactly one copy, no second send.
  - **G, focus:** during B and C Messages isn't brought to the front.
  - **H, two items in one message (new):** with two test items open ("send 1, 2 change to …" in his words). Pass: one echo listing both, one yes, each recipient receives exactly one message, two `sent` results.
  - **I, green-bubble item refused before the echo (new):** needs a test thread whose `service_name` is SMS or RCS (counts-only check), **with a green-bubble message that arrives after the new build is installed**: existing threads keep `service` unknown on HomeChat until their next uplinked message, and an unknown service is not refused before the echo (the Mac refuses it at send time instead). Check first, counts-only, that HomeChat shows that thread's service as SMS/RCS. Pass: HomeChat refuses it with the green-bubble line before any echo; the Mac receives no send (ledger count unchanged).
  - **A, switch off (optional):** unchanged.
  - F (changed group) stays unrun unless Alex wants it.
- [ ] **Step 4: What the runbook leaves unproven.** State plainly: an SMS fallback at runtime (`confirmed_fallback`) and `database_unreadable_before` are unit-proven only, because producing them would mean forcing a fallback or breaking `chat.db` / the ledger; Automation-denied and the daily cap likewise.
- [ ] **Step 5: Commit** `Runbook: phase 3 acceptance for natural replies`.

### Task 7: Review, gate, PR, status

**Files:**
- Modify: `.claude/STATUS.md` (rewrite in place), `.claude/LOG.md` (append)
- Modify: `FORK.md` only if an upstream file changed (none expected: all changes are in fork-only paths; state so in the PR)
- Modify: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md` (check the final text once for consistency across Tasks 1-5)

- [ ] **Step 1: Run the `send-safety-reviewer` agent** on the branch diff against the Global Constraints. Fix Critical and Important findings test-first; record any declined, with reasons, in the PR.
- [ ] **Step 2: Run the Mac gate** exactly as `.claude/agents/quality-gate.md` gives it: the Python script tests, then the native core tests (`docs/testing.md`). Expected: 0 failures. Use the two commands as written (no per-suite flags: they aren't in the allow rules). State the host that ran it. On a first-run timeout in an upstream driver test, re-run that test alone and say so.
- [ ] **Step 3: Update STATUS and LOG.** STATUS: the Mac half is merged and not installed; the install waits for HomeChat's deploy; Task 0's preflight result is recorded; the next step is the runbook's B, C, D, E, G, H, I after HomeChat's deploy. LOG: the decisions above (mapping, the 9001 and −1728 flags, the retry-until-expiry rule, `dispatchedAt == nil` records resolving `not_sent`, omitted-when-unknown `service`, `held` / `deferred`), under a dated heading, no personal data.
- [ ] **Step 4: Open the PR** in the fork (`--repo Goldalex98/msgblast-imessage`) with branch, identity, whether pushed, and that no merge into HomeChat is needed. Find the exact run by head sha (`gh run list --commit <sha>`), watch it with one background `gh run watch <run-id> --exit-status`, merge (merge commit) when green and mergeable under the standing rule, and check the run on `main`. The merge is not an approval to install or to send.
- [ ] **Step 5: Stop at the deploy gate.** Do not run `companion/build_fork_app.py`, sign, install or restart the app. Tell Alex the Mac is ready for install and that it waits for HomeChat's deploy, then for his go-ahead for each real send in the runbook.

## Self-review

- **Spec coverage (§9, §8, §10, §11.3):** 1 → Task 1; 2 → Task 2; 3 → Task 4; 4 (fixtures) → Task 5; 5 (read-back) → Task 3; 6 (service read, COALESCE) → Task 1; §8 → Task 1; §12 first acceptance step → Task 0; §10 acceptance → Task 6; deploy order → Global Constraints, Task 4 step 5, Task 7 step 5. No gap.
- **Type consistency:** `CompanionThread.Service` / `service`, `CompanionOutgoingRow.service`, `SendDetail.confirmedFallback` and `.databaseUnreadableBefore`, `held` and `deferred` are each defined in one task and referenced by name afterwards. `SendDetail.allCases.count`: 21 now, 22 after Task 3, 23 after Task 4.
- **Proportion:** the spec's Mac half is one section; this plan is test names, signatures and checks, with no function bodies.

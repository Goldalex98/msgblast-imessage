# iMessage companion as a standalone agent: design

2026-11-14 · from a brainstorm with Alex after the no-send `imsg` trial · Fable-reviewed 2026-11-14 (sound with changes, folded in) · **approved by Alex 2026-11-15** (Claude's "my call" defaults accepted as written) · nothing built

Supersedes, for the Mac half: the msgblast fork as the companion's host, and the natural-replies Mac plan (`docs/superpowers/plans/2026-11-14-phase3-natural-replies-mac.md`, never built). The companion design (`2026-11-07-imessage-companion-design.md`) still holds for intent, goals and the HomeChat side except where this file says otherwise. HomeChat's half changes only through `homechat-bot`'s own design amendment and PRs (§7).

This file lives here until the new repo exists, then moves to that repo's `docs/`.

Labels: **Alex** = decided by Alex (with the date). **Evidence** = measured on the MacBook, counts only. **My call** = Claude's default, which Alex can override.

## 1. Intent

The companion reads Alex's texts on his MacBook, flags the ones waiting on him, sends them to HomeChat, clears a flag when he replies, and sends a reply only after he approves its exact text. Replies stopped on 2026-11-14 (HomeChat's `iMessage;` gate against macOS 27's `any;` chats). Three reviews then found the method too heavy and the rules too rigid for what has actually been proven.

Alex uses msgblast only for the companion (Alex, 2026-11-14). So the companion leaves the fork and becomes a small background agent that does just this job. It reads through `openclaw/imsg`'s `IMsgCore` library instead of our own reader, keeps the safety core already written (scrubber, uplink, send ledger, identity checks), and drops the fork's costs: upstream merges, the design gate, the project generator and a 12–20 minute native suite for an app he doesn't use.

**Success:** replies work again on every route; the agent runs unattended, including `imsg` updates; Alex never has to review code to keep it current; nothing is ever sent without his approval of the exact words.

## 2. Goals, non-goals, anti-goals

**Goals**
- Everything the fork companion did: read 1:1 and group chats, uplink, flag, clear on reply, approved sends (Alex, 2026-11-07).
- Replies on every route: iMessage, SMS, RCS, 1:1 and group (Alex, 2026-11-14).
- Unsends reach HomeChat and clear their flag (new; my call). Edits are deferred: they need a HomeChat update path and flag re-judging (Fable).
- Status through HomeChat, no menu-bar icon (Alex, 2026-11-14: "whichever is easier", no icon if it's more work). A remote pause from WhatsApp is my call (from Fable's pivot review), not something Alex asked for.
- `imsg` updates arrive and install without Alex reviewing them (Alex, 2026-11-14; mechanism in §5.6).

**Non-goals (this design)**
- New conversations, attachments in replies, tapbacks as replies (unchanged from 2026-11-07; my call).
- HomeChat's reply flow itself (natural replies, verbs, confirms): that is `homechat-bot`'s approved natural-replies design. This design only changes what the Mac sends and accepts.
- Calendar (phase 2) and Duet tools (phase 4): no Mac change needed.
- A menu-bar icon or any window.

**Anti-goals (a failure even if it works)**
- Anything sent as Alex without his approval of the exact words (Alex).
- An ambiguous send retried (2026-11-07 design).
- Writing `chat.db`, marking texts read, typing indicators, touching Messages' UI (repo rule).
- A Social Security number reaching HomeChat or Claude (Alex).
- Two uploaders running at once (Fable pivot review).
- Personal data in the public repo (repo rule).
- Nag spam, including status alerts (2026-11-07 design).

## 3. Facts this rests on

- **`imsg` trial** (Evidence, 2026-11-14, macOS 27.2, `imsg` 0.21.0):
  - 1,796 chat rows; only `any;-;` (1,130 direct) and `any;+;` (548 group). No direct chat lacks exactly one participant.
  - `listChats` omits the 118 empty chats.
  - The live watch reported new, edited, unsent and from-me events on a 1:1 chat, the new rows within 1 s.
  - Not shown: group, SMS and RCS rows in watch; text decoding accuracy.
- **`chat.service_name` is stale** on macOS 27 (Evidence, 2026-11-14: a blue-bubble group reads SMS, 6,156 iMessage rows to 1 SMS). Messages picks the route per send. The send never takes a service.
- **Packaging test** (Evidence, 2026-11-14, a throwaway app, since deleted):
  - A small signed `.app` started by a launchd user agent (parent pid 1) does not inherit anyone else's grants.
  - After Alex granted it Full Disk Access, it opened `chat.db` read-only. It also created and read back its own login-Keychain item with no prompt.
  - Rebuilt with a new code hash and swapped in over the installed copy, it kept both, with no prompt and no re-grant.
  - Its designated requirement is bundle ID plus the Apple Development certificate, with no code hash.
- **Skip rule on real data** (Evidence, 30 days of inbound):
  - The verification-code keyword rule skipped 13 texts, all in threads Alex never wrote in, and 0 where he has.
  - Short-code senders: 82 skipped.
  - 56 threads Alex never wrote in sent 157 texts. 86 of them, from ordinary phone numbers, were not skipped.
- **Mac sleep** (Evidence, last 7 days): 15 sleeps, 14 under 10 minutes, 0.9 h in all. A 10-minute approval window rarely meets a sleeping Mac at home.
- **`IMsgCore`** (source at `openclaw/imsg` 264f9252 and release 0.21.0):
  - A library product (MIT). It opens `chat.db` read-only.
  - Its `Message` carries `rowID`, `chatID`, `guid`, `sender`, `text`, `date`, `isFromMe`, per-message `service`, `attachmentsCount`, reactions, `editedAt` and `unsentAt`.
  - `messagesAfter(afterRowID:)` pages by ROWID. `MessageWatcher` streams new rows and edit/unsend events. Edits and unsends are not replayed after a restart.
  - Depends on SQLite.swift and PhoneNumberKit, and links ScriptingBridge and Contacts.
- **Companion code** (fork, `msgblast/Core/Companion/`): about 2,000 lines, no ties to msgblast. It uses Foundation, SQLite3, CryptoKit, Security and LocalAuthentication. 12 test files run on a synthetic fixture.

## 4. Approaches

**Where the companion lives** (decided before this design; Alex accepted Fable's pivot direction 2026-11-14 17:40 ET, conditional on the trial, which passed):
- A. Stay in the fork. Pays every fork cost for an unused app. Rejected.
- B. A script around `imsg rpc` / the `imsg` binary. Smallest, but it throws away the tested Swift. It also leaves a Homebrew-upgraded binary holding Full Disk Access, and inherits `imsg`'s send path with no identity check. Rejected (Fable).
- **C. Picked: a standalone Swift agent that links `IMsgCore` as a library and keeps our own scrubber, uplink, ledger and send script.**

**How it's packaged** (Alex picked the first, 2026-11-14, after the packaging test):
- **Picked: a small signed app bundle with no window, started by launchd.** Grants show under its own name and survive rebuilds (proven by the test).
- A bare command-line binary plus a launchd plist. Grants are listed by path, and attribution and re-sign survival are less certain.
- Hosting inside the fork app. Rejected with A.

**How updates reach the Mac** (Alex picked the first, 2026-11-14):
- **Picked: tagged `imsg` releases only, a 3-day wait after release, then merge on green CI, then a nightly rebuild and install on the Mac with rollback and a report to HomeChat.**
- Merge on green, but install only after Alex's one-word yes in WhatsApp.
- Every release, immediately.

**Build order** (Alex picked the first, 2026-11-14):
- **Picked: one build with both halves and sends off. Accept reading and uplink first, then Alex switches sends on for the reply checks.**
- Reading only first, sending as a second build.
- Everything at once.

## 5. Design

### 5.1 Shape

- **Repo:** new public repo `Goldalex98/imsg-companion` (Alex: new public repo; name and MIT licence are my call). It holds only our code; `IMsgCore` comes in as a SwiftPM dependency. The lifted files are our own work from the fork's companion folder. The one upstream-derived helper (`ChatResolver.normalize`) is rewritten, not copied. The same public-repo rules apply: no personal data, synthetic fixtures only.
- **Product:** one Swift executable inside `ImsgCompanion.app` (bundle ID `io.github.goldalex98.imsg-companion`, my call). It is an agent-style app (`LSUIElement`: no Dock icon, no menu bar, no windows), not background-only, so it can show the Contacts and Automation prompts, signed with Alex's existing Apple Development identity, installed in `~/Applications`, hardened runtime, with the Apple Events entitlement plus Contacts and Apple Events usage strings.
- **Launch:** a launchd user agent (`RunAtLoad`, `KeepAlive` on crash), so it starts at login and restarts if it dies. A second launchd agent runs the nightly updater (§5.6).
- **Commands** (same binary; my call):
  - `run`: what launchd starts.
  - `setup`: HomeChat URL, then the device token read from stdin into the Keychain.
  - `status`: local status, counts only.
  - `pause` / `resume`.
  - `sends on` / `sends off`.
  - `preflight <chat rowid>`: the no-send identity check, so Automation is granted to the agent, not to Terminal.

  `status`, `pause`/`resume` and `sends on`/`off` edit or read `companion.json`, which the running agent reloads every cycle. `preflight` writes a request file that the running agent executes and reports in its status, so Automation is used by the agent itself. Only `setup` needs the app's own identity for its Keychain write and first prompts. It runs as a fresh launch through LaunchServices before the launchd agent is loaded (`open -a` passes arguments only to an app it starts, not to a running one; Fable). That attribution is unproven (§9). If S0 or U9 shows a prompt can't be triggered this way, the builder stops and brings it back rather than picking a fallback.
- **Config:** `~/Library/Application Support/imsg-companion/companion.json`, with the same keys as the fork: `uplink_url`, `device_id`, `paused`, `cursor`, `sends_enabled`. Plus tunables that were constants before (expiry ceiling, daily cap, backoff), so changing them is a config edit, not a rebuild (Fable audit; my call). The ledger lives beside it. The Keychain item is a login generic password, as in the fork.

### 5.2 Reading

- `IMsgCore` (pinned at release 0.21.0, which has per-message `service`, `editedAt` and `unsentAt`) replaces our message reader, `AttributedBodyDecoder` and file watching.
- **Cursor:** the raw `message.ROWID` of the last accepted row, as in the fork. Pages come from `messagesAfterPage(afterRowID:…, includeReactions: true)`, and the cursor advances to its `nextRowID`. That is the last row scanned, not the last row returned, because `IMsgCore` drops duplicate URL-preview rows and, by default, reactions. `MessageWatcher.stream` is required, because it is the only public source of edit and unsend events (the mutation functions are internal). Paging stays the source of new rows. A row with no chat join yet comes back with `chatID` 0, and `nextRowID` moves past it, so the orphan hold must cap the cursor below it. The batch limits, orphan hold and backoff behave as in the fork, and so does the first-run window, except at cutover (§5.7).
- **Our own small read-only queries stay** for what `IMsgCore` doesn't give: system rows (`item_type`), the set of threads Alex has written in, and the send path's identity and read-back queries. They use the same read-only connection rules and the same Full Disk Access. The rest of `CompanionReader` goes.
- **Kinds map 1:1** to the existing contract:
  - reaction: `isReaction`
  - attachment_only: empty text with `attachmentsCount` > 0
  - unreadable: decided by our own per-page query (below), because `IMsgCore` has no unreadable signal. Its `text` is non-optional, a failed decode gives `""`, and a non-typedstream blob is decoded as lossy UTF-8 (`TypedStreamParser.swift:4-27`, v0.21.0)
  - skipped: the scrubber
  - text: everything else

  Unsent rows arrive with empty text and 0 attachments, so `unsentAt` is checked before the kind map. System rows (`item_type` ≠ 0) are passed over, as before. `IMsgCore` returns them and doesn't expose the column, so our per-page query supplies `item_type` and whether a body is present.
- **Per-message service:** each uplinked message carries `IMsgCore`'s per-message `service` (iMessage / SMS / RCS / other). Thread-level service is never sent, because `chat.service_name` is stale (§3).
- **Unsends:** when the watcher reports one, the agent re-posts that message with the same `guid` and `unsent: true` (no text). They are seen only while the agent runs, which is accepted. Edits are deferred (§2).
- **Names:** from the Contacts framework, as in the fork. If Contacts is denied, names are null and status says `contacts: denied`.
- **Scrubber:** SSN removal, the 4,000-character cut and the short-code skip stay as they are. The verification-code keyword skip applies only in threads where Alex has never sent a message (Alex, 2026-11-14). The agent keeps a set of threads with any `is_from_me` row, refreshed as it reads.

### 5.3 Uplink contract changes

The contract (`2026-11-08-imsg-uplink-contract.md`) stays as it is, with only additive, optional fields. HomeChat must ignore unknown fields before the Mac sends them. Deploy order: HomeChat first.
- `messages[].service`: iMessage, SMS, RCS or other (per message).
- `messages[].unsent`: a re-post of a known `guid`. HomeChat marks that message unsent and clears its flag.
- `send-results.sent_service`: the service of the sent row read back from `chat.db` (Fable routes pass). `not_imessage` is retired (never produced, still accepted).
- New `POST /imsg/status` (§5.5).
- `GET /imsg/sends` response: optional `control.paused` (§5.5).
- The new `device_id` must match HomeChat's `mac-[0-9a-f]{8}` (`auth.py:10`).
- New device ID and token for the agent. The fork's token is revoked after cutover (§5.7).

### 5.4 Sending

Lifted from the fork's executor, ledger and script, unchanged except as follows.
- **Kept:**
  - exact-text hash
  - expiry
  - non-blank text without control characters
  - thread present
  - participant fingerprint match
  - the script's chat-id, participant-count and handle checks (9001, 9002, 9004)
  - exclusive ledger record before dispatch
  - read-back of the sent row
  - ambiguous never retried
  - the `sends_enabled` switch (off by default)
- **Dropped:**
  - every iMessage assumption (Alex: every route): the executor's `service_name` check (`CompanionSendExecutor.swift:163`), the identity query's requirement for `chat.service_name` (`CompanionReader.swift:304`), and the script's 9003 account check (`CompanionSendScript.swift:36`). HomeChat's own (`sends.py:47,76,120`) are in §7
  - the separate approval-length rule (expiry covers it; Fable audit)
- **Daily cap:** kept on the Mac as a tunable, default 30. My call. It equals HomeChat's own approval cap (`sends.py:20`), so in normal use it never binds first and adds no friction. It bounds the rate, not the harm: if HomeChat itself were compromised, the Mac could still send up to 30 forged texts a day, because it can verify only that the text matches what HomeChat sent, not that Alex approved it.
- **Result:** reports `sent_service`. The Mac keeps its detail codes. HomeChat stops rejecting unknown ones (the 422 at `send_route.py:66`) and already shows an unknown one as "the Mac refused it" (`sends.py:203`). The outcome stays strict (sent / not_sent / ambiguous).
- **Read-back** also looks at the thread's other chat rows for the same participants (imsg #394: Messages can file a send under a twin row). So the baseline becomes the global highest `message.ROWID`, not the chat's own (`CompanionSendExecutor.swift:153`). The builder decides the matching.
- **`preflight`:** runs the script's checks without the `send` line and reports ready / the refusal code. It is used in acceptance on iMessage, SMS and RCS chats before any real send.

### 5.5 Status and control

- **Status:** `POST /imsg/status` every 15 minutes and on any change (my call). It carries:
  - `device_id`, agent version, `IMsgCore` version
  - permission states: full_disk_access, automation_messages, contacts (granted / denied / unknown)
  - `paused`, `sends_enabled`
  - last uplink time, last error (free text, no message data)
  - last update result (installed / rolled_back / failed / none, with version and time), and "bump pending or CI red since <date>", so a breaking `imsg` 0.x bump that fails CI doesn't sit unseen (`imsg` shipped 0.17 to 0.21 in 20 days)

  HomeChat shows it on request and in the twice-daily update. It mentions staleness only in that update, with no separate alerts (anti-goal: nag spam). A laptop that is away is normal.
- **Control** (my call): HomeChat may set `control.paused` in the `GET /imsg/sends` response, so Alex can pause from WhatsApp. The agent is paused if either the local flag or the remote one says so. A remote `false` never undoes a local pause. The send poll always runs, even with sends off or paused, so control can arrive (today's executor skips it: `CompanionSendExecutor.swift:70-71`).
- **Stopping sends from WhatsApp** needs no Mac change: HomeChat simply refuses to queue. **Turning sends on is local only** (`sends on` at the Mac, which Claude can run from its shell on Alex's say-so). A compromised server can pause the agent but never enable sending. My call.

### 5.6 Updates

- **Dependency:** `IMsgCore` pinned to an exact release tag. Its transitive packages are pinned by `Package.resolved`.
- **Bump bot:** Dependabot (`swift` ecosystem) with a 3-day `cooldown` opens PRs only for tagged releases. Renovate is out: it rewrites `Package.resolved` only for registry pins, not URL pins (Fable, sourced from both projects' docs).
- **Auto-merge:** the last job of the CI workflow merges the PR with a merge commit. It runs only when the test job is green, the author is `dependabot[bot]`, and the diff touches only `Package.swift`/`Package.resolved`. It then triggers a CI run on `main` with `workflow_dispatch`, because a merge made with `GITHUB_TOKEN` starts no push run. It uses `GITHUB_TOKEN` with `contents: write` and no other secret. GitHub's own auto-merge setting isn't used: with no required check it would merge before CI. (Alex, 2026-11-14, for the bump bot in this repo only.) Every other PR follows the fork's rule: Claude merges on green, no auto-merge.
- **CI:** `swift build` and `swift test` on GitHub's macOS runner (xcode-27), with no secrets.
- **Nightly updater** (a launchd calendar job, about 03:30 local; launchd runs a missed job at the next wake; it skips if a run is under way):
  1. Fetch `main` into a dedicated clone under `~/Library/Application Support/imsg-companion/src` (not a dev checkout).
  2. Continue only if `main`'s head has a green CI run (GitHub's public API) and differs from the installed build. The commit checked is the commit built.
  3. Run `swift test` and build release.
  4. Sign with the Apple Development identity and verify the signature and designated requirement. If `codesign` prompts for key access the first time, Alex chooses Always Allow once, as with the fork on 2026-11-08.
  5. Check HomeChat is reachable; if not, try again the next night (offline must not roll back a good build). Wait until no send record is in progress (the ledger lock itself is held for the agent's whole life, `CompanionSendLedger.swift:48-58`, so it can't be the test). If that takes over 10 minutes, try again the next night. Stop the agent with `launchctl bootout`, because a plain kill lets `KeepAlive` restart the old binary mid-swap. The agent finishes any in-flight send on SIGTERM, within a raised `ExitTimeOut`. Then move the old app to `previous/`, install the new one, start it.
  6. Wait up to 3 minutes for a health mark (it read `chat.db` and made one successful HomeChat call).
  7. On failure, restore `previous/`, report `rolled_back`, and record the failed commit so the same one isn't retried nightly. At start, if no app is installed but `previous/` exists, restore it.
  8. Report the result in the next status post.

  Grants survive the swap (§3). Signing from the launchd context is unproven (§9).
- **Out of the loop:** the Homebrew `imsg` binary plays no part. Nothing in the agent, its tests or acceptance runs it. After cutover it can be uninstalled with Alex's yes.
- **CI:** the full suite on every PR and push (no scope filter, which a small repo doesn't need), no secrets, synthetic fixtures only.

### 5.7 Cutover and rollback

- **Order:**
  1. HomeChat ships its changes (§7).
  2. Check that HomeChat holds 0 unfinished sends (true now: every send is refused).
  3. Issue a token for the new device.
  4. Quit the fork app and switch off its Login Item (it stays installed, paused, as the fallback).
  5. Copy the fork's cursor into the new config. Both are the last ROWID scanned (`CompanionReader.swift:10`), so nothing is missed. HomeChat stores messages by `guid` with `INSERT OR IGNORE`, so a cursor a little behind only re-posts rows it ignores. The first-run window is not used. The fork's send ledger isn't copied: it holds 0 records, and HomeChat binds each send to a device.
  6. `setup`, grant permissions, start.
- **Before Stage S:** revoke the fork's token, because HomeChat refuses every send while more than one Mac is linked (`sends.py`: "More than one Mac is linked"). Until then every reply is refused, which is expected through Stage U. From then on, rolling back to the fork needs a fresh fork token (HomeChat runbook).
- **Single uploader:** the agent refuses to uplink while the fork app is running (checked by bundle ID; my call).
- **Rollback:** stop the agent, unpause the fork app; the cursor carries back the same way.
- **After acceptance:** with Alex's yes, remove the fork app's grants (Alex, in System Settings), its Keychain item and its Login Item, and archive the fork repo on GitHub.

### 5.8 Security and privacy

Unchanged from the 2026-11-07 design §6:
- read-only database
- token only in the Keychain
- HTTPS only, no redirects
- no message text in logs, ledger or status
- synthetic fixtures

New since then:
- **Updates:** they install unattended, guarded by tagged releases, a 3-day wait, green CI, our tests and the health check. A bad `imsg` release can still reach the Mac; that is accepted (Alex chose this over a one-tap install). Only `IMsgCore` is linked. The agent never calls its send, launch or bridge code.
- **Remote control is one-way safe** (§5.5).

## 6. Acceptance (on the MacBook)

**Stage U: reading and uplink, sends off.**
- U1: starts from launchd at login and after a crash. The grants show under the agent's own name.
- U2: first run after cutover. The cursor carries over; HomeChat's message count shows no gap and no duplicates.
- U3: a test-contact text is stored in HomeChat within a few seconds.
- U4: a question is flagged and seen on Alex's phone; his reply clears it.
- U5: the fork's open checks 5–8:
  - quit-and-reopen catch-up
  - offline retry
  - SSN scrub on a test text
  - code skip in both cases: a code text in a never-written thread is skipped; one in a thread Alex writes in goes up
- U6: an unsend reaches HomeChat and clears its flag.
- U7: pause and resume from WhatsApp, with a local pause holding against a remote resume; status visible in HomeChat; there is no way to turn sends on from WhatsApp.
- U8: the nightly updater in five cases: no update; an update installs; a forced health-check failure rolls back; HomeChat unreachable leaves the build alone; a send in progress defers the swap.
- U9: Contacts on: an unsaved-number text is not flagged and is counted in the update.

**Stage S: sends on, Alex's typed yes per real send, to test contacts.**
- S0: `preflight` ready on an iMessage 1:1, an `any;+;` group, an SMS 1:1 and an RCS 1:1 if one exists. Automation → Messages shows under the agent.
- S1: an iMessage 1:1 reply received once.
- S2: a reply in an SMS-labelled iMessage group.
- S3: an SMS 1:1 reply with an accent and an emoji.
- S4: a changed-participants refusal.
- S5: an expired approval refused.
- In each case `sent_service` is reported and the ledger holds no text.
- Not covered, so still unproven: true MMS groups and RCS groups, unless a test group of that kind exists.

## 7. HomeChat changes (for `homechat-bot`'s own amendment and PRs)

1. Drop every iMessage assumption: the `iMessage;` GUID gate and the other service checks (`sends.py:47,76,120`). The natural-replies design's `threads[].service` from `chat.service_name`, its "must be iMessage when known" rule and `confirmed_fallback` (its lines 178, 188, 232) are superseded by this design.
2. Accept and store the additive fields in §5.3. Upsert edited/unsent re-posts by `guid`; an unsend clears its flag.
3. Accept unknown `detail` codes (drop the 422 at `send_route.py:66`; `sends.py:203` already shows them as "the Mac refused it"), `sent_service`, and the retired `not_imessage`.
4. Add `POST /imsg/status`, stored per device. Show it in HomeChat's status, and mention staleness in the twice-daily update only.
5. Add `control.paused` to `GET /imsg/sends` (already an object, `{"sends": [...]}`, so this is additive), with WhatsApp commands for pause and resume. Stopping sends is HomeChat refusing to queue; there is never a way to turn sends on.
6. Unsaved senders: still not flagged. The update counts "N texts from unsaved numbers, not checked", and Alex can ask to see them (Alex, 2026-11-14). A null name only counts as unsaved when status says Contacts is granted.
7. The "30 a day" text is hard-coded in `NOT_SENT_REASONS`; keep it in step if either cap becomes a tunable.
8. Unsends: `imsg_messages` uses `INSERT OR IGNORE` on `guid` today, so an unsent re-post needs an update path. Ingest already ignores unknown keys (`ingest.py`), so the new fields are safe before it ships. Deploying HomeChat first still matters for the 422 and the update path.
9. Deploy before the agent's cutover. Issue the new device token, and revoke the fork's before Stage S (§5.7).

## 8. Left to the builder

- Module layout and which lifted files are merged or renamed.
- `NSAppleScript` in-process versus `/usr/bin/osascript` as a child: whichever makes Automation attribute to the agent (prove it in S0).
- Renovate or Dependabot, whichever meets the release-only, 3-day rule for SwiftPM.
- Exact schedule times, file names and the health-mark format.
- Logging (counts and states only).

## 9. Still unproven (each is checked by the stage named)

- Signing from a launchd context: the Apple Development key in the login keychain, used by the updater with no prompt (U8).
- Contacts and Automation prompts for an agent-style app: Contacts through the `setup` launch, Automation through the running launchd agent (U9, S0).
- `IMsgCore` as a versioned SwiftPM dependency at all. `imsg`'s executable target uses `unsafeFlags` (`Package.swift:42-50`), and SwiftPM may refuse that in a versioned dependency even though we link only `IMsgCore`. This is the plan's first task; if it fails, the builder stops and brings it back. Also: building under Xcode 27 with our signing and hardened runtime (first CI run).
- Whether Dependabot bumps `imsg`'s transitive packages separately (with the cooldown) or only alongside an `imsg` bump.
- Group, SMS and RCS rows through `IMsgCore` on real data, and its text decoder's accuracy (U3–U6).
- The identity checks on SMS and RCS chats (S0, S3).
- Late delivery of a green send while the iPhone is offline. It can't be cancelled; it is reported as whatever the read-back shows.

## 10. Where things go

- This design: here now, then the new repo's `docs/specs/`.
- The plan: the new repo, after this design is approved and Fable-reviewed.
- HomeChat's amendment and plan: `homechat-bot`, in its own session.
- The fork: frozen except for cutover notes in its STATUS/LOG. It is archived after acceptance with Alex's yes.

# Log: msgblast-imessage

_The flight recorder: append only, newest at the bottom. Decisions, corrections, dead ends and why. What's true now is in [STATUS.md](STATUS.md). Design decisions stay in the design doc. This repo is public: no names, numbers, hosts or tokens here._

## 2026-11-07 21:25 ET: project set up
- **Why a separate fork:** the companion needs a Mac app with Full Disk Access and Automation, so it is a fork of msgblast rather than part of HomeChat. Alex chose a public fork (GitHub can't make a fork of a public repo private), so personal data never goes in the repo; config stays local and in the Keychain. The whole app is kept so upstream fixes keep merging; our code goes in new files.
- **Forked** from upstream `main` at `8fd9191` with `--default-branch-only`. The fork came with Actions enabled at the repo level. Turning it off from Claude was refused by the auto-mode classifier, so Alex switched it off himself; re-read as `enabled: false` before anything was pushed. Upstream's workflows need its signing secrets and `xcode-27` runners, and its release jobs aren't ours.
- **Remotes:** `upstream` has its push URL disabled, so nothing can be pushed upstream by accident. `gh repo set-default` points at the fork, because `gh pr create` in a fork otherwise targets the parent.
- **Upstream's AGENTS.md:** its process rules (branch prefix, evidence SHAs, video per PR, PR size) are for upstream contributions only. Its safety rules (never mutate the Messages database, uncertain sends are not retried, no real sends for evidence, Linux checks don't prove native builds) were carried into CLAUDE.md.
- **Chat content stays out of dev sessions:** `.claude/settings.json` denies reading the Messages and Contacts stores, and the spikes print only counts and shapes. Read denies don't cover Bash, so CLAUDE.md states the rule too.
- **No standing merge rule:** each PR inside the fork is merged only with Alex's yes for that PR, until he says otherwise.
- **STATUS/LOG instead of a handoff file**, the same flight-deck pattern as HomeChat. The Project Desk link is left out because the repo is public.
- **Agents:** `quality-gate` (Haiku, high) and `send-safety-reviewer` (Sonnet, medium). No ops inspector (nothing runs yet) and no Opus reviewer (no money or deletion here).
- **The design** was copied unchanged from HomeChat's research notes, where Alex approved it at 13:00 ET. A scan found no hostnames, IP addresses, phone numbers, emails or tokens. The background evaluation stays in `homechat-bot`.
- **Clone detail:** the Remember plugin had already written `.remember/` into the empty folder, which blocks `git clone <url> .`. It was moved aside for the one clone command and moved back; it is git-ignored.

## 2026-11-07 21:30 ET: commit identity and folder trust
- **Commit email:** this repo's commits use the GitHub noreply address (local `git config user.email` in this clone only), because a public repo would otherwise publish the personal address in its history. The setup commit was rewritten before its first push, so no commit with the personal address was ever pushed. Set the same local email in the MacBook clone.
- **Folder trust:** the first headless agent runs warned that the project allow rules were ignored. The parent folder is trusted, so no trust prompt appears, but the CLI checks this folder's own flag, which was false. Alex set it; the re-run showed no warning. Lesson: read `claude -p` stderr in live proofs, because 0 denials alone can mean auto mode allowed the command.

## 2026-11-07 21:50 ET: phase 0 plan approved
- Alex approved `docs/superpowers/plans/2026-11-07-phase0-spikes.md`. It runs inline (his standing rule: inline unless he picks subagent-driven).
- Why probes in Python, not Swift: they run in the existing Linux gate against synthetic databases, and they can be read before they ever touch the real `chat.db`. Phase 1 ports the decoder to Swift.
- Why reuse upstream's preview builder for the fork app: it already isolates the bundle ID, the support folder and Sparkle, so no upstream file needs editing. The fork variant uses the blue icon because the builder expects blue-green only for its own `development` variant.

## 2026-11-07 22:10 ET: phase 0 probes built and reviewed
- Tasks 1–7 ran inline on `spikes/phase0`, each test-first. A fresh Opus code review and `send-safety-reviewer` found no Critical issues.
- Fixed before any Mac run: undecodable text in `chat.db` could have put message text or a group name into an error message; a real send could go uncounted if interrupted during `osascript`, or unreported if the 30 s anchor watch failed; an ambiguous send didn't stop a rerun (now a `.local/spikes/send-blocked` marker that only Alex deletes, after checking with the test contacts).
- Kept on purpose: `--tamper` stays a real send attempt, because Task 10 tests that the real send path refuses a changed member set. The 6-send cap counts real sends only; preflights carry no send command.
- Deferred minors: no lock on the send counter (don't run two probes at once); `sync_watch` writes nothing if stopped with Ctrl-C (let it run to `--minutes`); the fork build's temp copy briefly includes `.local/`; a failed re-sign leaves the ad-hoc app in `build/fork-app`; `find_anchor` matches the plain `text` column only, so `anchor_rows 0` means "check by hand", not "not delivered".

## 2026-11-07 22:15 ET: phase 0 code merged
- Alex said go: PR #2 (plan) then PR #3 (probes) merged into `main` locally as merge commits under the noreply identity, as with PR #1.

## 2026-11-07 22:25 ET: fork CI
- Alex asked for CI. Upstream's six workflows stay off (several are release, signing and notarization jobs that expect upstream's secrets); each is switched off by name, so turning Actions back on runs only the fork's own `fork-ci.yml`.
- Why `xcode-27`: it is GitHub's hosted Xcode 27 image (public preview, arm64), the same label upstream uses; the job pins Xcode 27.0 like upstream. The Linux job mirrors the Linux gate; the macOS job runs the Python tests and the native core tests exactly as `docs/testing.md` writes them.
- No secrets, no artifacts, `contents: read`, checkout without persisted credentials, and every job is limited to this repository.

## 2026-11-08 07:55 ET: Task 8 stopped at the Xcode check
- Cloned on the MacBook (it had no copy: the earlier sessions ran on the Linux box). `gh repo clone` added `upstream` by itself, so only the push URL needed disabling; it's `DISABLED` rather than the plan's longer string, same effect.
- Stopped per the plan's Step 1 rule: Xcode 27 is missing. Installing and selecting Xcode needs Alex's Apple ID and password, so it's his step. `/usr/bin/python3` is 3.9.6; the plan's spikes run with it, so check they don't need newer syntax when Task 8 resumes.

## 2026-11-08 08:20 ET: Task 8 Steps 1–2 on the MacBook
- Alex installed Xcode 27.2 and selected it. 27.2 rather than CI's pinned 27.0; the native tests pass on both.
- Gate run in `default` permission mode, not `auto`, so a command outside the allow rules would have shown as a denial rather than being allowed silently. 0 denials and a clean stderr prove the two Mac allow rules match. The agent's counts were cross-checked against the xcresult bundle.

## 2026-11-08 08:45 ET: spikes (a) and (b) on the real database
- Alex ran both in Terminal.app rather than the Claude app's terminal pane, so Full Disk Access went to Terminal only and Claude's tools still can't open `chat.db`. The `.local/` deny also blocks Claude's Bash, so Alex pasted the two counts-only reports; they held only numbers and key names.
- The decoder's 3.3% mismatch on rows with both columns is why the phase 1 recommendation is the system typedstream reader rather than porting the byte scanner. The probe can't say how the rows differ without reading text, which dev sessions don't do.

## 2026-11-08 10:40 ET: phase 1 decoder is NSUnarchiver
- Alex chose the system typedstream reader (`NSUnarchiver` into `NSAttributedString`) over porting the byte scanner. Why: the scanner matched `text` exactly on only 96.7% of rows with both columns, and the system reader is Apple's own format implementation. The Python decoder stays as the oracle for synthetic fixtures; no mismatch-shape probe is needed.

## 2026-11-08 11:05 ET: spike (f awake) and Task 8 done
- 8 events rather than the 3 test texts: `sync_watch` counts every `is_from_me` row, tapbacks included, from any device. That's a bigger sample, not an error. All delays fell inside the 2 s poll, so awake sync is faster than the probe can resolve.
- Plan box ticks for Task 8 are left as they are; STATUS and the results doc are the record.

## 2026-11-08 11:20 ET: standing merge approval
- Alex changed the rule: Claude merges fork PRs itself once their fork CI run is green, instead of asking per PR. It matches his rule for his other repos. Unchanged: nothing goes upstream without his yes, real sends still need their own typed yes, and `homechat-bot` follows its own rules.

## 2026-11-08 13:35 ET: Task 9 build 1
- `codesign` from Claude's shell fails with `errSecInternalComponent` on a new key: the Keychain's allow prompt can't appear for a process with no window. One build from Terminal.app with Always Allow added `codesign` to the key's access list. Later builds should sign from Claude's shell; build 2 is the test of that.
- This commit is the "any docs commit" Task 9 Step 3 asks for, so build 2 has a different source SHA from build 1.

## 2026-11-08 13:40 ET: Task 9 pair redone as build 2 → build 3
- Build 1's `sign_check.py record` left no report in `.local/spikes/`, so `compare` had nothing to pair with. Build 1 was already overwritten, so it couldn't be re-recorded. Build 2's report (recorded on build 2's own screen) becomes the "before", and build 3, from this commit, the "after". The comparison is the same; only the labels move.

## 2026-11-08 13:45 ET: spike (g) passes, Task 9 done
- Self-signed certificate signing keeps the grants: the designated requirement is bundle ID plus certificate, so a new build with a new code hash is still the same app to TCC. No Personal Team or paid account needed.
- `grants_kept` reflects what the app's permission screen showed, as Alex read and typed it; the probe doesn't read the TCC database itself (by design: dev tools don't open it).

## 2026-11-08 14:05 ET: send probe's frontmost check fixed for macOS 27
- c2 reported `frontmost_before/after = unknown`. macOS 27's `lsappinfo info -only name` prints `"Name" ASN:...` instead of `"LSDisplayName"="Name"`, and can quote the bundle ID on a later line, so the old pattern found nothing (or would have matched the bundle ID). The probe now reads the leading quoted name first and falls back to the old form. Test-first; Python gate 175 OK, 1 skipped.
- c2's own focus reading is lost; spike (d) uses c1 and c3, plus Alex's eyes on c2. The send path and its checks are unchanged.

## 2026-11-08 14:10 ET: spikes (c) and (d), Task 10 done
- Alex typed his yes in chat and ran each send himself in Terminal.app; Claude never sent. Recipients were his own choice of real contacts (a 1:1 and a two-person group); their names and numbers are only in the git-ignored local config, never in the repo.
- Two runs stopped at the `SEND` prompt before c1 (not typed exactly); the counter proved nothing was submitted, so retrying was safe.
- c2 ran before the frontmost fix, so its focus reading is lost; the verdict rests on c1, c3 and c4. c3 is the strongest case: Messages wasn't running, the send launched it, and Terminal stayed in front.
- 3 of the 6 phase 0 sends are used; the rest stay unused unless a later spike needs them.

## 2026-11-08 16:30 ET: spike (e) preliminary
- Probed the bot hostname, not the connector hostname: the connector only admits Anthropic by design, and the Mac's uplink would go to the bot. The hostname lives only in the git-ignored local config; it's named in `homechat-bot`'s own docs, not here.
- A 404 through Cloudflare with no Access redirect means the edge isn't the obstacle; the route is. That points the uplink at a token-authenticated Caddy route rather than an Access service token, pending a real POST.

## 2026-11-08 17:30 ET: spike (f asleep), phase 0 spikes done
- Messages reach the Mac during sleep: background wakes picked each send up within seconds, so the lid doesn't gate sync. The 24 h nudge stays as the spec has it, for an offline Mac; no spec change.
- Phase 0 ends with one open item, spike (e)'s full test, which needs a probe route built in `homechat-bot` under its rules. The six phase 1 decisions are tabled in the results doc.
- Terminal kept Full Disk Access and Automation only for the spikes; Alex revokes both now (plan Task 11 Step 4).

## 2026-11-08 17:40 ET: phase 1 Mac plan drafted
- `docs/superpowers/plans/2026-11-08-phase1-mac-read-and-uplink.md`, 10 tasks: contract, models, decoder, reader, scrubber, config/token/client, service, Contacts names, status section, acceptance runbook. No sending.
- `NSUnarchiver` raises Objective-C exceptions on corrupt input and the project has no Objective-C to catch them, so a structural pre-check (the spike's scanner rules) gates every call. The residual risk is a structurally valid but internally corrupt blob.
- Contract deviations from the spec's sketch: attachments are a count, not names; verification-code and short-code messages go up as `kind: skipped` with no text, so codes never leave the Mac.
- HomeChat's half starts in `homechat-bot` (4b is live, pre-approved 2026-11-07) against the contract, under that repo's rules.
- Hygiene slip, caught before merge: the first plan commit (PR #10, closed unmerged) wrote a private domain name into a grep pattern. The plan was rebuilt on a fresh branch (PR #11) so `main`'s history never holds it. Scans now look for `https?://` instead of naming the domain. The old branch and PR #10 still hold that commit on GitHub; deleting the branch is Alex's call.

## 2026-11-08 19:00 ET: phase 1 Mac side built (plan Tasks 1–10)
- Executed inline on `phase1/mac-read-uplink`, test-first per task; every ruling is in the plan ledger (git-ignored) and in the PR description.
- Shape: `CompanionReader` (read-only, every chat, groups included) → `CompanionScrubber` → `CompanionService` (one cycle per tick: 3-day first run, batches of 200, cursor saved only on HomeChat's ack, 5 s→300 s backoff, 401/4xx stop until the address or token changes) → `UplinkClient` (HTTPS only, no redirects). A Settings section shows it; a 2 s controller drives it and does nothing until an address and token are saved.
- The token is a login-keychain item, not the data-protection keychain upstream's Grok Bot uses: the self-signed fork has no keychain-access-groups entitlement. Its round-trip in the signed app is unproven until acceptance.
- Three automated security-review findings were real and fixed test-first: scrubber patterns widened (dotted and non-ASCII-digit SSNs, split 6-digit codes, PIN); actor reentrancy (a pause during a post was overwritten, and overlapping ticks could post twice); Contacts phone matching now requires equal country codes when both sides have one. Declined: alphanumeric-only codes and "login/security" keywords, which would also hide ordinary messages from people.
- The Settings section wasn't checked visually: computer-use access to the app was declined. It is check 0 of the acceptance runbook.
- Slip: installing the build replaced the app bundle while an old copy was running; it was then quit normally and the new build opened. Next time, quit first.

## 2026-11-08 20:10 ET: phase 1 Mac side merged; acceptance check 0 passed
- PR #12 merged as `5fa56be` after a green PR run and a green `main` run. The final review (send-safety-reviewer on Sonnet, per the model rules) found 0 Critical and 2 Important. Both were fixed test-first: a corrupt `attributedBody` could crash every launch (a decode marker now poisons only that row), and a long-text backlog went over the 1 MB body limit (batches now halve to fit). A promoted Minor was also fixed: fresh chat-less rows hold the cursor for 10 s. The deferred minors are in the PR description.
- Alex ran check 0 himself, since computer-use access was declined. The section shows, Paused survives a relaunch, and Full Disk Access is Allowed. The installed build (`12d78dc`) predates the review fixes; rebuild before checks 1–8.

## 2026-11-09 21:30 ET: uplink live end to end; acceptance checks 1–4 passed
- HomeChat's uplink (PR A in `homechat-bot`) was deployed from the EliteBook, with only the uplink switch on; the flagger and desk stay off. The Mac's token was issued from the Mac's Terminal straight to the clipboard, so it never appeared on screen or in a session.
- Rebuilt the app from `main` (`2bcc8ad`, with the PR #12 review fixes) and installed it after quitting the old copy; the old copy is kept outside the repo for rollback.
- Checks 1–4 passed against counts-only, read-only readbacks of HomeChat's store. Alex chose to move on before checks 5–8, so restart catch-up, offline retry and the scrubber on real data stay unproven at runtime (unit tests cover them on synthetic data).
- The token didn't save on the first tries: Save with an empty token field keeps "no token" without an error, which hid what went wrong. Queued as a small app fix.
- Next is HomeChat's flagger (PR B), from the EliteBook.

## 2026-11-10 20:25 ET: reader hardening from other chat.db readers (PR #17)
- Compared the companion with `anipottsbuilds/imessage-mcp` (21 releases), its fork `jaredzimmerman/iMessageMCP` (adds sending), the other forks, and other send code (Prpking, daveremy, JonathanRReed, BlueBubbles). We took ideas only. None of them replaces the fork: phase 1 is already live, and sending already works through msgblast.
- Four Mac-only fixes for silent stops: reopen on a replaced chat.db, a visible stop on a reset, system rows passed over, and a 4 MiB decode cap. The reset check uses `sqlite_sequence`, so deleting the newest messages doesn't trigger it. A review finding narrowed the system-row skip to rows with no text, body or attachments.
- Left for HomeChat (contract changes): edits and unsends, a sibling SMS/iMessage chat, a failed outgoing row clearing a flag, and recovery after a reset.
- Phase 3 send notes written as plan input. Main points: pass the text as an argument, not script source; keep a pre-dispatch send record on the Mac; take a ROWID baseline and read the `error`/`is_sent` read-back; a real hash binding to the approved text.

## 2026-11-10 20:55 ET: PRs #16–#18 merged; faster Mac CI
- The Mac job was about 3 minutes of build and about 18 of tests, mostly upstream's timer-bound driver tests. So the speed-up skips or narrows the tests rather than caching the build.
- What it does: `scripts/ci_native_scope.py` decides the scope per PR. The full suite now runs with `-parallel-testing-enabled`.
- One green parallel trial (12m43s): flakiness isn't ruled out yet. If a full-suite run fails in a way that doesn't repeat, take parallel out and keep the scoping.
- Alex approved the new gate rule (CLAUDE.md): a red full-suite run on `main` after a merge stops further merges until it's fixed forward.

## 2026-11-10 22:15 ET: reader hardening installed; checks 5–8 deferred
- The pre-install checks came back clean: the real `message` table uses AUTOINCREMENT, so the reset stop can't fire when the newest messages are deleted. No row with a non-zero `item_type` has a body, so the system-row skip can't drop an ordinary message.
- The first query attempt failed with "authorization denied": it ran from a shell without Full Disk Access, not Terminal.app. Nothing was read.
- Built with `companion/build_fork_app.py` into its own folder and checked that the designated requirement matched before installing, so the grants carried over. The old copy was moved aside, not deleted.
- Alex chose not to run checks 5–8 tonight (no test contact free). They stay recorded as not run, not as passed.

## 2026-11-11 20:50 ET: Settings Save no longer hides a missing token
- The fix for the first-save confusion on 2026-11-09. Save with an empty token field and no token saved now keeps the address and says a token is still needed. After a token write, the token is read back; a write that reports success but can't be read back says so.
- The save logic moved from the app's `CompanionController` into Core, so unit tests can reach it with a fake token store. A Keychain write failure now still updates the shown host, since the address was already saved.
- Not proven: why the first save on 2026-11-09 failed. This makes such a failure visible; it doesn't explain it.

## 2026-11-11 21:20 ET: phase 3 Mac plan approved
- Plan: `docs/superpowers/plans/2026-11-11-phase3-mac-approved-replies.md`, 10 tasks, Mac side only. It fixes the two send routes in the uplink contract (Task 1); HomeChat builds its half against that.
- Alex's answers to the send-notes questions: a send left `in_progress` by a crash resolves to `sent` only on exactly one exact matching row after the baseline with `error` = 0 and `is_sent` = 1, otherwise `ambiguous`; read-back waits 20 s; the Mac's audit keeps hash and length only; iMessage 1:1 and group threads. Not asked, defaulted: `sent` is enough, `is_delivered` isn't read.
- Choices made in the plan: a `send_id` with any ledger record is never dispatched again; sends are off until a new Settings switch is turned on; the AppleScript is fixed and takes everything as `argv`; recovery after a crash never reports `not_sent`.
- Execution: inline, per Alex's default; send-safety-reviewer on the whole branch before merge.

# Status: msgblast-imessage

**Updated:** 2026-11-10 20:55 ET
**At:** The Mac uplinks to the live HomeChat (build `2bcc8ad`); acceptance checks 1–4 passed at the Mac; checks 5–8 not run (Alex chose to move on).
**Next:** HomeChat PR C (twice-daily update, date nudge, replies), open in `homechat-bot` and run from the EliteBook under that repo's rules; this repo waits on it.
**Phase:** Phase 1 Read and flag: uplink live end to end (Mac → HomeChat store); HomeChat's flagger live (PR B); update (PR C) in review; desk items (PR D) not built.
**Milestones:** Setup ✓ · Spikes ✓ (one follow-up) · Read and flag (now: uplink live) · Calendar · Replies · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — done (spike (e) full test waits on `homechat-bot`)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — now (uplink and flagger live; update in review; desk next)
- 2 Calendar — free or clash for texted dates, add on yes — next
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — next
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Fork CI (`fork-ci.yml`): runs on PRs and pushes to `main`.
- "msgblast iMessage.app" (build `2bcc8ad`, installed 2026-11-09 19:44 ET; the previous copy is kept outside the repo for rollback) on the MacBook, address and token saved, uplinking new messages to HomeChat within seconds.

## QUEUED
- Reader hardening (merged, PR #17) is not installed: at the MacBook, run the plan's counts-only pre-install checks (AUTOINCREMENT on `message`, `item_type` counts) and the native gate, then rebuild and reinstall (quit the app first).
- Phase 3 plan: start from `docs/superpowers/specs/2026-11-10-phase3-send-notes.md` (what to borrow from other send implementations, what to avoid, five questions for Alex).
- `homechat-bot` PR C (twice-daily update and replies, open as homechat-bot#231) and PR D (`txt-` desk items, not started), per its plan `docs/superpowers/plans/2026-11-08-imsg-phase1-plan.md`, under that repo's rules (spec §9).
- Mac acceptance checks 5–8 (quit-and-reopen catch-up, offline retry, SSN scrub, code skip): not run; worth running now the flagger is live, so the same test texts can also check flags and auto-clear.
- Small app fix: Save with an empty token field silently keeps "no token" and shows no error; it should say a token is still needed.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- None. Terminal keeps Full Disk Access and Automation → Messages for now, by Alex's choice (2026-11-09), in case a Terminal step is needed again.

## DONE
- 2026-11-10: PR #17 merged (`651f054`): reader hardening (reopen on a replaced chat.db, a visible reset stop using `sqlite_sequence`, system rows passed over, 4 MiB decode cap) plus phase 3 send notes; green full native suite on the PR. PR #18 merged (`a1ee574`): fork CI scopes the Mac job (none for docs/`.claude`-only PRs, the companion suites for companion-only PRs, the full suite otherwise and on `main`) and runs it in parallel (trial: test step 12m43s vs 20m53s, green). PR #16 merged (`411c626`): agent turn caps raised. The `main` run on `a1ee574` covers all three. Not installed on the Mac.
- 2026-11-10: HomeChat PR B (flagger, scrubber, auto-clear, per-kind spend) merged in `homechat-bot` (homechat-bot#227) and recorded there as live (homechat-bot#228). Not checked from this repo: a flag raised by a real text, seen on Alex's phone, or cleared by his reply.
- 2026-11-09: stale branch `plan/phase1-mac` deleted by Alex (local and GitHub). Its commit with the private domain name stays reachable through closed PR #10 on GitHub.
- 2026-11-08: phase 1 Mac plan Tasks 1–10 on `phase1/mac-read-uplink`: contract, wire models, `attributedBody` decoder, group-aware reader, scrubber, config/Keychain token/uplink client, companion service, Contacts names, Settings section and app wiring, acceptance runbook. Three automated security-review findings fixed test-first (scrubber patterns, actor reentrancy, phone country codes). Rulings in the plan ledger, summarised in LOG.
- 2026-11-08: phase 0 Tasks 8–11 on the MacBook (PRs #5–#9) and the phase 1 Mac plan (PR #11), all merged with green CI.
- 2026-11-07: phase 0 Tasks 1–7 on `spikes/phase0` (`ee7c52b..` 8 commits, incl. one final-review fix pass): probe library and synthetic fixture, spikes (a), (b), (c)/(d), (e), (f), (g), and `companion/build_fork_app.py`. Final review: 0 Critical; 4 Important fixed with tests; 5 minors deferred (LOG 22:10).
- 2026-11-07: forked upstream at `8fd9191` (public, `main` only, Actions disabled); added CLAUDE.md, `.claude/` (settings, agents, STATUS, LOG), FORK.md, `.gitignore` entries and the approved design.

## EVIDENCE
- Acceptance checks 1–4 at the Mac (2026-11-09 21:15–21:25 ET, build `2bcc8ad`, counts-only readback of HomeChat's store run by Alex, read-only): (1) status went to up to date; (2) first run stored 26 threads (6 groups) and 255 messages, oldest 3.0 days, none older, 0 skipped rows with text; (3) a test-contact text was stored 2.2 s after it was sent; (4) with Paused on nothing went up and Paused survived a relaunch (Alex's reading); after unpausing the held text was stored once (sent-to-stored 48.5 s). Not run: checks 5–8. Not checked: the runbook's "count roughly matches the Mac's 3-day count". Scrubbing (SSN, codes) is proven only by unit tests on synthetic data; 10 real messages went up as `skipped` with no text, but none was checked against a known code text.
- HomeChat uplink live (2026-11-09 19:10 ET, `homechat-bot` PR #208 deployed with only the uplink switched on; recorded in that repo). The Mac's device token was issued from the Mac's Terminal and lives only in the login keychain (item present, value never shown). The first Save stored only the address; the cause wasn't pinned down; re-entering the address and pasting the token again worked.
- Acceptance check 0 at the Mac (2026-11-08 20:04–20:06 ET, build `12d78dc`, read by Alex): the companion section shows in Settings ("No uplink yet this session"); Paused stayed on across a quit and relaunch (companion.json saved mode 0600, app restarted 20:04:39); Full Disk Access reads Allowed. The status line's exact words weren't reported. The build predates the review fixes in `5fa56be`.
- PR #12 merged 2026-11-08 (`5fa56be`): PR run 42539220785 and `main` run 42541211665 both green (linux and native on GitHub's `xcode-27`). The Mac gate at `c498bcd` was 944 native tests, 0 failures, and Python 175 OK.
- Phase 1 Mac gate on the MacBook (2026-11-08 18:40–18:51 ET, `12d78dc`): Python script tests 175 OK, 1 skipped; native tests 941 executed, 1 skipped, 0 failures, TEST SUCCEEDED (was 872; 69 new companion tests, all on synthetic `chat.db` fixtures). Signed build of `12d78dc` passes `codesign` validation and its designated requirement, and is installed in `/Applications`, running. Not proven: Keychain token round-trip in the signed app, any read of the real `chat.db` by the app, any post to HomeChat.
- Spike (f asleep) on the MacBook (2026-11-08 16:50–17:10 ET, 20 min, lid closed): 7 sleep gaps; 4 sends, each seen 1.8–5.5 s after sending and 0–12 s after a wake.
- Spike (e) preliminary on the MacBook (2026-11-08 16:27 ET, `reach.py`): bot hostname root answered 404 through Cloudflare in 169 ms, `access_redirect=false`. Not a real route; the full test needs the `homechat-bot` probe route.
- Spikes (c), (d) on the MacBook (2026-11-08 13:57–14:06 ET, Alex's typed yes, Terminal.app): c1 1:1 sent once (0.6 s); c2 group sent once (0.5 s, arrival confirmed); c3 group with Messages quit sent once (2.6 s, Messages launched in the background); c4 tampered refused with 9004. Alex confirmed c1–c3 arrived. Terminal frontmost before and after c1, c3, c4; c2's focus reading was lost to the macOS 27 `lsappinfo` bug, fixed in PR #7. 3 of 6 sends used.
- Spike (g) on the MacBook (2026-11-08 13:40 ET): build 2 (`70ec3c7`) → build 3 (`144610b`), reinstalled over the old copy: `same_requirement=true`, `grants_kept=true` (grants as read by Alex on the app's screen); code hash changed. Build 2 signed from Claude's shell with no prompt.
- Task 9 build 1 (2026-11-08 13:11 ET, `main` `76dc5fa`): signed with the self-signed local identity, `codesign --verify --deep --strict` passes in `/Applications`; designated requirement is bundle ID plus certificate leaf (no cdhash); Sparkle feed and key are empty in Info.plist (runtime unverified). The first re-sign failed with `errSecInternalComponent` because Claude's process can't show the key-access prompt; Alex ran the build once in Terminal.app and chose Always Allow.
- Spike (f awake) on the MacBook (2026-11-08, 10 min, 2 s polls): 8 sends seen, all within one poll (median 0.6 s, max 1.6 s), iMessage only, 0 sleeps.
- Spikes (a), (b) on the MacBook (2026-11-08 08:33 ET, Terminal.app with Full Disk Access, 14-day window, counts-only reports pasted by Alex; Claude's tools are denied `.local/`): (a) 3.3% of bodies `attributedBody`-only, all decoded; rows with both match exactly 96.7%. (b) 100% of inbound group messages have a sender; 0 style mismatches; 11% of active groups named.
- MacBook clone (2026-11-08 07:50 ET): `main` at `1db674d`, level with `origin`; `upstream` push disabled; local `user.email` set to the noreply address; `gh` default repo is the fork. Versions: macOS 27.2, `arm64`, `/usr/bin/python3` 3.9.6, Xcode 27.2 (27B52), Swift 6.4.2, macOS SDK 27.2, selected at 08:01 ET (first-launch status OK).
- MacBook gate (2026-11-08 08:03–08:15 ET, headless `claude -p --agent quality-gate --permission-mode default`, Haiku): pass, 2 turns, 0 permission denials, no trust warning on stderr, so the Mac allow rules match. Python script tests 174 OK, 1 skipped. Native core tests: xcresult says Passed, 872 total, 871 passed, 1 skipped, 0 failed (~12 min, first build). Still unproven on the Mac: TCC, signing, the fork app build and anything touching the real `chat.db`.
- Linux gate at setup (2026-11-07, Python 3.12.3): 121 script tests, OK, 2 skipped (one needs `installer-requirements.txt`, one needs macOS clang/lipo).
- Linux gate after the review fixes (2026-11-07 22:10 ET): 174 tests, OK, 2 skipped. Fixture-only: no probe has touched a real `chat.db`, Messages, HomeChat or `codesign`.
- First fork CI run (2026-11-08 03:17–03:37 UTC, run 42442049686, PR #4 head `24aa5f7`): linux pass (Python tests OK, 2 skipped); native pass on GitHub `xcode-27`, Xcode 27.0 (27A266a): Python tests OK (1 skipped), native core tests 872 executed, 1 skipped, 0 failures, TEST SUCCEEDED. Upstream's six workflows stayed off. This is GitHub's VM, not the MacBook: TCC, signing and the real app are still unproven.
- Agent live proof (headless `claude -p`, 2026-11-07): `quality-gate` on Haiku 5.5 ran the Linux gate (pass, 2 turns); `send-safety-reviewer` on Sonnet 5.5 reviewed the setup files (pass, no findings, 5 turns). 0 permission denials each. The first runs ignored the project allow rules (folder untrusted); after Alex set the trust flag, `quality-gate` re-ran with no trust warning and 0 denials, so the Linux allow rule matches. The Mac allow rule was proven on 2026-11-08 (see the MacBook gate line).
- Not proven yet: msgblast on current macOS beyond tests, the `NSUnarchiver` decoder on real blobs (proven only on `NSArchiver` output), sends from the fork app itself (not `osascript`), SMS sends, overnight sleep and Low Power Mode sync, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them (fork PRs merge on green CI without asking, since 2026-11-08): never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Plans: `docs/superpowers/plans/` (phase 1 Mac: `2026-11-08-phase1-mac-read-and-uplink.md`). Uplink contract: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`. Acceptance: `docs/superpowers/runbooks/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

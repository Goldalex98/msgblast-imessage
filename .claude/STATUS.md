# Status: msgblast-imessage

**Updated:** 2026-11-08 14:10 ET
**At:** Task 10 done: spikes (c) and (d) pass. 1:1 and group sends landed once each, a tampered member set was refused (9004), and Messages never took focus.
**Next:** Task 11: spike (e) reach (needs `homechat_probe_url` in the local config) and spike (f) asleep (lid-closed sync run), then the phase 0 wrap-up.
**Phase:** Phase 0 spikes: plan approved (PR on `plan/phase0-spikes`), Tasks 1–7 merged to `main` (PRs #2, #3); Tasks 8–10 done on the MacBook; Task 11 next.
**Milestones:** Setup ✓ · Spikes (now) · Read and flag · Calendar · Replies · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — now (probes built, Mac runs next)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — next
- 2 Calendar — free or clash for texted dates, add on yes — next
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — next
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Fork CI (`fork-ci.yml`, PR #4): runs on PRs and pushes to `main`. Nothing else runs: no app build, no uplink, no HomeChat routes.

## QUEUED
- MacBook, Task 11: reach (`reach.py`, needs the HomeChat probe URL in the local config) and the asleep sync run. Claude reads only the counts-only reports.
- HomeChat's half is built in `homechat-bot`, not here. Spike (e)'s full test needs a probe route there.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- His re-review of the design.
- A MacBook session for Tasks 8–11, and a yes typed in chat before Task 10's real sends.

## DONE
- 2026-11-07: phase 0 Tasks 1–7 on `spikes/phase0` (`ee7c52b..` 8 commits, incl. one final-review fix pass): probe library and synthetic fixture, spikes (a), (b), (c)/(d), (e), (f), (g), and `companion/build_fork_app.py`. Final review: 0 Critical; 4 Important fixed with tests; 5 minors deferred (LOG 22:10).
- 2026-11-07: forked upstream at `8fd9191` (public, `main` only, Actions disabled); added CLAUDE.md, `.claude/` (settings, agents, STATUS, LOG), FORK.md, `.gitignore` entries and the approved design.

## EVIDENCE
- Spikes (c), (d) on the MacBook (2026-11-08 13:57–14:06 ET, Alex's typed yes, Terminal.app): c1 1:1 sent once (0.6 s); c2 group sent once (0.5 s, arrival confirmed); c3 group with Messages quit sent once (2.6 s, Messages launched in the background); c4 tampered refused with 9004. Terminal frontmost before and after c1, c3, c4; c2's focus reading was lost to the macOS 27 `lsappinfo` bug, fixed in PR #7. 3 of 6 sends used.
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
- Not proven yet: msgblast on current macOS, the Swift `NSUnarchiver` decoder, sends from the fork app itself (not `osascript`), SMS sends, iPhone-to-Mac sync delay while asleep, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them (fork PRs merge on green CI without asking, since 2026-11-08): never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Build plan (when written): `docs/superpowers/plans/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

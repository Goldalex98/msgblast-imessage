# Status: msgblast-imessage

**Updated:** 2026-11-08 11:05 ET
**At:** Task 8 done on the MacBook: spikes (a), (b) and (f awake) ran and their verdicts are in `docs/superpowers/spikes/2026-11-phase0-results.md`; decoder decision NSUnarchiver.
**Next:** PR Task 8's records (branch `spikes/mac-task8`), then Task 9: permission grants across rebuilds.
**Phase:** Phase 0 spikes: plan approved (PR on `plan/phase0-spikes`), Tasks 1–7 merged to `main` (PRs #2, #3); Task 8 done on the MacBook (not yet merged); Tasks 9–11 next.
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
- MacBook, Tasks 8–11: clone the fork, check macOS, Xcode 27 and Apple silicon, then make the self-signed signing certificate. Alex then runs the probes and the real sends (only with his yes), and Claude reads only the counts-only reports.
- HomeChat's half is built in `homechat-bot`, not here. Spike (e)'s full test needs a probe route there.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- A yes to commit, push and PR `spikes/mac-task8` (STATUS, LOG, results doc), and a yes to merge it.
- His re-review of the design.
- A MacBook session for Tasks 8–11, and a yes typed in chat before Task 10's real sends.

## DONE
- 2026-11-07: phase 0 Tasks 1–7 on `spikes/phase0` (`ee7c52b..` 8 commits, incl. one final-review fix pass): probe library and synthetic fixture, spikes (a), (b), (c)/(d), (e), (f), (g), and `companion/build_fork_app.py`. Final review: 0 Critical; 4 Important fixed with tests; 5 minors deferred (LOG 22:10).
- 2026-11-07: forked upstream at `8fd9191` (public, `main` only, Actions disabled); added CLAUDE.md, `.claude/` (settings, agents, STATUS, LOG), FORK.md, `.gitignore` entries and the approved design.

## EVIDENCE
- Spike (f awake) on the MacBook (2026-11-08, 10 min, 2 s polls): 8 sends seen, all within one poll (median 0.6 s, max 1.6 s), iMessage only, 0 sleeps.
- Spikes (a), (b) on the MacBook (2026-11-08 08:33 ET, Terminal.app with Full Disk Access, 14-day window, counts-only reports pasted by Alex; Claude's tools are denied `.local/`): (a) 3.3% of bodies `attributedBody`-only, all decoded; rows with both match exactly 96.7%. (b) 100% of inbound group messages have a sender; 0 style mismatches; 11% of active groups named.
- MacBook clone (2026-11-08 07:50 ET): `main` at `1db674d`, level with `origin`; `upstream` push disabled; local `user.email` set to the noreply address; `gh` default repo is the fork. Versions: macOS 27.2, `arm64`, `/usr/bin/python3` 3.9.6, Xcode 27.2 (27B52), Swift 6.4.2, macOS SDK 27.2, selected at 08:01 ET (first-launch status OK).
- MacBook gate (2026-11-08 08:03–08:15 ET, headless `claude -p --agent quality-gate --permission-mode default`, Haiku): pass, 2 turns, 0 permission denials, no trust warning on stderr, so the Mac allow rules match. Python script tests 174 OK, 1 skipped. Native core tests: xcresult says Passed, 872 total, 871 passed, 1 skipped, 0 failed (~12 min, first build). Still unproven on the Mac: TCC, signing, the fork app build and anything touching the real `chat.db`.
- Linux gate at setup (2026-11-07, Python 3.12.3): 121 script tests, OK, 2 skipped (one needs `installer-requirements.txt`, one needs macOS clang/lipo).
- Linux gate after the review fixes (2026-11-07 22:10 ET): 174 tests, OK, 2 skipped. Fixture-only: no probe has touched a real `chat.db`, Messages, HomeChat or `codesign`.
- First fork CI run (2026-11-08 03:17–03:37 UTC, run 42442049686, PR #4 head `24aa5f7`): linux pass (Python tests OK, 2 skipped); native pass on GitHub `xcode-27`, Xcode 27.0 (27A266a): Python tests OK (1 skipped), native core tests 872 executed, 1 skipped, 0 failures, TEST SUCCEEDED. Upstream's six workflows stayed off. This is GitHub's VM, not the MacBook: TCC, signing and the real app are still unproven.
- Agent live proof (headless `claude -p`, 2026-11-07): `quality-gate` on Haiku 5.5 ran the Linux gate (pass, 2 turns); `send-safety-reviewer` on Sonnet 5.5 reviewed the setup files (pass, no findings, 5 turns). 0 permission denials each. The first runs ignored the project allow rules (folder untrusted); after Alex set the trust flag, `quality-gate` re-ran with no trust warning and 0 denials, so the Linux allow rule matches. The Mac allow rule was proven on 2026-11-08 (see the MacBook gate line).
- Not proven yet: signing and the fork app on the Mac, msgblast on current macOS, the Swift `NSUnarchiver` decoder, group send, whether a send raises Messages, iPhone-to-Mac sync delay while asleep, permission grants across rebuilds, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them: never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Build plan (when written): `docs/superpowers/plans/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

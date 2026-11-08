# Status: msgblast-imessage

**Updated:** 2026-11-07 22:25 ET
**At:** The test probes and the fork app builder are merged; they pass on the Linux box but haven't run on the Mac.
**Next:** On the MacBook with you: clone, build the fork app, then run the probes and the few test sends.
**Phase:** Phase 0 spikes: plan approved (PR on `plan/phase0-spikes`), Tasks 1–7 merged to `main` (PRs #2, #3); Tasks 8–11 need the MacBook.
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
- Fork CI (`fork-ci.yml`) being added on `ci/fork-ci`: Linux gate + native core tests on GitHub's `xcode-27` runner. Nothing else runs: no app build, no uplink, no HomeChat routes.

## QUEUED
- MacBook, Tasks 8–11: clone the fork, check macOS, Xcode 27 and Apple silicon, then make the self-signed signing certificate. Alex then runs the probes and the real sends (only with his yes), and Claude reads only the counts-only reports.
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
- Linux gate at setup (2026-11-07, Python 3.12.3): 121 script tests, OK, 2 skipped (one needs `installer-requirements.txt`, one needs macOS clang/lipo).
- Linux gate after the review fixes (2026-11-07 22:10 ET): 174 tests, OK, 2 skipped. Fixture-only: no probe has touched a real `chat.db`, Messages, HomeChat or `codesign`.
- Agent live proof (headless `claude -p`, 2026-11-07): `quality-gate` on Haiku 5.5 ran the Linux gate (pass, 2 turns); `send-safety-reviewer` on Sonnet 5.5 reviewed the setup files (pass, no findings, 5 turns). 0 permission denials each. The first runs ignored the project allow rules (folder untrusted); after Alex set the trust flag, `quality-gate` re-ran with no trust warning and 0 denials, so the Linux allow rule matches. The Mac allow rule is unproven until it runs there.
- Not proven yet: anything on the Mac (Xcode 27, native tests, signing), msgblast on current macOS, `attributedBody`-only bodies, group read and send, whether a send raises Messages, iPhone-to-Mac sync delay, permission grants across rebuilds, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them: never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Build plan (when written): `docs/superpowers/plans/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

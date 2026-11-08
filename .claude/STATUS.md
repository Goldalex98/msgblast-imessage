# Status: msgblast-imessage

**Updated:** 2026-11-07 21:25 ET
**At:** The fork is set up with its rules, agents and the approved design. No app code yet.
**Next:** Write the build plan, then run the phase 0 tests on the MacBook.
**Phase:** Setup done on the Linux box; the build plan is next, with the phase 0 spikes first.
**Milestones:** Setup ✓ · Spikes (now) · Read and flag · Calendar · Replies · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — now (build plan next)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — next
- 2 Calendar — free or clash for texted dates, add on yes — next
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — next
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Nothing runs yet: no app build, no uplink, no HomeChat routes.

## QUEUED
- Build plan with `superpowers:writing-plans` from the design, phase 0 spikes (a)–(g) first. Alex re-reviews the design meanwhile.
- MacBook: clone the fork, check macOS and Xcode 27, make the self-signed Keychain code-signing certificate, run the spikes.
- HomeChat's half waits until HomeChat's phase 4b is live; it is built in `homechat-bot`, not here.

## BLOCKED
- Project allow rules don't load on the Linux box yet: the CLI reports this folder as untrusted (its own `hasTrustDialogAccepted` is false, even though a parent folder is trusted, so no prompt appears). Gate commands still run through auto mode. Unblocked when Alex sets the flag; then re-run `quality-gate` and check the warning is gone.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- His re-review of the design while the build plan is written.

## DONE
- 2026-11-07: forked upstream at `8fd9191` (public, `main` only, Actions disabled); added CLAUDE.md, `.claude/` (settings, agents, STATUS, LOG), FORK.md, `.gitignore` entries and the approved design.

## EVIDENCE
- Linux gate at setup (2026-11-07, Python 3.12.3): 121 script tests, OK, 2 skipped (one needs `installer-requirements.txt`, one needs macOS clang/lipo).
- Agent live proof (headless `claude -p`, 2026-11-07): `quality-gate` on Haiku 5.5 ran the Linux gate (pass, 2 turns); `send-safety-reviewer` on Sonnet 5.5 reviewed the setup files (pass, no findings, 5 turns). 0 permission denials each, but the project allow rules were ignored (folder untrusted), so their exact-match is unproven.
- Not proven yet: anything on the Mac (Xcode 27, native tests, signing), msgblast on current macOS, `attributedBody`-only bodies, group read and send, whether a send raises Messages, iPhone-to-Mac sync delay, permission grants across rebuilds, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them: never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Build plan (when written): `docs/superpowers/plans/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

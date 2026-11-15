# Status: msgblast-imessage

**Updated:** 2026-11-15 08:45 ET
**At:** Alex approved the standalone-agent design (2026-11-15, `docs/superpowers/specs/2026-11-14-imsg-standalone-agent-design.md`; Fable-reviewed, sound with changes, folded in). Nothing built or sent.
**Next:** Alex reviews the agent plan (`docs/superpowers/plans/2026-11-15-imsg-standalone-agent.md`, Fable-reviewed, sound with changes, folded in) and picks how it runs. Its Task 1 proves `IMsgCore` 0.21.0 as a pinned SwiftPM dependency despite `unsafeFlags` and stops if it fails. HomeChat's half (design §7) goes to `homechat-bot`'s own session and PRs.
**Phase:** Phase 3 Replies: standalone agent designed, plan next; the natural-replies Mac plan is superseded (not built). Mac switch off; HomeChat still refuses every send (`iMessage;` gate). Phase 1 left open: checks 5–8 and desk items (PR D).
**Milestones:** Setup ✓ · Spikes ✓ · Read and flag · Calendar · Replies (now) · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — done (spike (e) full test waits on `homechat-bot`)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — next (uplink, flagger and update live; checks 5–8 and desk items left)
- 2 Calendar — free or clash for texted dates, add on yes — next (HomeChat-only; code in homechat-bot#305, switch off; deploy and acceptance wait on Alex)
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — now (pivot to a standalone agent on `IMsgCore` in a new repo: design approved, plan next; Mac switch off)
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Fork CI (`fork-ci.yml`): runs on PRs and pushes to `main`.
- `imsg` 0.21.0 on the MacBook (Homebrew `steipete/tap/imsg`, only that formula trusted, `brew pin`ned; Developer ID signed and notarized). Installed for the trial; nothing runs it.
- "msgblast iMessage.app" on the MacBook: the phase 3 build, Apple Development signed, installed 2026-11-12 evening (see DONE); "Send approved replies" turned off again 2026-11-14 ~14:00 ET (quit, edit, reopen). Uplink and the flagger proven working 2026-11-14 (a test text was flagged and nudged). Rollback copies: `build/rollback-20261112*/`.

## QUEUED
- Phase 2 Calendar acceptance (`docs/superpowers/runbooks/phase2-calendar-acceptance.md`): after Alex's yes to deploy HomeChat with its calendar switch on, a test contact's dated text, `N add` by Alex, the event seen in Calendar on his phone. No Mac build.
- Standalone agent: implementation plan, one Fable plan review, then build in the new repo `Goldalex98/imsg-companion` (not created yet). The 2026-11-14 natural-replies Mac plan is superseded.
- HomeChat's half of the agent design (§7: new fields, unsend update path, `control.paused`, new device token): `homechat-bot`'s own session and PRs, deployed before cutover.
- Deletion reconcile, the Mac half: send `present` daily for the last 14 days (queued on the HomeChat side; not planned here yet).
- `homechat-bot` PR D (`txt-` desk items, not started; PR C merged as homechat-bot#231), per its plan `docs/superpowers/plans/2026-11-08-imsg-phase1-plan.md`, under that repo's rules (spec §9).
- Mac acceptance checks 5–8 (quit-and-reopen catch-up, offline retry, SSN scrub, code skip) on the installed build: not run, waiting for a free test contact. Run them with one question-shaped text so the same run checks a flag on Alex's phone and its clear on his reply.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- Delete the `ImsgAgentProbe` row in Full Disk Access (left from the 2026-11-14 launchd probe, which was removed). Terminal keeps Full Disk Access and Automation → Messages, by his choice (2026-11-09); Claude Code's process also has Full Disk Access since 2026-11-14 for counts-only checks (his grant; he may switch it off).

## DONE
- 2026-11-15 08:28 ET: PR #42 merged (`474a827`, docs only; PR and main CI green): the design, approved.
- 2026-11-15 08:13 ET: Alex approved the standalone-agent design, including Claude's "my call" defaults as written.
- 2026-11-14 20:22 ET: no-send `imsg` trial passed (EVIDENCE). PR #40 merged 17:38 ET (`854f56c`, docs only).
- 2026-11-14 17:40 ET: PR #39 merged (`03cc6d5`, docs only). Alex accepted Fable's pivot direction, pending the trial: a standalone agent (no menu-bar icon unless it is the easier route), a new public repo, and imsg updates that arrive and merge automatically on green CI rather than by hand review. `brew upgrade` does not run unattended on the Mac (no Homebrew launch agent found).

## EVIDENCE
- `imsg` no-send trial on the MacBook (2026-11-14, macOS 27.2, `imsg` 0.21.0, run from Claude's shell with Full Disk Access; every command first rehearsed on a synthetic `chat.db`; shape-only output, no text, handles, names or GUIDs). Chats: 1,796 chat rows, 118 with no messages; `imsg chats` lists 1,678 (it omits empty chats). Only two GUID shapes: `any;-;` direct 1,130 (label iMessage 269, SMS 845, RCS 16) and `any;+;` group 548 (iMessage 356, SMS 176, RCS 16); the group flag matches the prefix on every chat; 0 direct chats without exactly 1 participant; 0 groups under 2. The labels are the stale `chat.service_name`. Watch (1:1 `any;-;` chat, test contact): new, edited, unsent, then Alex's reply from his phone, one line each in order; new rows seen within 1 s of their timestamp; edit and unsend seen 12 s and 27 s after the original's timestamp; 0 stderr lines. Not shown: group, SMS or RCS rows in watch, tapbacks, attachments, body-decoder accuracy, edits and unsends across a restart, and grants for a launchd agent.
- Acceptance checks 1–4 at the Mac (2026-11-09 21:15–21:25 ET, build `2bcc8ad`, counts-only readback of HomeChat's store run by Alex, read-only): (1) status went to up to date; (2) first run stored 26 threads (6 groups) and 255 messages, oldest 3.0 days, none older, 0 skipped rows with text; (3) a test-contact text was stored 2.2 s after it was sent; (4) with Paused on nothing went up and Paused survived a relaunch (Alex's reading); after unpausing the held text was stored once (sent-to-stored 48.5 s). Not run: checks 5–8. Not checked: the runbook's "count roughly matches the Mac's 3-day count". Scrubbing (SSN, codes) is proven only by unit tests on synthetic data; 10 real messages went up as `skipped` with no text, but none was checked against a known code text.
- Spikes (c), (d) on the MacBook (2026-11-08 13:57–14:06 ET, Alex's typed yes, Terminal.app): c1 1:1 sent once (0.6 s); c2 group sent once (0.5 s, arrival confirmed); c3 group with Messages quit sent once (2.6 s, Messages launched in the background); c4 tampered refused with 9004. Alex confirmed c1–c3 arrived. Terminal frontmost before and after c1, c3, c4; c2's focus reading was lost to the macOS 27 `lsappinfo` bug, fixed in PR #7. 3 of 6 sends used.
- Not proven yet: msgblast on current macOS beyond tests, the `NSUnarchiver` decoder on real blobs (proven only on `NSArchiver` output), sends from the fork app itself (not `osascript`), SMS sends, overnight sleep and Low Power Mode sync, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them (fork PRs merge on green CI without asking, since 2026-11-08): never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Plans: `docs/superpowers/plans/` (phase 1 Mac: `2026-11-08-phase1-mac-read-and-uplink.md`). Uplink contract: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`. Acceptance: `docs/superpowers/runbooks/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

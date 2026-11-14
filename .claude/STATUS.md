# Status: msgblast-imessage

**Updated:** 2026-11-14 17:40 ET
**At:** Building is stopped. The Task 0 preflight passed (`any;` chats resolve), but `chat.service_name` proved stale on macOS 27, and three Fable reviews then found the method overbuilt and rigid. Alex ruled that replies go on every route (iMessage, SMS, RCS) and that he uses msgblast only for the companion. Fable recommends leaving the fork for a small standalone agent on the `imsg` library.
**Next:** The no-send `imsg` trial (install `imsg` via Homebrew with Alex's yes, rehearse every command on the synthetic fixture first, then Alex runs it in Terminal.app; counts and shapes only, no send). If it holds: a design for the standalone agent across both repos, one Fable review, then plans.
**Phase:** Phase 3 Replies: redesign; the natural-replies Mac plan is superseded (not built). Mac switch off; HomeChat still refuses every send (`iMessage;` gate). Phase 1 left open: checks 5–8 and desk items (PR D).
**Milestones:** Setup ✓ · Spikes ✓ · Read and flag · Calendar · Replies (now) · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — done (spike (e) full test waits on `homechat-bot`)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — next (uplink, flagger and update live; checks 5–8 and desk items left)
- 2 Calendar — free or clash for texted dates, add on yes — next (HomeChat-only; code in homechat-bot#305, switch off; deploy and acceptance wait on Alex)
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — now (redesign after Fable reviews; possible pivot off the fork; Mac switch off)
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Fork CI (`fork-ci.yml`): runs on PRs and pushes to `main`.
- "msgblast iMessage.app" on the MacBook: the phase 3 build, Apple Development signed, installed 2026-11-12 evening (see DONE); "Send approved replies" turned off again 2026-11-14 ~14:00 ET (quit, edit, reopen). Uplink and the flagger proven working 2026-11-14 (a test text was flagged and nudged). Rollback copies: `build/rollback-20261112*/`.

## QUEUED
- Phase 2 Calendar acceptance (`docs/superpowers/runbooks/phase2-calendar-acceptance.md`): after Alex's yes to deploy HomeChat with its calendar switch on, a test contact's dated text, `N add` by Alex, the event seen in Calendar on his phone. No Mac build.
- Phase 3 redesign: Alex's pivot decision; then the no-send `imsg` trial (install pinned via Homebrew, chat-shape counts, live watch with a test contact; no send); then a design across both repos covering every route, the narrowed code-skip rule, unsaved senders, tolerant result details and wake-tolerant expiry (Fable audit), with one Fable review. The 2026-11-14 natural-replies Mac plan is superseded.
- Deletion reconcile, the Mac half: send `present` daily for the last 14 days (queued on the HomeChat side; not planned here yet).
- `homechat-bot` PR D (`txt-` desk items, not started; PR C merged as homechat-bot#231), per its plan `docs/superpowers/plans/2026-11-08-imsg-phase1-plan.md`, under that repo's rules (spec §9).
- Mac acceptance checks 5–8 (quit-and-reopen catch-up, offline retry, SSN scrub, code skip) on the installed build: not run, waiting for a free test contact. Run them with one question-shaped text so the same run checks a flag on Alex's phone and its clear on his reply.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- His yes to install `imsg` (Homebrew tap `steipete/tap`) for the trial, then the trial run itself in Terminal.app. Terminal keeps Full Disk Access and Automation → Messages for now, by his choice (2026-11-09).

## DONE
- 2026-11-14 17:40 ET: PR #39 merged (`03cc6d5`, docs only). Alex accepted Fable's pivot direction, pending the trial: a standalone agent (no menu-bar icon unless it is the easier route), a new public repo, and imsg updates that arrive and merge automatically on green CI rather than by hand review. `brew upgrade` does not run unattended on the Mac (no Homebrew launch agent found).
- 2026-11-14 17:30 ET: Task 0 preflight (no send): 1:1 `any;-;` ready, group `any;+;` ready, no −1728/9003. `chat.service_name` is stale (a blue-bubble group reads SMS: 6156 iMessage rows to 1 SMS; 40 direct and 16 group chats likewise). Research pass plus three Fable reviews (send path: rethink; every route: drop the service gate, report the route used; whole system: keep the safety core, rethink the method; pivot: standalone agent on `IMsgCore`). Alex: every route allowed; msgblast used only for the companion. Nothing built or sent. Reviews kept locally, outside the repo.
- 2026-11-14: Natural-replies Mac plan merged (PR #36, `32a1a2c`); Task 0 steps 1–5, the preflight recording GUID prefix shape and service, merged (PR #37, `1983a89`). No preflight run recorded yet.

## EVIDENCE
- Acceptance checks 1–4 at the Mac (2026-11-09 21:15–21:25 ET, build `2bcc8ad`, counts-only readback of HomeChat's store run by Alex, read-only): (1) status went to up to date; (2) first run stored 26 threads (6 groups) and 255 messages, oldest 3.0 days, none older, 0 skipped rows with text; (3) a test-contact text was stored 2.2 s after it was sent; (4) with Paused on nothing went up and Paused survived a relaunch (Alex's reading); after unpausing the held text was stored once (sent-to-stored 48.5 s). Not run: checks 5–8. Not checked: the runbook's "count roughly matches the Mac's 3-day count". Scrubbing (SSN, codes) is proven only by unit tests on synthetic data; 10 real messages went up as `skipped` with no text, but none was checked against a known code text.
- Spikes (c), (d) on the MacBook (2026-11-08 13:57–14:06 ET, Alex's typed yes, Terminal.app): c1 1:1 sent once (0.6 s); c2 group sent once (0.5 s, arrival confirmed); c3 group with Messages quit sent once (2.6 s, Messages launched in the background); c4 tampered refused with 9004. Alex confirmed c1–c3 arrived. Terminal frontmost before and after c1, c3, c4; c2's focus reading was lost to the macOS 27 `lsappinfo` bug, fixed in PR #7. 3 of 6 sends used.
- Not proven yet: msgblast on current macOS beyond tests, the `NSUnarchiver` decoder on real blobs (proven only on `NSArchiver` output), sends from the fork app itself (not `osascript`), SMS sends, overnight sleep and Low Power Mode sync, the Mac reaching HomeChat through Cloudflare, the Sparkle and telemetry blanks at runtime.

## STANDING RULES
- `CLAUDE.md` holds them (fork PRs merge on green CI without asking, since 2026-11-08): never write the Messages database; no send without Alex's exact-text approval; uncertain sends never retried; no personal data in this public repo; nothing aimed at upstream without Alex's yes.

## WHERE THINGS ARE
- Design: `docs/superpowers/specs/2026-11-07-imessage-companion-design.md`. Plans: `docs/superpowers/plans/` (phase 1 Mac: `2026-11-08-phase1-mac-read-and-uplink.md`). Uplink contract: `docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`. Acceptance: `docs/superpowers/runbooks/`.
- Remotes: `origin` is the fork; `upstream` is `mgalpert/msgblast`, fetch-only. Fork base: `8fd9191`.
- What changed versus upstream: `FORK.md`.

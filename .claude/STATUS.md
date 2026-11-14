# Status: msgblast-imessage

**Updated:** 2026-11-14 16:10 ET
**At:** The redesigned reply flow has its Mac plan, and the no-send preflight tool is ready. The preflight results aren't recorded yet.
**Next:** Record Alex's preflight result. If both test chats read ready, build the Mac changes task by task on the MacBook.
**Phase:** Phase 3 Replies: natural-replies Mac plan, Task 0 (no-send preflight) steps 1–5 merged; step 6 results not recorded; Mac switch off. Phase 1 left open: checks 5–8 and desk items (PR D).
**Milestones:** Setup ✓ · Spikes ✓ · Read and flag · Calendar · Replies (now) · Duet tools
**Project Desk:** not linked from this public repo

_The instrument panel: rewrite it in place, only ever describing now, on every state change. Why things are the way they are goes in [LOG.md](LOG.md) (append only). Format and rules: the user-level `flight-deck` skill. This repo is public: no names, numbers, hosts or tokens here._

## PLAN
- 0 Spikes — answer the seven unknowns on the MacBook (design §7) — done (spike (e) full test waits on `homechat-bot`)
- 1 Read and flag — flags on the desk and in the WhatsApp update, cleared by a reply — next (uplink, flagger and update live; checks 5–8 and desk items left)
- 2 Calendar — free or clash for texted dates, add on yes — next (HomeChat-only; code in homechat-bot#305, switch off; deploy and acceptance wait on Alex)
- 3 Replies — approved sends with expiry, audit and no retry of ambiguous sends — now (natural-replies Mac plan, Task 0 preflight; Mac switch off)
- 4 Duet tools — waiting texts and reply proposals in Duet — next

## RUNNING NOW
- Fork CI (`fork-ci.yml`): runs on PRs and pushes to `main`.
- "msgblast iMessage.app" on the MacBook: the phase 3 build, Apple Development signed, installed 2026-11-12 evening (see DONE); "Send approved replies" turned off again 2026-11-14 ~14:00 ET (quit, edit, reopen). Uplink and the flagger proven working 2026-11-14 (a test text was flagged and nudged). Rollback copies: `build/rollback-20261112*/`.

## QUEUED
- Phase 2 Calendar acceptance (`docs/superpowers/runbooks/phase2-calendar-acceptance.md`): after Alex's yes to deploy HomeChat with its calendar switch on, a test contact's dated text, `N add` by Alex, the event seen in Calendar on his phone. No Mac build.
- Phase 3 natural replies, Mac half (`docs/superpowers/plans/2026-11-14-phase3-natural-replies-mac.md`): Task 0 step 6 (Alex runs the two no-send preflights in Terminal.app), step 7 (record outcome words and codes in LOG; stop on −1728 or 9003), then Tasks 1–7 on the MacBook with the native gate. Building and installing waits on HomeChat's natural-replies deploy, checked live (plan, Deploy order).
- Deletion reconcile, the Mac half: send `present` daily for the last 14 days (queued on the HomeChat side; not planned here yet).
- `homechat-bot` PR D (`txt-` desk items, not started; PR C merged as homechat-bot#231), per its plan `docs/superpowers/plans/2026-11-08-imsg-phase1-plan.md`, under that repo's rules (spec §9).
- Mac acceptance checks 5–8 (quit-and-reopen catch-up, offline retry, SSN scrub, code skip) on the installed build: not run, waiting for a free test contact. Run them with one question-shaped text so the same run checks a flag on Alex's phone and its clear on his reply.

## BLOCKED
- None.

## HELD
- An upstream PR offering a generic local API to msgblast (design phase 5): only with Alex's yes.

## AWAITING Alex
- None. Terminal keeps Full Disk Access and Automation → Messages for now, by Alex's choice (2026-11-09), in case a Terminal step is needed again.

## DONE
- 2026-11-14: Natural-replies Mac plan merged (PR #36, `32a1a2c`); Task 0 steps 1–5, the preflight recording GUID prefix shape and service, merged (PR #37, `1983a89`). No preflight run recorded yet.
- 2026-11-14: Phase 3 acceptance on the installed build: A not run (Alex skipped); B failed: HomeChat refused the approved edit before queueing ("That thread isn't iMessage", `any;` GUIDs), 0 sends queued, Mac ledger 0; C, D, E not run (Alex chose a redesign first); F skipped earlier. Proven end to end: uplink and the flagger (test text flagged and nudged to Alex's phone). Not proven: any send from the fork app.
- 2026-11-12 21:28 ET: PR #28 merged (`19b93ca`): the fork builds sign with Alex's free Apple Development identity (its hash in `~/.config/msgblast-imessage/signing-identity`, outside the repo; timestamped). Proven on the MacBook: after one Keychain "Always Allow" and a Full Disk Access re-grant, two rebuilds (different cdhashes) were installed with no Keychain dialog, and HomeChat heard from the Mac 10 s after the second. Phase 3 build running from it, sends off. Rollback copies: `build/rollback-20261112*/`. The certificate expires 2027-11-13; renew it in Xcode at the Mac before then.
- 2026-11-11: PR #23 merged (`36e572a`; PR CI full suite green; Mac gate re-run Python 182/0 failed, native 1052/0 failed after a first run with 3 upstream driver-test timeouts that passed alone): phase 3 Mac side (plan Tasks 1–10): send contract fixed, wire models, rules, a fixed argv AppleScript and runner, identity and read-back queries, outcome decision, no-text send ledger with an exclusive lock, sends client, executor, Settings switch (off by default), runbook. Send-safety review: 0 Critical, 3 Important fixed test-first, 6 minors deferred (LOG). Proven only on synthetic fixtures and fakes; no real send from the fork app.

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

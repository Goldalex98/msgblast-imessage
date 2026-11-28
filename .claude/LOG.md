# Log: msgblast-imessage

_The flight recorder: append only, newest at the bottom. Decisions, corrections, dead ends and why. What's true now is in [STATUS.md](STATUS.md). Design decisions stay in the design doc. This repo is public: no names, numbers, hosts or tokens here._

_Older entries (2026-11-07 to the rotation) are in [LOG-archive-2026-11-14.md](LOG-archive-2026-11-14.md)._

Older entries rotated 2026-11-28 (from 2026-11-12 12:00 ET — Phase 3 build installed; the Keycha) are in [LOG-archive-2026-11-28.md](LOG-archive-2026-11-28.md).

## 2026-11-14 17:40 ET — Alex's answers to the pivot review
- Status: whichever is easier; no menu-bar icon if it is more work. Repo: a new public one is fine. Updates: he can't review every `imsg` update by hand, so either don't pin, or bumps must arrive and merge automatically when CI passes; the design has to include that mechanism (e.g. a dependency bot on the `IMsgCore` package plus auto-merge on a green run, and a way for the Mac to pick the merged update up). `brew upgrade`: he didn't set one up, and none runs unattended (no Homebrew launch agent on the Mac).
- Taken as Alex's go-ahead for the pivot direction, conditional on the no-send trial ("Fable review first and then if it checks out we'll move on to a trial"). Nothing installed, built or sent yet.

## 2026-11-14 17:42 ET — Moved from STATUS (size trim)
- 2026-11-14: Phase 3 acceptance on the installed build: A not run (Alex skipped); B failed: HomeChat refused the approved edit before queueing ("That thread isn't iMessage", `any;` GUIDs), 0 sends queued, Mac ledger 0; C, D, E not run (Alex chose a redesign first); F skipped earlier. Proven end to end: uplink and the flagger (test text flagged and nudged to Alex's phone). Not proven: any send from the fork app.

## 2026-11-14 20:25 ET — No-send `imsg` trial passed
- Alex's approvals (18:00 ET): install `imsg` from Homebrew and pin it; give Claude's own process more Mac access so it runs counts-only checks itself. He switched on Full Disk Access for Claude Code; nothing else was changed and no permission was reset.
- Install: `steipete/tap` tapped; only the `imsg` formula trusted (not the whole tap); `imsg` 0.21.0 installed and `brew pin`ned; Developer ID signed (`com.steipete.imsg`) and notarized. `jq` was already present (system `jq` 1.7.1).
- Rehearsal: every command ran first on a synthetic `chat.db` (built from `scripts/tests/companion_fixture.py` plus the extra columns and tables `imsg` reads, outside the repo) with `any;-;`, `any;+;` and legacy chats, one empty chat, a two-handle direct chat, and sentinel strings in every field. Output carried none of the sentinels; junk lines and odd types reduce to `other` or counts. Found on the way: `imsg chats` lists 20 chats unless `--limit` is given; its JSON carries names, handles, GUIDs and participants, so the filters keep only an allow-listed GUID prefix, the service label, the group flag and counts; a read-only open of a WAL database fails when its `-wal`/`-shm` files are gone (rehearsal only; the live database has them).
- Real chats (counts only): 1,796 chat rows (equal to the evidence pack), 118 with no messages; `imsg chats` lists 1,678, so `listChats` omits empty chats (its query inner-joins `chat_message_join`). Shapes: `any;-;` direct 1,130 (iMessage 269, SMS 845, RCS 16); `any;+;` group 548 (iMessage 356, SMS 176, RCS 16); no other prefix; group flag agrees with the prefix on every chat; 0 direct chats without exactly 1 participant; 0 groups under 2; 0 stderr lines.
- Live watch (`imsg watch --json`, stdin not a terminal so it skips Contacts, piped to a shape-only filter; 18:46–20:22 ET): the test contact sent a text, edited it and unsent it, and Alex replied from his phone. Lines in order: new (inbound), edited, unsent, new (from me), all in one `any;-;` chat; the new rows within 1 s of their timestamps; edit and unsend 12 s and 27 s after the original's timestamp. Two earlier lines at 18:54 ET (one inbound, one from me, `any;-;`) are not attributed to the test. 0 stderr lines. No `send`, `react`, `read`, `typing`, `launch` or `rpc` was run.
- Verdict: pass. Fable's "could not verify" items answered: `listChats` omits empty chats (yes, 118); `imsg` runtime on macOS 27.2 for chat listing and for live new, edit and unsend events on a 1:1 chat (yes); a watch `--no-contacts` flag (none exists; a non-terminal stdin skips Contacts instead). Partly answered: grants follow the launching process (it ran on Claude Code's Full Disk Access with no entry of its own), shown only for an interactive parent.
- Still unproven: grants for a launchd agent on macOS 27; group, SMS and RCS rows in the watch; tapbacks and attachments; the body decoder's accuracy on real text; edits and unsends across a restart (not replayed by design); `IMsgCore` built under Xcode 27 with our signing; whether a kept bundle ID carries grants. The send path was not exercised (no dry run exists).

## 2026-11-14 20:25 ET — Moved from STATUS (size trim)
- 2026-11-14 17:30 ET: Task 0 preflight (no send): 1:1 `any;-;` ready, group `any;+;` ready, no −1728/9003. `chat.service_name` is stale (a blue-bubble group reads SMS: 6156 iMessage rows to 1 SMS; 40 direct and 16 group chats likewise). Research pass plus three Fable reviews (send path: rethink; every route: drop the service gate, report the route used; whole system: keep the safety core, rethink the method; pivot: standalone agent on `IMsgCore`). Alex: every route allowed; msgblast used only for the companion. Nothing built or sent. Reviews kept locally, outside the repo.
- 2026-11-14: Natural-replies Mac plan merged (PR #36, `32a1a2c`); Task 0 steps 1–5, the preflight recording GUID prefix shape and service, merged (PR #37, `1983a89`). No preflight run recorded yet.

## 2026-11-15 08:20 ET — Standalone-agent design approved
- Design `docs/superpowers/specs/2026-11-14-imsg-standalone-agent-design.md` drafted 2026-11-14 after the trial. A launchd probe (a throwaway signed agent app) showed the agent gets no `chat.db` access until it has its own Full Disk Access row, and keeps its own Keychain item; the probe was removed. One Fable review: sound with changes, all folded in.
- Alex was shown the twelve "my call" defaults (repo name and MIT licence, bundle ID and `LSUIElement`, one binary for all commands with tunables in config, 15-minute status, remote pause from WhatsApp, sends switched on only at the Mac, the Mac's 30-a-day cap, edits deferred and unsends kept, cutover copying the cursor but not the ledger, the fork token revoked before Stage S, a single uploader, the unchanged out-of-scope list) and approved the design as written (2026-11-15 08:13 ET).
- Next: the implementation plan; its Task 1 proves `IMsgCore` builds as a pinned SwiftPM dependency despite `unsafeFlags` in `imsg`'s executable target, and the plan stops there if it can't. One Fable plan review before building.

## 2026-11-15 08:45 ET — Agent implementation plan drafted and Fable-reviewed
- PR #42 merged as `474a827` (docs only; PR run and the `main` run green): the approved design and its STATUS/LOG.
- Plan `docs/superpowers/plans/2026-11-15-imsg-standalone-agent.md`, 13 tasks. Task 1 is a stop gate: resolve and build `openclaw/imsg` pinned `exact: "0.21.0"` (debug and release), read a synthetic fixture through `IMsgCore`, and sign a hardened-runtime probe app with the real entitlements. Any `unsafeFlags` refusal stops the plan for Alex's decision.
- Read before writing (counts and code only, no real data): `IMsgCore` v0.21.0 source (`1bc0679`) and the fork companion's interfaces. Found: `Message` isn't `Codable`; edits and unsends arrive as a `Message` with `mutationEvent`; `Chat` has no guid or group flag; the fork fixture lacks `message.service`, which `IMsgCore` selects.
- Fable plan review: sound with changes, all nine folded in. Decisions taken from it: no expiry ceiling (the approval-length rule is dropped as design §5.4 says; a `now`-based ceiling would refuse every send from a Mac whose clock runs behind HomeChat's); `highWaterRowID` (`sqlite_sequence`) kept for the replaced-database check, so deleting the newest texts doesn't stall reading; sends fetched while sends are off or paused are ignored (no ledger record, no result), as today; the send-safety reviewer runs on Tasks 3, 5, 7, 8 and 9; read-back pages to the end; uplink posts go through one serializer; the remote-pause gap after a restart is recorded for U7.
- Nothing built, resolved or sent.

## 2026-11-15 08:40 ET — Plan Task 1: `IMsgCore` 0.21.0 works as a pinned dependency
- Alex approved the plan for inline execution (08:32 ET). PR #43 merged as `e59cbb7`.
- On the MacBook (Xcode 27.2, Swift 6.4.2), in a scratch package outside both repos: `.package(url: "https://github.com/openclaw/imsg.git", exact: "0.21.0")`, only the `IMsgCore` product used. `swift package resolve` passed, with no `unsafeFlags` message. Pins: imsg 0.21.0 `1bc0679`, SQLite.swift 0.17.0, PhoneNumberKit 5.0.14, CSQLite 3.53.4, Commander 0.3.0 (resolved, not linked). `swift build` and `swift build -c release` passed, and no `imsg` executable was built.
- `MessageStore.messagesAfterPage` read a synthetic fixture (a copy of the fork's): three joined rows in order, an orphan with `chatID` 0, `nextRowID` 4. The only column the fork fixture lacked was `message.service`.
- A probe `.app` signed with the Apple Development identity, hardened runtime and the Apple Events entitlement: `codesign --verify --strict` valid; the designated requirement is the identifier plus the certificate, with no code hash; it ran with no library-validation error.
- Not shown: the Xcode 27 GitHub runner (Task 2's first CI run), real `chat.db` reads through the library. The probe folder stays until Alex says to delete it.

## 2026-11-15 10:40 ET — the standalone agent is built; this fork freezes
- Plan Tasks 2–13 ran in `Goldalex98/imsg-companion` (PRs #1–#12, each merged on green CI). That repo's LOG holds the detail.
- This fork now changes only for cutover notes. The app stays installed and paused, as the rollback.
- Next is cutover, after HomeChat deploys its §7 changes. The runbooks are in the agent repo's `docs/runbooks/`.
- Nothing has been sent. Nothing real has been read through the agent.

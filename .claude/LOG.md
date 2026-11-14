# Log: msgblast-imessage

_The flight recorder: append only, newest at the bottom. Decisions, corrections, dead ends and why. What's true now is in [STATUS.md](STATUS.md). Design decisions stay in the design doc. This repo is public: no names, numbers, hosts or tokens here._

_Older entries (2026-11-07 to the rotation) are in [LOG-archive-2026-11-14.md](LOG-archive-2026-11-14.md)._

## 2026-11-12 12:00 ET — Phase 3 build installed; the Keychain prompt stops uplink
- Built `a128e1b` with `companion/build_fork_app.py`: codesign verify ok, designated requirement equal to the installed copy's. Installed at ~10:57 ET; the old copy is in `build/rollback-20261112/`. "Send approved replies" is off.
- Uplink then stopped. The app has `chat.db` open, but HomeChat's `last_seen_ts` stopped moving, and `SecurityAgent` is up: a Keychain dialog is waiting. The token item's partition is the build's `cdhash`, so each self-signed rebuild prompts again. I installed while Alex was remote; that was a mistake, and the new rule is to never reinstall while he can't reach the Mac.
- Research (2026-11-12, advice only, untested): a free Apple ID "Apple Development" certificate should give a stable `teamid:` partition (Apple's securityd `clientid.cpp`). Data protection keychain access groups need a profile, so they're out. Alex chose the free route for his next time at the Mac (QUEUED).
- Not run: any acceptance check A–G.

## 2026-11-12 21:30 ET — Fork signing moved to Apple Development; Keychain re-prompt fixed
- Alex answered the waiting Keychain dialog at about 19:10 ET, and uplink resumed.
- Alex created a free "Apple Development" certificate in Xcode. Read-only check: it has OID 1.2.840.113635.100.6.1.12 and a team ID, and is valid until 2027-11-13. It showed as invalid until Apple's WWDR G3 intermediate was added; with Alex's yes, Claude downloaded it from apple.com, checked it chains to Apple Root CA, and imported it into the login keychain. Trust settings were not changed.
- PR #28 (merged `19b93ca`): `build_fork_app.py` takes the identity from `MSGBLAST_SIGN_IDENTITY` or `~/.config/msgblast-imessage/signing-identity`, which holds a SHA-1 so the name stays out of this repo. Apple-issued identities get `--timestamp`.
  - The send-safety review found 4 Important issues, all fixed test-first: `find-identity -v` with whole-line matching; no half-signed app left after a failed re-sign; sign_check accepts the Apple Development authority; a dated note in the spec.
  - Two minors deferred: no notice when an empty identity file falls back; no test of `main()`'s preflight end to end.
  - Mac gate: Python 193 OK, native 1051/0.
- Proof, on the MacBook:
  - The first Apple-signed build needed Alex once: Always Allow for `codesign` in Terminal.app, the Keychain dialog, and a Full Disk Access re-grant.
  - Claude then rebuilt and reinstalled twice from its own shell (different cdhashes). No Keychain dialog appeared, and HomeChat saw the Mac 10 s after the second install.
  - The designated requirement is now `anchor apple generic` plus the certificate's CN, so it should survive renewal. Renewal itself is unproven.
- Not run: any acceptance check. "Send approved replies" is still off.

## 2026-11-14 09:00 ET — STATUS header refreshed
- The At, Phase, Milestones, PLAN and RUNNING NOW lines still described the 2026-11-10 reader-hardening build, though DONE recorded the Apple-signed phase 3 build as installed. They now match DONE.
- Phase 3 is `now` and phase 1 is `next`, because phase 3 acceptance is first in QUEUED; phase 1 still has checks 5–8 and the desk items. This change only re-labels; nothing was re-checked against the Mac or HomeChat.
- STATUS.md is about 16k characters, over the 8k cap. Not trimmed here.

## 2026-11-14 — Moved from STATUS (size trim)
- STATUS.md was about 16k characters against the 8k cap. These lines moved here verbatim: the older DONE bullets, then the EVIDENCE that no longer bears on current work. Kept in STATUS: the five newest DONE bullets and the evidence for the installed build, checks 1–4, the live uplink, the spike sends and what is not proven.

DONE (moved):
- 2026-11-10: PR #17 merged (`651f054`): reader hardening (reopen on a replaced chat.db, a visible reset stop using `sqlite_sequence`, system rows passed over, 4 MiB decode cap) plus phase 3 send notes; green full native suite on the PR. PR #18 merged (`a1ee574`): fork CI scopes the Mac job (none for docs/`.claude`-only PRs, the companion suites for companion-only PRs, the full suite otherwise and on `main`) and runs it in parallel (trial: test step 12m43s vs 20m53s, green). PR #16 merged (`411c626`): agent turn caps raised. The `main` run on `a1ee574` covers all three. Not installed on the Mac.
- 2026-11-10: HomeChat PR B (flagger, scrubber, auto-clear, per-kind spend) merged in `homechat-bot` (homechat-bot#227) and recorded there as live (homechat-bot#228). Not checked from this repo: a flag raised by a real text, seen on Alex's phone, or cleared by his reply.
- 2026-11-09: stale branch `plan/phase1-mac` deleted by Alex (local and GitHub). Its commit with the private domain name stays reachable through closed PR #10 on GitHub.
- 2026-11-08: phase 1 Mac plan Tasks 1–10 on `phase1/mac-read-uplink`: contract, wire models, `attributedBody` decoder, group-aware reader, scrubber, config/Keychain token/uplink client, companion service, Contacts names, Settings section and app wiring, acceptance runbook. Three automated security-review findings fixed test-first (scrubber patterns, actor reentrancy, phone country codes). Rulings in the plan ledger, summarised in LOG.
- 2026-11-08: phase 0 Tasks 8–11 on the MacBook (PRs #5–#9) and the phase 1 Mac plan (PR #11), all merged with green CI.
- 2026-11-07: phase 0 Tasks 1–7 on `spikes/phase0` (`ee7c52b..` 8 commits, incl. one final-review fix pass): probe library and synthetic fixture, spikes (a), (b), (c)/(d), (e), (f), (g), and `companion/build_fork_app.py`. Final review: 0 Critical; 4 Important fixed with tests; 5 minors deferred (LOG 22:10).
- 2026-11-07: forked upstream at `8fd9191` (public, `main` only, Actions disabled); added CLAUDE.md, `.claude/` (settings, agents, STATUS, LOG), FORK.md, `.gitignore` entries and the approved design.

EVIDENCE (moved):
- Acceptance check 0 at the Mac (2026-11-08 20:04–20:06 ET, build `12d78dc`, read by Alex): the companion section shows in Settings ("No uplink yet this session"); Paused stayed on across a quit and relaunch (companion.json saved mode 0600, app restarted 20:04:39); Full Disk Access reads Allowed. The status line's exact words weren't reported. The build predates the review fixes in `5fa56be`.
- PR #12 merged 2026-11-08 (`5fa56be`): PR run 42539220785 and `main` run 42541211665 both green (linux and native on GitHub's `xcode-27`). The Mac gate at `c498bcd` was 944 native tests, 0 failures, and Python 175 OK.
- Phase 1 Mac gate on the MacBook (2026-11-08 18:40–18:51 ET, `12d78dc`): Python script tests 175 OK, 1 skipped; native tests 941 executed, 1 skipped, 0 failures, TEST SUCCEEDED (was 872; 69 new companion tests, all on synthetic `chat.db` fixtures). Signed build of `12d78dc` passes `codesign` validation and its designated requirement, and is installed in `/Applications`, running. Not proven: Keychain token round-trip in the signed app, any read of the real `chat.db` by the app, any post to HomeChat.
- Spike (f asleep) on the MacBook (2026-11-08 16:50–17:10 ET, 20 min, lid closed): 7 sleep gaps; 4 sends, each seen 1.8–5.5 s after sending and 0–12 s after a wake.
- Spike (e) preliminary on the MacBook (2026-11-08 16:27 ET, `reach.py`): bot hostname root answered 404 through Cloudflare in 169 ms, `access_redirect=false`. Not a real route; the full test needs the `homechat-bot` probe route.
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

EVIDENCE (moved, superseded by the phase 3 build):
- Reader-hardening install (2026-11-10 21:50–22:08 ET, `main` `2d037cc`). Pre-install, counts-only and read-only, run by Alex in Terminal.app: `sqlite_sequence` has a `message` entry (AUTOINCREMENT); non-zero `item_type` rows are 279 (types 1–4: 217, 12, 26, 24), none with text or a body. Mac gate (quality-gate agent): Python 182 run, 1 skipped, 0 failed; native 955 executed, 1 skipped, 0 failed, TEST SUCCEEDED. Build: `codesign` valid and satisfies its designated requirement, which matches the old build's (bundle ID plus certificate leaf); Sparkle feed and key empty. The old app quit cleanly before the swap. After relaunch the status read Up to date and no reset stop showed (Alex's reading). Not proven on this build: checks 5–8, any new text uplinked, a replaced-database reopen or a system row passed over at runtime.

DONE (moved, superseded by the phase 3 build):
- 2026-11-10: reader hardening installed on the MacBook (build `2d037cc`) after the counts-only pre-install checks and the Mac gate passed; status reads Up to date.

## 2026-11-14 — Moved from STATUS (size trim)
- 2026-11-11: PR #22 merged (`97f28bb`): the approved phase 3 Mac plan; `main` CI green.
- 2026-11-11: PR #21 merged (`8dfcba2`; Mac gate Python 182/0 failed, native 962/0 failed; PR and `main` CI green): Settings Save says when a token is still needed (empty field, none saved) and reads the token back after writing it, so a write that didn't stick shows an error instead of "Saved". The save logic moved into Core (`CompanionConfig.saveSettings`) with 7 unit tests on a fake token store. Not installed on the Mac; the signed app's Keychain path is unchanged and not re-checked.

## 2026-11-14 11:55 ET — Phase 2 Calendar built on the HomeChat side
- Phase 2 needs no Mac code: HomeChat reads the calendars in plain code on its existing Google Calendar client (Alex's choice over the design's separate calendar run; dated note on design §10 item 3). A date with no time lists that day's events and `N add` makes an all-day event (Alex: "A").
- Fable (medium) reviewed the HomeChat amendment and plan at Alex's ask; findings folded in. Built in `homechat-bot` (PR #305, switch off); its bot-safety review found no critical issues, two fixed test-first.
- Acceptance runbook added here, next to phase 3's. Not verified: any live calendar read or add.

## 2026-11-14 — Phase 3 acceptance stopped at B; redesign chosen
- Setup found on the day: "Send approved replies" was already on; HomeChat `imsg_sends` empty, 0 open flags, Mac ledger 0. Alex skipped A.
- B: the test contact's dated question was flagged and arrived as a "Coming up soon" nudge (item 3). Alex's first reply `N: Edit …` matched no command and went to the general assistant, which asked about the calendar and changed nothing. The correct `3 edit: …` was refused by HomeChat before queueing: "That thread isn't iMessage". Cause: HomeChat's refusal rule (`homechat-bot` `sends.py`, amendment §5) requires a chat GUID starting `iMessage;`, but every thread it holds starts `any;` (60 direct, 8 group). Every send is blocked. All fixtures in both repos use `iMessage;` GUIDs, so tests never saw it.
- Counts-only probe of the Mac's chat table (run by Alex in Terminal.app): `service_name` is never empty; direct: iMessage 288, SMS 913, RCS 29; group: iMessage 356, SMS 183, RCS 27. Every direct chat has exactly 1 handle (1230). So the Mac's own `service_name == "iMessage"` gate and its participant count hold on real data; HomeChat's prefix gate is the only GUID blocker, and `service_name` (not the GUID) is what tells iMessage from SMS/RCS.
- Fable (high) reviewed both halves read-only at Alex's ask. Beyond the GUID gate: near-miss commands and a cancelled confirm fall through to the tool-using assistant; the confirm accepts only a bare `yes`; any other bot line (e.g. "Sent to…") cancels an open confirm; the nudge footer never mentions sending; all script refusal codes report as `script_refused`; a fetched send the Mac never records stays silent for 24 h and blocks its thread; no `any;` fixtures. It proposed per-item nudges with quote-reply selection, `send` / `say <text>` verbs and a plain-language confirm.
- Alex: the y/n flow is "something a computer would understand", the problem is bigger than one reply; redesign first, other acceptance tests not worth running now. Claude turned "Send approved replies" off (app quit, `companion.json` edited, reopened).

## 2026-11-14 — Preflight records prefix shape and service (Task 0 fix)

- `pick_chat.py` stores `guid_prefix` and `service` for the chosen chat, and `send_probe.py` copies both into the preflight report (`unknown` for older configs).
- The prefix rule is narrow: only the five known shapes (`any;-;`, `any;+;`, `iMessage;-;`, `iMessage;+;`, `SMS;-;`) are reported. Anything else, e.g. `SMS;+;`, reports `other`, so a handle-shaped first field can never reach the console or the report. A NULL service or a NULL GUID reports `other`.
- The prefix shapes and service labels are defined once, in `pick_chat.py`; `send_probe.py` derives its `ALLOWED` from them.
- Not run yet: Alex's Step 6 preflight in Terminal.app.

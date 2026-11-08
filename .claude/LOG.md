# Log: msgblast-imessage

_The flight recorder: append only, newest at the bottom. Decisions, corrections, dead ends and why. What's true now is in [STATUS.md](STATUS.md). Design decisions stay in the design doc. This repo is public: no names, numbers, hosts or tokens here._

## 2026-11-07 21:25 ET: project set up
- **Why a separate fork:** the companion needs a Mac app with Full Disk Access and Automation, so it is a fork of msgblast rather than part of HomeChat. Alex chose a public fork (GitHub can't make a fork of a public repo private), so personal data never goes in the repo; config stays local and in the Keychain. The whole app is kept so upstream fixes keep merging; our code goes in new files.
- **Forked** from upstream `main` at `8fd9191` with `--default-branch-only`. The fork came with Actions enabled at the repo level. Turning it off from Claude was refused by the auto-mode classifier, so Alex switched it off himself; re-read as `enabled: false` before anything was pushed. Upstream's workflows need its signing secrets and `xcode-27` runners, and its release jobs aren't ours.
- **Remotes:** `upstream` has its push URL disabled, so nothing can be pushed upstream by accident. `gh repo set-default` points at the fork, because `gh pr create` in a fork otherwise targets the parent.
- **Upstream's AGENTS.md:** its process rules (branch prefix, evidence SHAs, video per PR, PR size) are for upstream contributions only. Its safety rules (never mutate the Messages database, uncertain sends are not retried, no real sends for evidence, Linux checks don't prove native builds) were carried into CLAUDE.md.
- **Chat content stays out of dev sessions:** `.claude/settings.json` denies reading the Messages and Contacts stores, and the spikes print only counts and shapes. Read denies don't cover Bash, so CLAUDE.md states the rule too.
- **No standing merge rule:** each PR inside the fork is merged only with Alex's yes for that PR, until he says otherwise.
- **STATUS/LOG instead of a handoff file**, the same flight-deck pattern as HomeChat. The Project Desk link is left out because the repo is public.
- **Agents:** `quality-gate` (Haiku, high) and `send-safety-reviewer` (Sonnet, medium). No ops inspector (nothing runs yet) and no Opus reviewer (no money or deletion here).
- **The design** was copied unchanged from HomeChat's research notes, where Alex approved it at 13:00 ET. A scan found no hostnames, IP addresses, phone numbers, emails or tokens. The background evaluation stays in `homechat-bot`.
- **Clone detail:** the Remember plugin had already written `.remember/` into the empty folder, which blocks `git clone <url> .`. It was moved aside for the one clone command and moved back; it is git-ignored.

## 2026-11-07 21:30 ET: commit identity and folder trust
- **Commit email:** this repo's commits use the GitHub noreply address (local `git config user.email` in this clone only), because a public repo would otherwise publish the personal address in its history. The setup commit was rewritten before its first push, so no commit with the personal address was ever pushed. Set the same local email in the MacBook clone.
- **Folder trust:** the first headless agent runs warned that the project allow rules were ignored. The parent folder is trusted, so no trust prompt appears, but the CLI checks this folder's own flag, which was false. Alex set it; the re-run showed no warning. Lesson: read `claude -p` stderr in live proofs, because 0 denials alone can mean auto mode allowed the command.

## 2026-11-07 21:50 ET: phase 0 plan approved
- Alex approved `docs/superpowers/plans/2026-11-07-phase0-spikes.md`. It runs inline (his standing rule: inline unless he picks subagent-driven).
- Why probes in Python, not Swift: they run in the existing Linux gate against synthetic databases, and they can be read before they ever touch the real `chat.db`. Phase 1 ports the decoder to Swift.
- Why reuse upstream's preview builder for the fork app: it already isolates the bundle ID, the support folder and Sparkle, so no upstream file needs editing. The fork variant uses the blue icon because the builder expects blue-green only for its own `development` variant.

## 2026-11-07 22:10 ET: phase 0 probes built and reviewed
- Tasks 1–7 ran inline on `spikes/phase0`, each test-first. A fresh Opus code review and `send-safety-reviewer` found no Critical issues.
- Fixed before any Mac run: undecodable text in `chat.db` could have put message text or a group name into an error message; a real send could go uncounted if interrupted during `osascript`, or unreported if the 30 s anchor watch failed; an ambiguous send didn't stop a rerun (now a `.local/spikes/send-blocked` marker that only Alex deletes, after checking with the test contacts).
- Kept on purpose: `--tamper` stays a real send attempt, because Task 10 tests that the real send path refuses a changed member set. The 6-send cap counts real sends only; preflights carry no send command.
- Deferred minors: no lock on the send counter (don't run two probes at once); `sync_watch` writes nothing if stopped with Ctrl-C (let it run to `--minutes`); the fork build's temp copy briefly includes `.local/`; a failed re-sign leaves the ad-hoc app in `build/fork-app`; `find_anchor` matches the plain `text` column only, so `anchor_rows 0` means "check by hand", not "not delivered".

## 2026-11-07 22:15 ET: phase 0 code merged
- Alex said go: PR #2 (plan) then PR #3 (probes) merged into `main` locally as merge commits under the noreply identity, as with PR #1.

## 2026-11-07 22:25 ET: fork CI
- Alex asked for CI. Upstream's six workflows stay off (several are release, signing and notarization jobs that expect upstream's secrets); each is switched off by name, so turning Actions back on runs only the fork's own `fork-ci.yml`.
- Why `xcode-27`: it is GitHub's hosted Xcode 27 image (public preview, arm64), the same label upstream uses; the job pins Xcode 27.0 like upstream. The Linux job mirrors the Linux gate; the macOS job runs the Python tests and the native core tests exactly as `docs/testing.md` writes them.
- No secrets, no artifacts, `contents: read`, checkout without persisted credentials, and every job is limited to this repository.

## 2026-11-08 07:55 ET: Task 8 stopped at the Xcode check
- Cloned on the MacBook (it had no copy: the earlier sessions ran on the Linux box). `gh repo clone` added `upstream` by itself, so only the push URL needed disabling; it's `DISABLED` rather than the plan's longer string, same effect.
- Stopped per the plan's Step 1 rule: Xcode 27 is missing. Installing and selecting Xcode needs Alex's Apple ID and password, so it's his step. `/usr/bin/python3` is 3.9.6; the plan's spikes run with it, so check they don't need newer syntax when Task 8 resumes.

## 2026-11-08 08:20 ET: Task 8 Steps 1–2 on the MacBook
- Alex installed Xcode 27.2 and selected it. 27.2 rather than CI's pinned 27.0; the native tests pass on both.
- Gate run in `default` permission mode, not `auto`, so a command outside the allow rules would have shown as a denial rather than being allowed silently. 0 denials and a clean stderr prove the two Mac allow rules match. The agent's counts were cross-checked against the xcresult bundle.

## 2026-11-08 08:45 ET: spikes (a) and (b) on the real database
- Alex ran both in Terminal.app rather than the Claude app's terminal pane, so Full Disk Access went to Terminal only and Claude's tools still can't open `chat.db`. The `.local/` deny also blocks Claude's Bash, so Alex pasted the two counts-only reports; they held only numbers and key names.
- The decoder's 3.3% mismatch on rows with both columns is why the phase 1 recommendation is the system typedstream reader rather than porting the byte scanner. The probe can't say how the rows differ without reading text, which dev sessions don't do.

## 2026-11-08 10:40 ET: phase 1 decoder is NSUnarchiver
- Alex chose the system typedstream reader (`NSUnarchiver` into `NSAttributedString`) over porting the byte scanner. Why: the scanner matched `text` exactly on only 96.7% of rows with both columns, and the system reader is Apple's own format implementation. The Python decoder stays as the oracle for synthetic fixtures; no mismatch-shape probe is needed.

## 2026-11-08 11:05 ET: spike (f awake) and Task 8 done
- 8 events rather than the 3 test texts: `sync_watch` counts every `is_from_me` row, tapbacks included, from any device. That's a bigger sample, not an error. All delays fell inside the 2 s poll, so awake sync is faster than the probe can resolve.
- Plan box ticks for Task 8 are left as they are; STATUS and the results doc are the record.

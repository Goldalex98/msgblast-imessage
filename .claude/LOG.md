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

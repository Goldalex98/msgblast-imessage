# About this fork

`Goldalex98/msgblast-imessage` is a modified copy of [mgalpert/msgblast](https://github.com/mgalpert/msgblast).
It was forked from upstream `main` at `8fd9191f4838e5764f92330e24d0aa9d4b83451f` on 2026-11-07.
Like upstream, it is licensed under GPL-3.0-only (see [LICENSE](LICENSE)).

This fork is not affiliated with or endorsed by the msgblast authors. Please report problems with
fork-only features here, not upstream.

## What this fork changes

- **Since 2026-11-07:** Claude Code project files (`CLAUDE.md`, `.claude/`), the design of an
  iMessage companion (`docs/superpowers/specs/`), this file, and extra `.gitignore` entries.
- **Since 2026-11-07:** `companion/` holds fork-only tools: `build_fork_app.py` builds
  "msgblast iMessage.app" (its own bundle ID and support folder, updates and telemetry off) by
  reusing upstream's preview builder unchanged, and `companion/spikes/` holds the phase 0 probes,
  which print counts only. Their tests are `scripts/tests/test_companion_*.py`.
- **Since 2026-11-07:** `.github/workflows/fork-ci.yml` is the fork's own CI (Python tests on
  Linux and macOS, plus the native core tests). Upstream's workflows are kept but switched off in
  this fork's Actions settings.
- **Since 2026-11-08 (phase 1):** the companion's read-and-uplink half. `msgblast/Core/Companion/`
  reads every Messages thread, groups included, read-only; removes SSN-shaped numbers and skips
  verification codes and short-code senders; and posts new messages to the owner's home server
  (`docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`). `msgblast/Companion/` adds a
  status section at the top of Settings, Contacts names, and the 2 s timer. Settings live in
  `companion.json` in the app's support folder; the token lives in the login keychain. It does
  nothing until an address and token are saved.
- **Planned** (see the design): flagging messages waiting on a reply, and sending a reply only
  after the owner approves its exact text (phase 3).

Known limits of the companion:

- Message bodies stored only as `attributedBody` are decoded with `NSUnarchiver` after a
  structural check (header, class names, a string length that fits). `NSUnarchiver` raises an
  Objective-C exception on corrupt input that Swift can't catch, so a blob that passes the check
  but is still corrupt would crash the app. The check makes that unlikely, and the reader records
  the row it is decoding first, so after such a crash that row is treated as unreadable and the
  next launch carries on (one crash, not a crash loop).
- Edits, unsends and delivery changes rewrite existing rows and aren't uplinked.

New code goes in separate files where possible. Upstream files this fork changes are listed here
as they change:

| Upstream file | Changed since | Why |
|---|---|---|
| `.gitignore` | 2026-11-07 | Local Claude Code and tool files |
| `scripts/generate_project.py` | 2026-11-08 | Compiles the companion's `ContactNameResolver.swift` into the tests target, beside upstream's `MessagesAccessGuide.swift` case |
| `msgblast/App/msgblastApp.swift` | 2026-11-08 | `AppStartup` creates and starts one `CompanionController` (not in demo mode) and passes it to Settings |
| `msgblast/Windows/Views.swift` | 2026-11-08 | `AppSettingsView` takes an optional `companion` and shows its section first |

# About this fork

`Goldalex98/msgblast-imessage` is a modified copy of [mgalpert/msgblast](https://github.com/mgalpert/msgblast).
It was forked from upstream `main` at `8fd9191f4838e5764f92330e24d0aa9d4b83451f` on 2026-11-07.
Like upstream, it is licensed under GPL-3.0-only (see [LICENSE](LICENSE)).

This fork is not affiliated with or endorsed by the msgblast authors. Please report problems with
fork-only features here, not upstream.

## What this fork changes

- **Since 2026-11-07:** Claude Code project files (`CLAUDE.md`, `.claude/`), the design of an
  iMessage companion (`docs/superpowers/specs/`), this file, and extra `.gitignore` entries.
  No app code has changed yet.
- **Since 2026-11-07:** `companion/` holds fork-only tools: `build_fork_app.py` builds
  "msgblast iMessage.app" (its own bundle ID and support folder, updates and telemetry off) by
  reusing upstream's preview builder unchanged, and `companion/spikes/` holds the phase 0 probes,
  which print counts only. Their tests are `scripts/tests/test_companion_*.py`.
- **Planned** (see the design): an iMessage companion that reads Messages threads read-only,
  flags messages waiting on a reply, sends them to the owner's own home server, and sends a reply
  only after the owner approves its exact text. Builds of this fork will use their own bundle ID,
  with automatic updates and telemetry off.

New code goes in separate files where possible. Upstream files this fork changes are listed here
as they change:

| Upstream file | Changed since | Why |
|---|---|---|
| `.gitignore` | 2026-11-07 | Local Claude Code and tool files |

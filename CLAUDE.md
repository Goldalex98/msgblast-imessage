@AGENTS.md

## Claude Code setup
- No project MCP servers (`.mcp.json`).
- `.claude/settings.json` pre-allows only the two gate commands. It denies reading `.env*`, `*.local.json`, `.local/`, permission-test receipts, and the Messages and Contacts stores under `~/Library`. Read denies don't cover Bash; the rules above do.
- Claude Code also uses its user-level evidence-verifier, implementer and global git-guard hook.

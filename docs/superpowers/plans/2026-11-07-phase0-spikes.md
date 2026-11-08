# iMessage companion, phase 0 (spikes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer the seven phase 0 unknowns (spec §7, spikes a–g) on Alex's MacBook with small, tested probes, and give the fork its own isolated, stably signed app. The phase 1 plan can then be written from measurements instead of guesses.

**Architecture:**
- Probes are standard-library Python scripts in a new `companion/spikes/` folder (fork-only, no upstream file edits). They are unit-tested on Linux against synthetic `chat.db` fixtures through the existing gate.
- Alex runs them on the Mac. Each one writes a counts-only JSON report to `.local/spikes/` (git-ignored), and Claude reads only those reports.
- The one sending probe adapts msgblast's identity-checked AppleScript to groups.
- The fork's app is built with upstream's isolated-preview builder (`scripts/build_preview_apps.py`) under its own variant, then re-signed with a self-signed certificate.

**Tech Stack:** Python 3.9+ standard library (`sqlite3`, `json`, `argparse`, `unittest`, `subprocess`, `urllib`, `plistlib`), AppleScript via `/usr/bin/osascript`, `lsappinfo`, `codesign`, Xcode 27 `xcodebuild`, Keychain Access.

**Spec:** `docs/superpowers/specs/2026-11-07-imessage-companion-design.md` (§3, §4.1, §5.1, §6, §7 phase 0, §10.1, §10.4, §10.8). Later phases get their own plans (end of this file).

## Global Constraints

- **Python:** standard library only, compatible with Python 3.9 (the Mac's `/usr/bin/python3` may be 3.9). Every module starts with `from __future__ import annotations`. No `match`, no `datetime.UTC`. Run as `python3 -I <script>`; each script puts its own folder on `sys.path` before importing `spikelib`.
- **Opening `chat.db`:** only as `sqlite3.connect("file:" + urllib.parse.quote(path) + "?mode=ro", uri=True, timeout=1.5)`. This matches msgblast's `SQLITE_OPEN_READONLY` and 1500 ms busy timeout (`msgblast/Core/MessagesDatabase.swift:12,18`). Never write, never touch read state (spec §5.1).
- **Apple time:** `raw / 1e9 if raw > 1e12 else raw` seconds since 2001-01-01 UTC; add `978307200` for Unix time (`MessagesDatabase.swift:202-205`).
- **Reactions:** rows with `associated_message_type` between 2000 and 3999 are not messages (`MessagesDatabase.swift:92`).
- **Group vs 1:1:** `chat.style` 43 is a group and 45 is 1:1. Also count participants via `chat_handle_join`, because msgblast uses only participant count (`MessagesDatabase.swift:63`).
- **Reports:**
  - They may contain only dict keys, numbers, booleans, `null`, and strings from a fixed enum the probe declares. Never message text, handles, names, display names, chat IDs or URLs (spec §6).
  - They are written to `.local/spikes/<probe>-<UTC yyyymmddTHHMMSSZ>.json` with mode 0600.
  - The public results doc carries percentages and verdicts only, no absolute message counts.
- **Identifiers:** test-chat IDs, handles and the HomeChat probe URL live only in `.local/spikes/config.json`. `pick_chat.py` writes the chat IDs and handles; Alex adds the URL himself. Claude never opens that file; `.claude/settings.json` denies `./.local/**`.
- **Who runs what:** Claude writes and tests probes on Linux. Alex runs every probe that opens the real `chat.db`, sends, or probes HomeChat, in his own Terminal. That Terminal has Full Disk Access and Automation → Messages for phase 0 only; he revokes both afterwards. A Claude session on the Mac never runs these probes (CLAUDE.md: dev sessions never read real chat content).
- **Sends:**
  - Only through `send_probe.py`, only to the targets in config, and only after Alex types `SEND` at its prompt.
  - At most 6 real sends in phase 0 (counter file `.local/spikes/send-count`).
  - The text is exactly `msgblast-imessage spike <label> <HHMMSS>`.
  - `ambiguous` is never retried.
- **Fork app:** bundle ID `io.github.goldalex98.msgblast-imessage`, app `msgblast iMessage.app`, support folder `msgblast-iMessage` (must start `msgblast-`, `msgblast/Core/InstallationLocation.swift:17-21`), signing identity `msgblast-imessage local signing` (self-signed, Code Signing). Sparkle stays off and the update feed empty. Telemetry is already off for any bundle ID other than upstream's two (`msgblast/Core/Telemetry.swift:134`). Feedback posts to msgblast.app only when Alex submits it himself (`msgblast/Core/FeedbackSubmission.swift:5`), so it isn't patched in phase 0.
- **Git:** branch `spikes/phase0`, PR inside the fork, `send-safety-reviewer` before merge, merge only with Alex's yes.

## Review Focus

1. **A report leaks a message's text, a handle, a chat ID or a group's name** to a file Claude then reads. Expected: none of them ever appears. Each probe task has a sentinel test.
2. **Full Disk Access is missing**, so `chat.db` can't be opened. Expected: exit code 2 with a one-line hint naming Full Disk Access, no traceback, no report file (Task 1).
3. **Messages is writing to the live WAL database during a probe.** Expected: the probe reads committed rows, gives up after 1.5 s instead of hanging, and never writes (Task 1).
4. **An `attributedBody` is truncated, empty or not UTF-8.** Expected: counted as a decode failure, never raises (Task 2).
5. **A group's membership or service changed since config was written, or the text contains quotes, backslashes or newlines.** Expected: nothing is sent, outcome `not_sent` with the error code; text is escaped exactly as msgblast does (Task 5).

---

### Task 1: Probe library and synthetic chat.db fixture

**Files:**
- Create: `companion/spikes/spikelib.py`
- Create: `scripts/tests/companion_fixture.py` (test helper, imported by the companion tests)
- Test: `scripts/tests/test_companion_spikelib.py`

**Interfaces:**
- Produces (`spikelib`):
  - `class ProbeError(Exception)` with `.code: int`.
  - `open_ro(path: str) -> sqlite3.Connection`: raises `ProbeError(2, FDA_HINT)` when the file can't be opened.
  - `FDA_HINT: str = "Can't open chat.db read-only. Grant Full Disk Access to the app running this command (System Settings > Privacy & Security > Full Disk Access), then retry."`
  - `apple_seconds(raw: int) -> float` (seconds since 2001) and `unix_time(raw: int) -> float`.
  - `assert_counts_only(report: dict, allowed: frozenset[str]) -> None`: raises `ValueError` naming only the offending key path.
  - `write_report(name: str, report: dict, allowed: frozenset[str], out_dir: Path | None = None) -> Path`: `out_dir` defaults to `<repo>/.local/spikes`.
  - `load_config(path: Path | None = None) -> dict`
  - `run_main(fn: Callable[[], int]) -> int`: maps `ProbeError` to its code and message on stderr.
- Produces (fixture):
  - `build_chat_db(path: Path, wal: bool = False) -> None` creates the tables `chat(ROWID, guid, style, display_name, service_name)`, `handle(ROWID, id, service)`, `chat_handle_join`, `chat_message_join`, `message(ROWID, guid, text, attributedBody, date, is_from_me, handle_id, service, thread_originator_guid, associated_message_type, cache_has_attachments)`.
  - Builder helpers: `add_chat(...) -> int`, `add_message(...) -> int`.
  - `make_attributed_body(text: str) -> bytes` (format in Task 2).
  - `SENTINELS: tuple[str, ...]`, holding the text `SENTINEL-TEXT-7f3a`, handle `+15550001111`, email handle `sentinel@example.invalid`, chat GUID `iMessage;+;chatSENTINEL` and display name `SENTINEL GROUP`.
  - `seed_standard(path: Path) -> None`: one 1:1 chat and one 3-person group. Every row uses the sentinels, dates fall inside a 14-day window, plus one reaction row and one row older than the window.

- [ ] **Step 1: Write the failing tests** in `test_companion_spikelib.py`:
  - `test_open_ro_rejects_writes`: `open_ro(db).execute("INSERT INTO handle(id) VALUES ('x')")` raises `sqlite3.OperationalError`.
  - `test_open_ro_missing_permission_exits_2`: the db is `chmod 000`, so `open_ro` raises `ProbeError` with `.code == 2` and the message equal to `FDA_HINT`. Skip when running as root.
  - `test_open_ro_reads_committed_rows_during_open_write`: WAL fixture; a second connection runs `BEGIN IMMEDIATE`, inserts a row and doesn't commit. `open_ro` counts only the committed rows within 2 s.
  - `test_apple_time_units`: `apple_seconds(810000000000000000) == 810000000.0`; `apple_seconds(810000000) == 810000000.0`; `unix_time(0) == 978307200.0`.
  - `test_assert_counts_only`: accepts `{"a": 1, "b": {"c": True, "d": None, "e": 0.5}, "f": "sent"}` with `allowed={"sent"}`. Rejects a free string at `f` (error mentions `f` but not the value), and rejects a list holding a string.
  - `test_write_report_mode_and_name`: the file name matches `^bodies-\d{8}T\d{6}Z\.json$` and the mode is `0o600`.

- [ ] **Step 2: Run them and see them fail**
  Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_companion_spikelib.py' -v`
  Expected: `ModuleNotFoundError`/`ImportError` for `spikelib`.

- [ ] **Step 3: Implement `spikelib.py` and `companion_fixture.py`** with the signatures above. The tests import `spikelib` after `sys.path.insert(0, str(ROOT / "companion/spikes"))`, as upstream tests use `ROOT = Path(__file__).resolve().parents[2]`.

- [ ] **Step 4: Run the full Linux gate.**
  Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`
  Expected: `OK (skipped=2)` plus the new tests passing (upstream count 121 + new).

- [ ] **Step 5: Commit** `git add companion/spikes/spikelib.py scripts/tests/companion_fixture.py scripts/tests/test_companion_spikelib.py && git commit -m "Add the phase 0 probe library and synthetic chat.db fixture"`

### Task 2: Spike (a): bodies stored only in `attributedBody`

**Files:** Create `companion/spikes/bodies.py`; Test `scripts/tests/test_companion_bodies.py`

**Interfaces:**
- Consumes: `spikelib.open_ro`, `apple_seconds`, `write_report`, `run_main`; fixture `make_attributed_body`, `seed_standard`, `SENTINELS`.
- Produces: `decode_attributed_body(blob: bytes | None) -> str | None` (phase 1 ports it to Swift); `probe_bodies(conn, days: int = 14, now_unix: float | None = None) -> dict`.

The report keys, all integers, over non-reaction messages in the window:
- `total`, `text_present`
- `attributed_only`, `attributed_only_decoded`, `attributed_only_failed`
- `neither`, `neither_with_attachment`
- `cross_check_total` and `cross_check_equal`: rows that have both, and how many decode exactly to `text`. This proves the decoder on real data without printing any text.

The decoder algorithm (typedstream; the signature doesn't determine it):
```python
i = blob.find(b"NSString");  j = blob.find(b"\x01+", i)   # "+" starts the string payload
k = j + 2; n = blob[k]; k += 1
if n == 0x81: n = int.from_bytes(blob[k:k + 2], "little"); k += 2
elif n == 0x82: n = int.from_bytes(blob[k:k + 4], "little"); k += 4
raw = blob[k:k + n]  # None if i < 0, j < 0, k past end, len(raw) != n, or not UTF-8
```
`make_attributed_body(text)` emits `b"\x04\x0bstreamtyped\x81\xe8\x03\x84\x01@\x84\x84\x84\x12NSAttributedString\x00\x84\x84\x08NSObject\x00\x85\x92\x84\x84\x84\x08NSString\x01\x94\x84\x01+"`, then the length, the UTF-8 bytes, and `b"\x86\x84\x02iI\x01\x01\x92\x84\x84\x84\x0cNSDictionary\x00"`. The length is one byte when it is ≤ 0x7F, else `0x81` plus 2 bytes LE, or `0x82` plus 4 bytes LE.

- [ ] **Step 1: Write the failing tests.**
  - `test_decode_round_trip`: covers `"hi"`, a 200-character string (the 0x81 form), a 70,000-character string (the 0x82 form), and `"café 👋"`.
  - `test_decode_bad_input_returns_none`: covers `None`, `b""`, a blob without `NSString`, a blob truncated mid-payload, and `b"\xff\xfe"` payload bytes. None of them raises.
  - `test_probe_counts_on_fixture`: `seed_standard` plus 2 attributed-only rows (1 decodable, 1 truncated), 1 row with neither but an attachment, and 1 row with both matching. The test asserts each of the eight report keys, with the reaction row and the old row excluded.
  - `test_report_has_no_sentinels`: `json.dumps(probe_bodies(...))` contains none of `SENTINELS`, and `assert_counts_only(report, frozenset())` passes.
- [ ] **Step 2: Run them and see them fail.** Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_companion_bodies.py' -v`; expected: `ImportError`.
- [ ] **Step 3: Implement** `decode_attributed_body`, `probe_bodies` (window filter in SQL using the Apple-time `CASE` expression), and `main()`. The CLI is `--db` (default `~/Library/Messages/chat.db`) and `--days`; it writes the report via `write_report("bodies", ...)` and prints only the report path.
- [ ] **Step 4: Run the full Linux gate** (command as in Task 1, Step 4). Expected: OK.
- [ ] **Step 5: Commit** `bodies.py` and its test: "Add spike (a): attributedBody-only bodies probe".

### Task 3: Spike (b): reading group threads

**Files:** Create `companion/spikes/groups.py`; Test `scripts/tests/test_companion_groups.py`

**Interfaces:**
- Consumes: Task 1.
- Produces: `probe_groups(conn, days: int = 14, now_unix: float | None = None) -> dict`.

Report keys, all integers:
- `chats_by_style`: `{"group_43", "one_to_one_45", "other"}`
- `style_count_mismatch`: style 43 with ≤1 participant, or style 45 with >1
- `groups_active`
- `participants`: buckets `{"p2", "p3", "p4_6", "p7_plus"}`
- `group_inbound`, `group_inbound_with_sender`: `handle_id > 0` resolves to a `handle` row
- `group_outgoing`, `group_with_reply_link`: `thread_originator_guid` set
- `groups_with_display_name`

- [ ] **Step 1: Write the failing tests.**
  - `test_counts_on_fixture`: the standard fixture plus one group inbound message with `handle_id = 0` and one style-45 chat with 2 handles. The test asserts each key.
  - `test_report_has_no_sentinels`: same as Task 2.
- [ ] **Step 2: Run them and see them fail** (`-p 'test_companion_groups.py'`). Expected: `ImportError`.
- [ ] **Step 3: Implement** `probe_groups` and `main()`. The CLI has `--db` and `--days`, and the report name is `groups`.
- [ ] **Step 4: Run the full Linux gate.** Expected: OK.
- [ ] **Step 5: Commit** "Add spike (b): group thread read probe".

### Task 4: Spike (f): iPhone-to-Mac sync delay watcher

**Files:** Create `companion/spikes/sync_watch.py`; Test `scripts/tests/test_companion_sync_watch.py`

**Interfaces:**
- Consumes: Task 1.
- Produces: `watch(db_path: str, label: str, poll_s: float = 2.0, max_minutes: float = 30.0, clock=time.time, sleep=time.sleep, max_polls: int | None = None) -> dict`.

How it works:
- It records the baseline `MAX(ROWID)` and `PRAGMA data_version`. Each poll checks `data_version`; when it changes, the watcher reads the new `is_from_me = 1` rows above the baseline.
- A poll gap longer than `3 * poll_s` counts as a sleep. It sets `resume_at` and increments `sleeps_detected`.
- Each new row adds an event: `{"delay_s": clock() - unix_time(date), "since_resume_s": clock() - resume_at or null, "service": "imessage" | "sms" | "other"}`.
- The report is `{"label", "poll_s", "events": [...], "sleeps_detected", "duration_s"}`. `label` must be one of `{"awake", "asleep"}`.

- [ ] **Step 1: Write the failing tests.** They use a fake `clock` and a fake `sleep`; the fake `sleep` inserts rows through a second, writable connection.
  - `test_reports_delay_for_new_outgoing_row`: a row dated 5 s before the fake now gives `delay_s ≈ 5`.
  - `test_ignores_inbound_and_preexisting_rows`
  - `test_detects_sleep_gap`: the clock jumps 600 s between polls, so `sleeps_detected == 1` and `since_resume_s` is set.
  - `test_report_has_no_sentinels`
- [ ] **Step 2: Run them and see them fail.** Expected: `ImportError`.
- [ ] **Step 3: Implement** `watch` and `main()`. The CLI has `--db`, `--label` (required), `--minutes`, and the report name is `sync-<label>`.
- [ ] **Step 4: Run the full Linux gate.** Expected: OK.
- [ ] **Step 5: Commit** "Add spike (f): sync delay watcher".

### Task 5: Spikes (c) and (d): identity-checked group send, and focus

**Files:** Create `companion/spikes/send_probe.py`, `companion/spikes/pick_chat.py`; Test `scripts/tests/test_companion_send_probe.py`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `literal(value: str) -> str`: escapes `\`, `"`, CR and LF, then wraps in quotes, exactly as `msgblast/Core/MessagesSendScript.swift:35-37`.
  - `build_send_script(chat_id: str, expected_handles: list[str], text: str, preflight_only: bool, timeout_s: int = 20) -> str`
  - `parse_outcome(returncode: int, stdout: str, timed_out: bool) -> tuple[str, int | None]`: returns `sent` for `SUBMITTED`, `ready` for `READY`, `not_sent` plus the code for `NOT_SUBMITTED:<code>`, and `ambiguous` for everything else, including `UNCERTAIN:` (same rule as `msgblast/Messages/MessageSender.swift:63-72`).
  - `frontmost(runner) -> str`: one of `messages`, `terminal`, `other` or `unknown`, from `lsappinfo info -only name "$(lsappinfo front)"`.
  - `messages_running(runner) -> bool`: from `pgrep -x Messages`.
  - `find_anchor(db_path, chat_id, text, attempted_unix, wait_s=30.0, clock, sleep) -> dict`: returns `{"rows": int, "delay_s": float | None}`. It counts outgoing rows in that chat whose text equals `text` and whose `date` ≥ attempted − 2 s (msgblast's anchor rule, `msgblast/Core/Routing.swift:63-76`).
  - `run_probe(config: dict, target: str, label: str, preflight_only: bool, tamper: bool, id_prefix: str | None, runner, confirm=input, db_path: str) -> dict`
  - `pick_chat(db_path, kind: str, name_contains: str | None, handle: str | None, config_path: Path) -> int`: writes `config[kind] = {"chat_id": guid, "handles": [...]}` and prints only `wrote <kind> target with N participants`. It refuses unless exactly one chat matches.

The script, adapted from `MessagesSendScript.swift:16-33` (exact copy, because this is what the spike tests):
```applescript
set submissionAttempted to false
try
  with timeout of {timeout_s} seconds
    tell application "Messages"
      set targetChat to chat id {literal(chat_id)}
      if (id of targetChat as text) is not {literal(chat_id)} then error "identity" number 9001
      if service type of account of targetChat is not iMessage then error "service" number 9003
      set seen to {}
      repeat with p in participants of targetChat
        set end of seen to (handle of p as text)
      end repeat
      if (count of seen) is not {len(expected_handles)} then error "count" number 9002
      repeat with h in {{{", ".join(literal(h) for h in expected_handles)}}}
        if seen does not contain (h as text) then error "member" number 9004
      end repeat
      {'return "READY"' if preflight_only else 'set submissionAttempted to true'}
      {'' if preflight_only else 'send ' + literal(text) + ' to targetChat'}
      {'' if preflight_only else 'return "SUBMITTED"'}
    end tell
  end timeout
on error detail number code
  if submissionAttempted then return "UNCERTAIN:" & code
  return "NOT_SUBMITTED:" & code
end try
```

`run_probe` order:
1. Read `send-count` and refuse at 6.
2. Print the label, the target kind and the participant count, then require `confirm("Type SEND to send ...: ") == "SEND"`. Preflight runs skip this.
3. Record `frontmost` and `messages_running`.
4. Run `osascript -` with the script on stdin and a 35 s timeout.
5. Record `frontmost` and `messages_running` again.
6. On `sent` or `ambiguous`, bump `send-count` and call `find_anchor`.

`tamper=True` replaces the last expected handle with `tamper@example.invalid`. `id_prefix` rewrites the chat ID's service prefix (for example `any;+;…`) when Messages rejects the `chat.db` GUID.

Report keys:
- `label`, `target` (`group` or `one_to_one`), `preflight_only`, `tamper`
- `outcome`, `code`, `elapsed_ms`
- `frontmost_before`, `frontmost_after`, `messages_running_before`, `messages_running_after`
- `anchor_rows`, `anchor_delay_s`

- [ ] **Step 1: Write the failing tests**, with a fake runner that records commands and returns canned output.
  - `test_literal_escaping`: `literal('a"b\\c\nd\re') == '"a\\"b\\\\c\\nd\\re"'`
  - `test_script_checks_identity_count_service_members`: the script for 3 handles contains `number 9001`, `9002`, `9003`, `9004`, `is not 3` and every handle literal. The preflight script contains `return "READY"` and no `send `.
  - `test_parse_outcome`: `("SUBMITTED", 0)` gives `("sent", None)`. `NOT_SUBMITTED:9004` gives `("not_sent", 9004)`. `UNCERTAIN:-1712` gives `("ambiguous", -1712)`. `timed_out=True` gives `("ambiguous", None)`. A nonzero exit with empty output gives `("ambiguous", None)`.
  - `test_no_send_without_SEND`: `confirm` returns `"send"`, so the runner never sees `osascript` and the count stays the same.
  - `test_send_cap`: when `send-count` is 6, the probe refuses before confirming.
  - `test_ambiguous_is_not_retried`: the runner returns `UNCERTAIN:-1712`, so `osascript` is called exactly once and the count goes up by 1.
  - `test_tamper_changes_expected_set`
  - `test_pick_chat_requires_unique_match_and_prints_no_identifiers`: captured stdout contains none of the `SENTINELS`.
  - `test_report_has_no_sentinels`
- [ ] **Step 2: Run them and see them fail.** Expected: `ImportError`.
- [ ] **Step 3: Implement** both scripts and their `main()`s.
  - `send_probe.py` takes `--target {group,one_to_one}`, `--label`, `--preflight`, `--tamper`, `--id-prefix`, and `--db`.
  - `pick_chat.py` takes `--kind {group,one_to_one}`, `--name-contains`, `--handle`, and `--db`.
- [ ] **Step 4: Run the full Linux gate.** Expected: OK.
- [ ] **Step 5: Commit** "Add spikes (c)/(d): identity-checked group send probe".

### Task 6: Spike (e): reaching HomeChat through Cloudflare

**Files:** Create `companion/spikes/reach.py`; Test `scripts/tests/test_companion_reach.py`

**Interfaces:**
- Produces: `probe_reach(url: str, timeout_s: float = 10.0, opener=None, clock=time.monotonic) -> dict`.
- It does a GET with `User-Agent: msgblast-imessage-spike/0` and doesn't follow redirects.

Report keys:
- `status` (int or null)
- `error_kind`: `ok`, `http`, `dns`, `tls`, `timeout` or `other`
- `cf_ray` (bool)
- `access_redirect` (bool): a 3xx whose `Location` host ends with `cloudflareaccess.com`
- `server_kind`: `cloudflare`, `caddy`, `other` or `none`
- `elapsed_ms`

The URL comes from `config["homechat_probe_url"]` and never appears in the report.

- [ ] **Step 1: Write the failing tests**, with a fake opener.
  - A 200 response with `server: cloudflare` and a `cf-ray` header gives `ok`, `cf_ray=True` and `server_kind=cloudflare`.
  - An `HTTPError` 302 to `https://team.cloudflareaccess.com/...` gives `access_redirect=True`.
  - `URLError(socket.timeout())` gives `timeout`; `URLError(ssl.SSLError())` gives `tls`; a `gaierror` gives `dns`.
  - `test_report_has_no_url`
- [ ] **Step 2: Run them and see them fail.** Expected: `ImportError`.
- [ ] **Step 3: Implement** `probe_reach` and `main()`. The CLI has `--config`, and the report name is `reach`.
- [ ] **Step 4: Run the full Linux gate.** Expected: OK.
- [ ] **Step 5: Commit** "Add spike (e): HomeChat reachability probe".

### Task 7: The fork's own app, and spike (g): signing check

**Files:**
- Create: `companion/build_fork_app.py`, `companion/spikes/sign_check.py`
- Modify: `FORK.md` (the "Since" list: `companion/` holds fork-only tools)
- Test: `scripts/tests/test_companion_fork_app.py`

**Interfaces:**
- Consumes: upstream `scripts/preview_apps.py` (`VARIANTS`, `configure_info`, `verify_configured_info`, `copy_workspace`) and `scripts/build_preview_apps.py` (`package_variant`, `signing_order`, `is_mach_o`, `bundle_executable`). Both are loaded with `scripts/` on `sys.path`, because `build_preview_apps` does `import preview_apps as preview`.
- Produces:
  - `FORK_VARIANT: dict` equals `{**preview.VARIANTS["development"], "id": "imessage", "label": "iMessage companion fork", "app_name": "msgblast iMessage.app", "bundle_id": "io.github.goldalex98.msgblast-imessage", "bundle_name": "msgblast iMessage", "display_name": "msgblast iMessage", "icon_name": "AppIconDemo", "icon_source": preview.BLUE, "replace_app_icon": False, "support_directory": "msgblast-iMessage", "artifact_prefix": "msgblast-imessage"}`.
    - It takes the blue `AppIconDemo` artwork because `preview.expected_icon_color` expects blue-green only for the variant ID `development` (`scripts/preview_apps.py:140-141`).
    - `demo` and `fixture` stay `False`, so this is a live app with its own support folder, not Demo mode.
  - `FORK_IDENTITY = "msgblast-imessage local signing"`
  - `resign_commands(app: Path, entitlements: Path, identity: str, nested: list[Path], executable: Path) -> list[list[str]]`: the same flags and order as upstream's `sign_bundle` minus `--timestamp` (offline, self-signed), with `--preserve-metadata=entitlements` on already-signed nested items. It ends with the outer app signed with `--entitlements`, then `codesign --verify --deep --strict --verbose=2`.
  - `main()`: `--sha` and `--output`. It copies the workspace, runs `package_variant(workspace, FORK_VARIANT, sha, output)` (ad-hoc), re-signs with `FORK_IDENTITY` using `msgblast/msgblastDebug.entitlements`, and deletes the stale ad-hoc zip.
  - `sign_check.py` provides `signature_facts(app: Path, runner) -> dict`. It reads `codesign -dv --verbose=4` and `codesign -d -r-` and returns `{"identifier_ok", "authority_is_fork_identity", "requirement_uses_cdhash", "requirement_sha256"}`.
  - The `sign_check.py` CLI has `record --app --label --fda {yes,no} --automation {yes,no}` and `compare <report-a> <report-b>`. `compare` writes `{"same_requirement", "grants_kept"}`.

- [ ] **Step 1: Write the failing tests.**
  - `test_fork_variant_info`: `configure_info(plistlib.load(open("msgblast/Info.plist","rb")), FORK_VARIANT, "0"*40)` passes `verify_configured_info`. It also checks `CFBundleIdentifier == "io.github.goldalex98.msgblast-imessage"`; `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate` and `SUAllowsAutomaticUpdates` all `False`; `msgblastDisableUpdates` `True`; `SUFeedURL == ""`; and `msgblastSupportDirectory == "msgblast-iMessage"`.
  - `test_fork_identity_is_not_upstream`: the bundle ID is not in `{"com.msgblast.mac", "com.msgblast.development", "com.msgblast.demo"}`, and the support folder starts with `msgblast-`.
  - `test_resign_commands`: there is no `--timestamp`; the identity appears in every sign command; the outer app is last before verify and carries `--entitlements`.
  - `test_signature_facts`:
    - canned `codesign` output with `designated => identifier "io.github.goldalex98.msgblast-imessage" and certificate leaf = H"ab12"` gives `requirement_uses_cdhash=False`;
    - output with `cdhash H"..."` gives `True`;
    - `Authority=msgblast-imessage local signing` gives `authority_is_fork_identity=True`.
- [ ] **Step 2: Run them and see them fail.** Expected: `ImportError`.
- [ ] **Step 3: Implement** both files and add the `companion/` line to `FORK.md`.
- [ ] **Step 4: Run the full Linux gate.** Expected: OK.
- [ ] **Step 5: Commit, review, PR.** Commit "Add the fork app build and spike (g) signing check". Run `send-safety-reviewer` on `git diff main...HEAD` and fix every Critical. Update `.claude/STATUS.md`. Push `spikes/phase0`, then `gh pr create --repo Goldalex98/msgblast-imessage`. Merge only after Alex's yes.

### Task 8: Mac setup and the read-only runs, (a), (b) and (f awake) (on the MacBook)

- [ ] **Step 1: Clone the fork and record the versions.**
  - `git clone https://github.com/Goldalex98/msgblast-imessage.git ~/dev/msgblast-imessage`
  - `git -C ~/dev/msgblast-imessage config user.email 88671489+Goldalex98@users.noreply.github.com`
  - `git remote add upstream https://github.com/mgalpert/msgblast.git && git remote set-url --push upstream DISABLED-no-push-to-upstream`
  - `gh repo set-default Goldalex98/msgblast-imessage`
  - Run the two remote commands from inside the clone: `cd ~/dev/msgblast-imessage` first.
  - Record `sw_vers -productVersion`, `xcodebuild -version`, `uname -m` and `/usr/bin/python3 --version` in STATUS EVIDENCE.
  - Stop if Xcode 27 is missing, or if `uname -m` isn't `arm64`: upstream's builder pins `platform=macOS,arch=arm64`.
- [ ] **Step 2: Trust the folder.** Alex sets `hasTrustDialogAccepted` to true for the Mac path in `~/.claude.json`; it's a security setting, so it's his to change. Then run the `quality-gate` agent. Expected: both gate steps pass, and the headless run's stderr has no "not been trusted" warning.
- [ ] **Step 3: Alex grants permissions.** Alex gives Terminal Full Disk Access, then runs `python3 -I companion/spikes/bodies.py` and `python3 -I companion/spikes/groups.py`. Expected: each prints one report path; a missing Full Disk Access prints the hint and exits 2.
- [ ] **Step 4: Alex runs the awake sync test.** He starts `python3 -I companion/spikes/sync_watch.py --label awake --minutes 10`, then sends 3 texts from his iPhone to the test contact. Expected: 3 events.
- [ ] **Step 5: Claude reads the three reports** and writes the verdicts to `docs/superpowers/spikes/2026-11-phase0-results.md` (percentages only).

### Task 9: Spike (g): permission grants across rebuilds (on the MacBook)

- [ ] **Step 1: Make the certificate.** In Keychain Access, choose Certificate Assistant > Create a Certificate. Name it `msgblast-imessage local signing`, with Identity Type Self Signed Root and Certificate Type Code Signing. Then set its Trust to Code Signing: Always Trust.
  Check: `security find-identity -p codesigning` lists it.
- [ ] **Step 2: Build and install.**
  - Run `python3 -I companion/build_fork_app.py --sha $(git rev-parse HEAD) --output ~/msgblast-imessage-builds`.
  - Run `ditto "$HOME/msgblast-imessage-builds/msgblast iMessage.app" "/Applications/msgblast iMessage.app"`.
  - Open it. Alex grants Full Disk Access and Automation → Messages through the app's own prompts (`msgblast/Permissions/AppPermissions.swift`).
  - Run `python3 -I companion/spikes/sign_check.py record --app "/Applications/msgblast iMessage.app" --label build1 --fda yes --automation yes`.
  - Expected: `requirement_uses_cdhash=false`.
- [ ] **Step 3: Rebuild after a new commit** (any docs commit), reinstall over the old copy, and open the app. Alex reads the app's permission screen, then runs `sign_check.py record --app "/Applications/msgblast iMessage.app" --label build2 ...` and `sign_check.py compare` on the two reports.
  Expected for a pass: `same_requirement=true`, `grants_kept=true`.
  If it fails, repeat with Xcode's free Personal Team signing (spec §10.4). If that fails too, record it and stop; paying for the Developer Program is Alex's call.

### Task 10: Spikes (c) and (d): real sends, only with Alex's yes typed in chat for this task

- [ ] **Step 1: Prepare the targets.** Alex creates a test group: himself plus two test contacts, because a group needs at least two others. He then runs `pick_chat.py --kind group --name-contains "<group name>"` and `pick_chat.py --kind one_to_one --handle "<test contact>"` in his Terminal.
- [ ] **Step 2: Run the preflights** (no sends): `send_probe.py --target one_to_one --label pre1 --preflight`, and the same for `--target group`.
  Expected: `ready`. If Messages rejects the chat ID (`not_sent`, code -1728), retry with `--id-prefix any`.
- [ ] **Step 3: Run the real sends** (3 of the 6 allowed):
  - `c1`: 1:1, with Messages open in the background.
  - `c2`: group, with Messages open in the background.
  - `c3`: group, with Messages quit first.
  Expected for each: `sent`, `anchor_rows == 1`. The test contacts confirm that each message arrived once.
- [ ] **Step 4: Run the tampered check:** `--target group --label c4 --tamper`, no preflight. Expected: `not_sent` with 9002 or 9004, and the group receives nothing.
- [ ] **Step 5: Spike (d) verdict.** It comes from `frontmost_before/after` and `messages_running_before/after` across c1–c3. A pass means Terminal stays frontmost.

### Task 11: Spike (e), (f) asleep, results and next plans

- [ ] **Step 1: Spike (e), preliminary.** Alex puts the HomeChat edge hostname's root URL in `config["homechat_probe_url"]` and runs `reach.py`. This records how the edge treats a non-Anthropic client.
  The full test needs a probe route on HomeChat. That is homechat-bot work under its own rules: queue it there; pre-approved after 4b, spec §9.
- [ ] **Step 2: Spike (f), asleep.** Alex starts `sync_watch.py --label asleep --minutes 20`, closes the lid, sends 2 iPhone texts, waits 5 minutes, then opens the lid. Expected: `sleeps_detected ≥ 1` and two events with `since_resume_s`.
- [ ] **Step 3: Complete the results doc.** Give each spike its question, number, verdict and the phase 1 decision it drives:
  - decoder: port as-is, or use `NSUnarchiver`;
  - group sends: go or no-go (spec §10.8);
  - signing method;
  - uplink path;
  - the 24 h "replied on your phone?" fallback needed or not (spec §10.1).
- [ ] **Step 4: Wrap up phase 0.** Alex revokes Terminal's Full Disk Access and Automation. Update STATUS and LOG, PR the results, then write the phase 1 plan.

## Later plans (written after phase 0, from its results)

- **Phase 1, Mac side (this repo):**
  - the group-aware reader and `attributedBody` decoder (Swift, in new files), with a persisted global ROWID cursor;
  - the scrubber;
  - the uplink client (Keychain token, local config);
  - the status pane;
  - the first run limited to 3 days.
  The interface contract (spec §4.2) is fixed first as `docs/superpowers/specs/<date>-imsg-uplink-contract.md`, agreed with HomeChat's amendment.
- **HomeChat side (homechat-bot):** its design amendment, `CLAUDE.md` exception, plan and code (spec §9). It runs there under its own rules, not from this repo.
- **Phase 3, Mac side:** the send executor (expiry, identity re-check, no retry, anchor), reusing the Task 5 script once spike (c) passes.
- **Phase 2 (calendar) and phase 4 (Duet tools):** HomeChat only.

"""Spikes (c) and (d): an identity-checked AppleScript send to a test chat, and whether it steals focus.

Run on the Mac by Alex only, after pick_chat.py has written the targets:
  python3 -I companion/spikes/send_probe.py --target group --label pre1 --preflight
  python3 -I companion/spikes/send_probe.py --target group --label c2
A real send needs SEND typed at the prompt, and phase 0 allows at most 6 of them.
An ambiguous outcome is never retried. Prints only the path of a counts-only report in .local/spikes/.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402

SEND_CAP = 6
DEFAULT_COUNT = spikelib.DEFAULT_OUT / "send-count"
BLOCK_NAME = "send-blocked"
TAMPER_HANDLE = "tamper@example.invalid"
TARGETS = ("group", "one_to_one")
LABEL_RE = re.compile(r"^[a-z0-9]{1,16}$")
OSASCRIPT_TIMEOUT_S = 35
ALLOWED = frozenset(TARGETS) | frozenset({"sent", "ready", "not_sent", "ambiguous",
                                         "messages", "terminal", "other", "unknown"})

Runner = Callable[..., Tuple[int, str, bool]]


def run_command(args: List[str], stdin: Optional[str] = None, timeout: float = 10.0) -> Tuple[int, str, bool]:
    """Returns (exit code, stdout, timed out). Never raises for a missing tool or a timeout."""
    try:
        done = subprocess.run(args, input=stdin, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return (-1, "", True)
    except OSError:
        return (127, "", False)
    return (done.returncode, done.stdout, False)


def literal(value: str) -> str:
    """AppleScript string literal, escaped exactly as msgblast/Core/MessagesSendScript.swift:35-37."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")
    return '"' + escaped + '"'


def build_send_script(chat_id: str, expected_handles: List[str], text: str, preflight_only: bool,
                      timeout_s: int = 20) -> str:
    members = ", ".join(literal(h) for h in expected_handles)
    if preflight_only:
        command = 'return "READY"'
    else:
        command = ("set submissionAttempted to true\n"
                   f"      send {literal(text)} to targetChat\n"
                   '      return "SUBMITTED"')
    return f"""set submissionAttempted to false
try
  with timeout of {timeout_s} seconds
    tell application "Messages"
      set targetChat to chat id {literal(chat_id)}
      if (id of targetChat as text) is not {literal(chat_id)} then error "identity" number 9001
      if service type of account of targetChat is not iMessage then error "service" number 9003
      set seen to {{}}
      repeat with p in participants of targetChat
        set end of seen to (handle of p as text)
      end repeat
      if (count of seen) is not {len(expected_handles)} then error "count" number 9002
      repeat with h in {{{members}}}
        if seen does not contain (h as text) then error "member" number 9004
      end repeat
      {command}
    end tell
  end timeout
on error detail number code
  if submissionAttempted then return "UNCERTAIN:" & code
  return "NOT_SUBMITTED:" & code
end try
"""


def _code(value: str) -> Optional[int]:
    try:
        return int(value.strip())
    except ValueError:
        return None


def parse_outcome(returncode: int, stdout: str, timed_out: bool) -> Tuple[str, Optional[int]]:
    """Same rule as msgblast/Messages/MessageSender.swift:63-72: anything not clearly decided is ambiguous."""
    if timed_out or returncode != 0:
        return ("ambiguous", None)
    lines = stdout.strip().splitlines()
    first = lines[0].strip() if lines else ""
    if first == "SUBMITTED":
        return ("sent", None)
    if first == "READY":
        return ("ready", None)
    if first.startswith("NOT_SUBMITTED:"):
        return ("not_sent", _code(first[len("NOT_SUBMITTED:"):]))
    if first.startswith("UNCERTAIN:"):
        return ("ambiguous", _code(first[len("UNCERTAIN:"):]))
    return ("ambiguous", None)


def frontmost(runner: Runner) -> str:
    code, out, timed_out = runner(["/bin/sh", "-c", 'lsappinfo info -only name "$(lsappinfo front)"'], timeout=5)
    match = re.search(r'="([^"]*)"', out or "")
    if code != 0 or timed_out or not match:
        return "unknown"
    name = match.group(1)
    if name == "Messages":
        return "messages"
    if name in ("Terminal", "iTerm2", "iTerm"):
        return "terminal"
    return "other"


def messages_running(runner: Runner) -> bool:
    code, _, timed_out = runner(["pgrep", "-x", "Messages"], timeout=5)
    return code == 0 and not timed_out


def find_anchor(db_path: str, chat_id: str, text: str, attempted_unix: float, wait_s: float = 30.0,
                clock: Callable[[], float] = time.time, sleep: Callable[[float], None] = time.sleep) -> dict:
    """Counts outgoing rows in the chat with this exact text dated at or after attempted - 2 s
    (msgblast/Core/Routing.swift:63-76). Watches the whole window so a duplicate shows up as rows > 1."""
    conn = spikelib.open_ro(db_path)
    cutoff = attempted_unix - 2 - spikelib.APPLE_EPOCH_UNIX
    query = ("SELECT COUNT(*) FROM message m JOIN chat_message_join cm ON cm.message_id = m.ROWID"
             " JOIN chat c ON c.ROWID = cm.chat_id"
             f" WHERE c.guid = ? AND m.is_from_me = 1 AND m.text = ? AND {spikelib.APPLE_SECONDS_SQL} >= ?")
    deadline = clock() + wait_s
    rows, delay = 0, None
    while True:
        rows = conn.execute(query, (chat_id, text, cutoff)).fetchone()[0]
        if rows and delay is None:
            delay = clock() - attempted_unix
        if clock() >= deadline:
            break
        sleep(1.0)
    conn.close()
    return {"rows": rows, "delay_s": delay}


def read_count(path: Path) -> int:
    try:
        return int(Path(path).read_text().strip() or "0")
    except FileNotFoundError:
        return 0


def write_count(path: Path, value: int) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as file:
        file.write(f"{value}\n")


def blocked_path(count_path: Path) -> Path:
    """Marker beside the counter: present while a send's outcome is unknown, so it is never repeated."""
    return Path(count_path).parent / BLOCK_NAME


def _with_prefix(chat_id: str, id_prefix: Optional[str]) -> str:
    if not id_prefix:
        return chat_id
    _, sep, rest = chat_id.partition(";")
    return id_prefix + sep + rest if sep else chat_id


def run_probe(config: dict, target: str, label: str, preflight_only: bool, tamper: bool, id_prefix: Optional[str],
              runner: Runner = run_command, confirm: Callable[[str], str] = input,
              db_path: str = spikelib.DEFAULT_DB, clock: Callable[[], float] = time.time,
              sleep: Callable[[float], None] = time.sleep, count_path: Optional[Path] = None) -> dict:
    if target not in TARGETS:
        raise spikelib.ProbeError(4, "--target must be group or one_to_one")
    if not LABEL_RE.match(label or ""):
        raise spikelib.ProbeError(4, "--label must be 1-16 lowercase letters or digits")
    entry = config.get(target)
    if not entry or not entry.get("chat_id") or not entry.get("handles"):
        raise spikelib.ProbeError(3, f"No {target} target in config: run pick_chat.py --kind {target} first.")
    count_file = Path(count_path) if count_path else DEFAULT_COUNT
    count = read_count(count_file)
    if not preflight_only and count >= SEND_CAP:
        raise spikelib.ProbeError(5, f"Phase 0 send cap reached ({SEND_CAP}); nothing sent.")
    block = blocked_path(count_file)
    if not preflight_only and block.exists():
        raise spikelib.ProbeError(7, "An earlier send's outcome is unknown, so no new send runs. Check with the "
                                     f"test contacts, then delete .local/spikes/{BLOCK_NAME} yourself.")
    if not preflight_only:
        spikelib.open_ro(db_path).close()  # without chat.db access the send could not be checked afterwards

    handles = list(entry["handles"])
    if tamper:
        handles[-1] = TAMPER_HANDLE
    chat_id = entry["chat_id"]
    text = f"msgblast-imessage spike {label} {time.strftime('%H%M%S', time.localtime(clock()))}"
    script = build_send_script(_with_prefix(chat_id, id_prefix), handles, text, preflight_only)

    mode = "preflight (no send)" if preflight_only else f"SEND {count + 1} of {SEND_CAP}"
    print(f"{label}: {mode} to the {target} target, {len(handles)} expected participants"
          f"{', tampered' if tamper else ''}")
    if not preflight_only and confirm("Type SEND to send this one test message: ").strip() != "SEND":
        raise spikelib.ProbeError(6, "Not confirmed; nothing sent.")

    front_before, running_before = frontmost(runner), messages_running(runner)
    if not preflight_only:
        write_count(count_file, count + 1)  # reserved before the send, so an interrupt still counts it
        write_count(block, 1)
    attempted = clock()
    returncode, stdout, timed_out = runner(["osascript", "-"], stdin=script, timeout=OSASCRIPT_TIMEOUT_S)
    elapsed_ms = int(round((clock() - attempted) * 1000))
    outcome, code = parse_outcome(returncode, stdout, timed_out)
    front_after, running_after = frontmost(runner), messages_running(runner)

    if not preflight_only:
        if outcome == "not_sent":
            write_count(count_file, count)  # Messages refused before submitting: release the reservation
        if outcome != "ambiguous":
            block.unlink()
    print(f"outcome: {outcome}" + ("  (ambiguous: do NOT resend)" if outcome == "ambiguous" else ""))

    anchor = {"rows": None, "delay_s": None}
    if not preflight_only and outcome in ("sent", "ambiguous"):
        print("Watching chat.db for 30 s to count copies of the message...")
        try:
            anchor = find_anchor(db_path, chat_id, text, attempted, clock=clock, sleep=sleep)
        except Exception:  # noqa: BLE001 - the send already happened; still write the report
            anchor = {"rows": None, "delay_s": None}
    return {
        "label": label, "target": target, "preflight_only": preflight_only, "tamper": tamper,
        "outcome": outcome, "code": code, "elapsed_ms": elapsed_ms,
        "frontmost_before": front_before, "frontmost_after": front_after,
        "messages_running_before": running_before, "messages_running_after": running_after,
        "anchor_rows": anchor["rows"], "anchor_delay_s": anchor["delay_s"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", required=True, choices=TARGETS)
    parser.add_argument("--label", required=True)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--tamper", action="store_true")
    parser.add_argument("--id-prefix", default=None)
    parser.add_argument("--db", default=spikelib.DEFAULT_DB)
    args = parser.parse_args()
    report = run_probe(spikelib.load_config(), args.target, args.label, args.preflight, args.tamper,
                       args.id_prefix, db_path=args.db)
    print(spikelib.write_report(f"send-{args.label}", report, ALLOWED | {args.label}))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

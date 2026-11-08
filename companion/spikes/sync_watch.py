"""Spike (f): how long a message sent from the iPhone takes to appear in the Mac's chat.db.

Run on the Mac by Alex:  python3 -I companion/spikes/sync_watch.py --label awake [--minutes 30]
Then send a few texts from the iPhone. Prints only the path of a counts-only report in .local/spikes/.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Callable, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402

LABELS = frozenset({"awake", "asleep"})
SERVICES = {"imessage": "imessage", "sms": "sms"}
ALLOWED = LABELS | frozenset({"imessage", "sms", "other"})


def _max_rowid(conn) -> int:
    return conn.execute("SELECT COALESCE(MAX(ROWID), 0) FROM message").fetchone()[0]


def _data_version(conn) -> int:
    return conn.execute("PRAGMA data_version").fetchone()[0]


def watch(db_path: str, label: str, poll_s: float = 2.0, max_minutes: float = 30.0,
          clock: Callable[[], float] = time.time, sleep: Callable[[float], None] = time.sleep,
          max_polls: Optional[int] = None) -> dict:
    if label not in LABELS:
        raise spikelib.ProbeError(4, "--label must be awake or asleep")
    conn = spikelib.open_ro(db_path)
    start = last_poll = clock()
    last_rowid = _max_rowid(conn)
    version = _data_version(conn)
    resume_at: Optional[float] = None
    events = []
    sleeps = 0
    polls = 0
    while (max_polls is None or polls < max_polls) and clock() - start < max_minutes * 60:
        sleep(poll_s)
        polls += 1
        now = clock()
        if now - last_poll > 3 * poll_s:
            sleeps += 1
            resume_at = now
        last_poll = now
        current = _data_version(conn)
        if current == version:
            continue
        version = current
        rows = conn.execute(
            "SELECT ROWID, is_from_me, COALESCE(date, 0), LOWER(COALESCE(service, '')) FROM message"
            " WHERE ROWID > ? ORDER BY ROWID", (last_rowid,)).fetchall()
        for rowid, is_from_me, raw_date, service in rows:
            last_rowid = max(last_rowid, rowid)
            if not is_from_me or not raw_date:
                continue
            events.append({
                "delay_s": now - spikelib.unix_time(raw_date),
                "since_resume_s": None if resume_at is None else now - resume_at,
                "service": SERVICES.get(service, "other"),
            })
    return {"label": label, "poll_s": poll_s, "events": events, "sleeps_detected": sleeps,
            "duration_s": clock() - start}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=spikelib.DEFAULT_DB)
    parser.add_argument("--label", required=True, choices=sorted(LABELS))
    parser.add_argument("--minutes", type=float, default=30.0)
    args = parser.parse_args()
    report = watch(args.db, args.label, max_minutes=args.minutes)
    print(spikelib.write_report(f"sync-{args.label}", report, ALLOWED))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

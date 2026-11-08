from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))

import companion_fixture as fx  # noqa: E402
import spikelib  # noqa: E402
import sync_watch  # noqa: E402

START = 2_000_000_000.0


class FakeTime:
    """clock/sleep pair: each sleep advances time (by a scheduled step) and may write rows from 'another device'."""

    def __init__(self, db: Path, steps=None, writes=None):
        self.t = START
        self.db = db
        self.steps = steps or {}
        self.writes = writes or {}
        self.polls = 0

    def clock(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.polls += 1
        self.t += self.steps.get(self.polls, seconds)
        write = self.writes.get(self.polls)
        if write:
            conn = sqlite3.connect(str(self.db))
            write(conn, self.t)
            conn.commit()
            conn.close()


class SyncWatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "chat.db"
        fx.build_chat_db(self.db, wal=True)
        fx.seed_standard(self.db, now_unix=START)
        conn = sqlite3.connect(str(self.db))
        self.chat = conn.execute("SELECT ROWID FROM chat WHERE style = 45").fetchone()[0]
        conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def run_watch(self, fake: FakeTime, polls: int) -> dict:
        return sync_watch.watch(str(self.db), "awake", poll_s=2.0, clock=fake.clock, sleep=fake.sleep,
                                max_polls=polls)

    def test_reports_delay_for_new_outgoing_row(self):
        fake = FakeTime(self.db, writes={1: lambda c, t: fx.add_message(c, self.chat, t - 5, text=fx.SENTINEL_TEXT,
                                                                       is_from_me=True)})
        report = self.run_watch(fake, polls=2)
        self.assertEqual(len(report["events"]), 1)
        self.assertAlmostEqual(report["events"][0]["delay_s"], 5.0, places=3)
        self.assertIsNone(report["events"][0]["since_resume_s"])
        self.assertEqual(report["events"][0]["service"], "imessage")
        self.assertEqual(report["sleeps_detected"], 0)

    def test_ignores_inbound_and_preexisting_rows(self):
        fake = FakeTime(self.db, writes={1: lambda c, t: fx.add_message(c, self.chat, t - 1, text=fx.SENTINEL_TEXT,
                                                                       sender=fx.SENTINEL_EMAIL)})
        report = self.run_watch(fake, polls=2)
        self.assertEqual(report["events"], [])

    def test_detects_sleep_gap(self):
        fake = FakeTime(self.db, steps={2: 600.0},
                        writes={2: lambda c, t: fx.add_message(c, self.chat, t - 610, text=fx.SENTINEL_TEXT,
                                                               is_from_me=True)})
        report = self.run_watch(fake, polls=3)
        self.assertEqual(report["sleeps_detected"], 1)
        self.assertEqual(len(report["events"]), 1)
        self.assertAlmostEqual(report["events"][0]["since_resume_s"], 0.0, places=3)
        self.assertAlmostEqual(report["events"][0]["delay_s"], 610.0, places=3)

    def test_report_has_no_sentinels(self):
        fake = FakeTime(self.db, writes={1: lambda c, t: fx.add_message(c, self.chat, t - 5, text=fx.SENTINEL_TEXT,
                                                                       is_from_me=True)})
        report = self.run_watch(fake, polls=2)
        dumped = json.dumps(report)
        for sentinel in fx.SENTINELS:
            self.assertNotIn(sentinel, dumped)
        spikelib.assert_counts_only(report, sync_watch.ALLOWED)

    def test_rejects_unknown_label(self):
        with self.assertRaises(spikelib.ProbeError):
            sync_watch.watch(str(self.db), "lunch", max_polls=0)


if __name__ == "__main__":
    unittest.main()

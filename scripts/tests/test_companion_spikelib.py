from __future__ import annotations

import os
import re
import sqlite3
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))

import companion_fixture as fx  # noqa: E402
import spikelib  # noqa: E402


class SpikeLibTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.db = self.dir / "chat.db"

    def tearDown(self):
        os.chmod(self.db, 0o600) if self.db.exists() else None
        self.tmp.cleanup()

    def test_open_ro_rejects_writes(self):
        fx.build_chat_db(self.db)
        conn = spikelib.open_ro(str(self.db))
        with self.assertRaises(sqlite3.OperationalError):
            conn.execute("INSERT INTO handle(id) VALUES ('x')")

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root ignores file modes")
    def test_open_ro_missing_permission_exits_2(self):
        fx.build_chat_db(self.db)
        os.chmod(self.db, 0)
        with self.assertRaises(spikelib.ProbeError) as caught:
            spikelib.open_ro(str(self.db))
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(str(caught.exception), spikelib.FDA_HINT)

    def test_open_ro_reads_committed_rows_during_open_write(self):
        fx.build_chat_db(self.db, wal=True)
        fx.seed_standard(self.db)
        writer = sqlite3.connect(str(self.db), isolation_level=None)
        writer.execute("BEGIN IMMEDIATE")
        writer.execute("INSERT INTO handle(id) VALUES ('uncommitted')")
        try:
            started = time.monotonic()
            conn = spikelib.open_ro(str(self.db))
            count = conn.execute("SELECT COUNT(*) FROM message").fetchone()[0]
            self.assertLess(time.monotonic() - started, 2.0)
            self.assertEqual(count, 6)
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM handle WHERE id='uncommitted'").fetchone()[0], 0)
        finally:
            writer.execute("ROLLBACK")
            writer.close()

    def test_apple_time_units(self):
        self.assertEqual(spikelib.apple_seconds(810000000000000000), 810000000.0)
        self.assertEqual(spikelib.apple_seconds(810000000), 810000000.0)
        self.assertEqual(spikelib.unix_time(0), 978307200.0)

    def test_assert_counts_only(self):
        spikelib.assert_counts_only({"a": 1, "b": {"c": True, "d": None, "e": 0.5}, "f": "sent"}, frozenset({"sent"}))
        with self.assertRaises(ValueError) as caught:
            spikelib.assert_counts_only({"f": "leaked-value"}, frozenset({"sent"}))
        self.assertIn("f", str(caught.exception))
        self.assertNotIn("leaked-value", str(caught.exception))
        with self.assertRaises(ValueError):
            spikelib.assert_counts_only({"events": [1, "leak"]}, frozenset())

    def test_write_report_mode_and_name(self):
        path = spikelib.write_report("bodies", {"total": 3}, frozenset(), out_dir=self.dir / "out")
        self.assertRegex(path.name, r"^bodies-\d{8}T\d{6}Z\.json$")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()

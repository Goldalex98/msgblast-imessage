from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))

import companion_fixture as fx  # noqa: E402
import bodies  # noqa: E402
import spikelib  # noqa: E402

SUFFIX_LEN = 25  # bytes make_attributed_body appends after the string payload


class DecodeTests(unittest.TestCase):
    def test_decode_round_trip(self):
        for text in ("hi", "x" * 200, "y" * 70000, "café 👋"):
            self.assertEqual(bodies.decode_attributed_body(fx.make_attributed_body(text)), text)

    def test_decode_bad_input_returns_none(self):
        good = fx.make_attributed_body("hello world")
        bad_utf8 = good.replace("hello world".encode(), b"\xff\xfe" + b"x" * 9)
        for blob in (None, b"", b"streamtyped without the class", good[: -(SUFFIX_LEN + 3)], bad_utf8):
            self.assertIsNone(bodies.decode_attributed_body(blob))


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "chat.db"
        self.now = time.time()
        fx.build_chat_db(self.db)
        fx.seed_standard(self.db, now_unix=self.now)
        conn = sqlite3.connect(str(self.db))
        chat = conn.execute("SELECT ROWID FROM chat WHERE style = 45").fetchone()[0]
        fx.add_message(conn, chat, self.now - 60, attributed=fx.make_attributed_body(fx.SENTINEL_TEXT),
                       sender=fx.SENTINEL_EMAIL)
        fx.add_message(conn, chat, self.now - 50,
                       attributed=fx.make_attributed_body(fx.SENTINEL_TEXT)[: -(SUFFIX_LEN + 3)],
                       sender=fx.SENTINEL_EMAIL)
        fx.add_message(conn, chat, self.now - 40, has_attachment=True, sender=fx.SENTINEL_EMAIL)
        fx.add_message(conn, chat, self.now - 30, text=fx.SENTINEL_TEXT,
                       attributed=fx.make_attributed_body(fx.SENTINEL_TEXT), is_from_me=True)
        conn.commit()
        conn.close()
        self.report = bodies.probe_bodies(spikelib.open_ro(str(self.db)), days=14, now_unix=self.now)

    def tearDown(self):
        self.tmp.cleanup()

    def test_probe_counts_on_fixture(self):
        self.assertEqual(self.report, {
            "total": 8, "text_present": 5,
            "attributed_only": 2, "attributed_only_decoded": 1, "attributed_only_failed": 1,
            "neither": 1, "neither_with_attachment": 1,
            "cross_check_total": 1, "cross_check_equal": 1,
        })

    def test_report_has_no_sentinels(self):
        dumped = json.dumps(self.report)
        for sentinel in fx.SENTINELS:
            self.assertNotIn(sentinel, dumped)
        spikelib.assert_counts_only(self.report, frozenset())


if __name__ == "__main__":
    unittest.main()

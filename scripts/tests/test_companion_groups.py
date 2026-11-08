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
import groups  # noqa: E402
import spikelib  # noqa: E402


class GroupProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "chat.db"
        now = time.time()
        fx.build_chat_db(self.db)
        fx.seed_standard(self.db, now_unix=now)
        conn = sqlite3.connect(str(self.db))
        group = conn.execute("SELECT ROWID FROM chat WHERE style = 43").fetchone()[0]
        fx.add_message(conn, group, now - 120, text=fx.SENTINEL_TEXT, reply_to="msg-anchor")  # handle_id 0
        fx.add_chat(conn, "iMessage;-;odd", 45, [fx.SENTINEL_PHONE, fx.SENTINEL_PHONE_2])
        conn.commit()
        conn.close()
        self.report = groups.probe_groups(spikelib.open_ro(str(self.db)), days=14, now_unix=now)

    def tearDown(self):
        self.tmp.cleanup()

    def test_counts_on_fixture(self):
        self.assertEqual(self.report, {
            "chats_by_style": {"group_43": 1, "one_to_one_45": 2, "other": 0},
            "style_count_mismatch": 1,
            "groups_active": 1,
            "participants": {"p2": 0, "p3": 1, "p4_6": 0, "p7_plus": 0},
            "group_inbound": 2,
            "group_inbound_with_sender": 1,
            "group_outgoing": 1,
            "group_with_reply_link": 1,
            "groups_with_display_name": 1,
        })

    def test_report_has_no_sentinels(self):
        dumped = json.dumps(self.report)
        for sentinel in fx.SENTINELS:
            self.assertNotIn(sentinel, dumped)
        spikelib.assert_counts_only(self.report, frozenset())


if __name__ == "__main__":
    unittest.main()

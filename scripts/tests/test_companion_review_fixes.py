from __future__ import annotations

import contextlib
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bodies  # noqa: E402
import companion_fixture as fx  # noqa: E402
import groups  # noqa: E402
import send_probe  # noqa: E402
import spikelib  # noqa: E402
from test_companion_send_probe import START, FakeClock, FakeRunner, GROUP_HANDLES  # noqa: E402


class NonUtf8Tests(unittest.TestCase):
    """Final review Important 1: undecodable TEXT must never put content into an error message."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "chat.db"
        fx.build_chat_db(self.db)
        fx.seed_standard(self.db, now_unix=START)
        conn = sqlite3.connect(str(self.db))
        group = conn.execute("SELECT ROWID FROM chat WHERE style = 43").fetchone()[0]
        bad = "CAST(x'ff" + fx.SENTINEL_TEXT.encode().hex() + "' AS TEXT)"
        conn.execute(f"UPDATE chat SET display_name = {bad} WHERE ROWID = ?", (group,))
        message = fx.add_message(conn, group, START - 60, text="placeholder", sender=fx.SENTINEL_PHONE)
        conn.execute(f"UPDATE message SET text = {bad} WHERE ROWID = ?", (message,))
        conn.commit()
        conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_probes_survive_non_utf8_text(self):
        report = bodies.probe_bodies(spikelib.open_ro(str(self.db)), now_unix=START)
        self.assertEqual(report["text_present"], 5)
        report = groups.probe_groups(spikelib.open_ro(str(self.db)), now_unix=START)
        self.assertEqual(report["groups_with_display_name"], 1)

    def test_run_main_hides_unexpected_error_text(self):
        def boom():
            raise RuntimeError(fx.SENTINEL_TEXT)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = spikelib.run_main(boom)
        self.assertEqual(code, 1)
        self.assertNotIn(fx.SENTINEL_TEXT, err.getvalue())
        self.assertIn("RuntimeError", err.getvalue())

    def test_decode_rejects_non_bytes(self):
        self.assertIsNone(bodies.decode_attributed_body("streamtyped NSString"))


class SendOrderingTests(unittest.TestCase):
    """Final review Important 2 and 3: a real send is always counted, reported, and never repeatable after ambiguous."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "chat.db"
        self.count = root / "send-count"
        fx.build_chat_db(self.db, wal=True)
        fx.seed_standard(self.db, now_unix=START)
        self.config = {"group": {"chat_id": fx.SENTINEL_GROUP_GUID, "handles": list(GROUP_HANDLES)}}
        self.clock = FakeClock()

    def tearDown(self):
        self.tmp.cleanup()

    def probe(self, runner, preflight=False, confirm=lambda prompt: "SEND", db=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return send_probe.run_probe(self.config, "group", "c2", preflight_only=preflight, tamper=False,
                                        id_prefix=None, runner=runner, confirm=confirm,
                                        db_path=str(db or self.db), clock=self.clock.clock,
                                        sleep=self.clock.sleep, count_path=self.count)

    def test_count_reserved_before_osascript(self):
        class Interrupting(FakeRunner):
            def __call__(inner, args, stdin=None, timeout=10.0):
                if args[0] == "osascript":
                    raise KeyboardInterrupt
                return super().__call__(args, stdin, timeout)
        with self.assertRaises(KeyboardInterrupt):
            self.probe(Interrupting())
        self.assertEqual(send_probe.read_count(self.count), 1)

    def test_unreadable_db_refuses_before_confirm(self):
        runner = FakeRunner()
        with self.assertRaises(spikelib.ProbeError) as caught:
            self.probe(runner, confirm=lambda prompt: self.fail("asked to confirm"), db=Path(self.tmp.name) / "missing.db")
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(runner.calls, [])
        self.assertEqual(send_probe.read_count(self.count), 0)

    def test_anchor_failure_still_reports(self):
        original = send_probe.find_anchor
        def failing(*args, **kwargs):
            raise spikelib.ProbeError(2, "gone")
        send_probe.find_anchor = failing
        try:
            report = self.probe(FakeRunner())
        finally:
            send_probe.find_anchor = original
        self.assertEqual(report["outcome"], "sent")
        self.assertIsNone(report["anchor_rows"])

    def test_ambiguous_blocks_later_real_sends(self):
        self.probe(FakeRunner(osascript=(0, "UNCERTAIN:-1712", False)))
        self.assertTrue(send_probe.blocked_path(self.count).exists())
        runner = FakeRunner()
        with self.assertRaises(spikelib.ProbeError):
            self.probe(runner, confirm=lambda prompt: self.fail("asked to confirm"))
        self.assertEqual(runner.osascript_calls(), [])
        report = self.probe(FakeRunner(osascript=(0, "READY", False)), preflight=True)
        self.assertEqual(report["outcome"], "ready")

    def test_not_sent_releases_reservation(self):
        report = self.probe(FakeRunner(osascript=(0, "NOT_SUBMITTED:9004", False)))
        self.assertEqual(report["outcome"], "not_sent")
        self.assertEqual(send_probe.read_count(self.count), 0)


if __name__ == "__main__":
    unittest.main()

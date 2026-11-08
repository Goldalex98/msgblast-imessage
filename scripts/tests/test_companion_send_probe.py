from __future__ import annotations

import contextlib
import io
import json
import re
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))

import companion_fixture as fx  # noqa: E402
import pick_chat  # noqa: E402
import send_probe  # noqa: E402
import spikelib  # noqa: E402

START = 2_000_000_000.0
GROUP_HANDLES = [fx.SENTINEL_EMAIL, fx.SENTINEL_PHONE, fx.SENTINEL_PHONE_2]


class FakeClock:
    def __init__(self):
        self.t = START

    def clock(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.t += seconds


class FakeRunner:
    """Records every command; osascript returns canned output and may 'deliver' the message into chat.db."""

    def __init__(self, osascript=(0, "SUBMITTED", False), deliver_to=None, clock=None):
        self.osascript = osascript
        self.deliver_to = deliver_to  # (db path, chat rowid) or None
        self.clock = clock
        self.calls = []

    def __call__(self, args, stdin=None, timeout=10.0):
        self.calls.append((list(args), stdin, timeout))
        if args[0] == "osascript":
            if self.deliver_to and "\nsend " in "\n" + "\n".join(line.strip() for line in stdin.splitlines()):
                text = re.search(r'send "(msgblast-imessage spike [^"]+)" to targetChat', stdin).group(1)
                conn = sqlite3.connect(str(self.deliver_to[0]))
                fx.add_message(conn, self.deliver_to[1], self.clock.t + 1, text=text, is_from_me=True)
                conn.commit()
                conn.close()
            return self.osascript
        if args[0] == "pgrep":
            return (0, "4242\n", False)
        return (0, '"LSDisplayName"="Terminal"\n', False)

    def osascript_calls(self):
        return [call for call in self.calls if call[0][0] == "osascript"]


class ScriptTests(unittest.TestCase):
    def test_literal_escaping(self):
        self.assertEqual(send_probe.literal('a"b\\c\nd\re'), '"a\\"b\\\\c\\nd\\re"')

    def test_script_checks_identity_count_service_members(self):
        handles = ["+15550000001", "x@example.invalid", "+15550000003"]
        script = send_probe.build_send_script("iMessage;+;chat1", handles, "hi", preflight_only=False)
        for needle in ("number 9001", "number 9002", "number 9003", "number 9004", "is not 3",
                       'chat id "iMessage;+;chat1"', 'send "hi" to targetChat', 'return "SUBMITTED"',
                       "with timeout of 20 seconds"):
            self.assertIn(needle, script)
        for handle in handles:
            self.assertIn(send_probe.literal(handle), script)
        preflight = send_probe.build_send_script("iMessage;+;chat1", handles, "hi", preflight_only=True)
        self.assertIn('return "READY"', preflight)
        self.assertNotIn("send ", preflight)
        self.assertNotIn("submissionAttempted to true", preflight)

    def test_parse_outcome(self):
        self.assertEqual(send_probe.parse_outcome(0, "SUBMITTED\n", False), ("sent", None))
        self.assertEqual(send_probe.parse_outcome(0, "READY", False), ("ready", None))
        self.assertEqual(send_probe.parse_outcome(0, "NOT_SUBMITTED:9004", False), ("not_sent", 9004))
        self.assertEqual(send_probe.parse_outcome(0, "UNCERTAIN:-1712", False), ("ambiguous", -1712))
        self.assertEqual(send_probe.parse_outcome(0, "SUBMITTED", True), ("ambiguous", None))
        self.assertEqual(send_probe.parse_outcome(1, "", False), ("ambiguous", None))
        self.assertEqual(send_probe.parse_outcome(0, "something else", False), ("ambiguous", None))

    def test_frontmost_and_running(self):
        def runner(output, code=0):
            return lambda args, stdin=None, timeout=10.0: (code, output, False)
        self.assertEqual(send_probe.frontmost(runner('"LSDisplayName"="Messages"\n')), "messages")
        self.assertEqual(send_probe.frontmost(runner('"LSDisplayName"="Terminal"\n')), "terminal")
        self.assertEqual(send_probe.frontmost(runner('"LSDisplayName"="Safari"\n')), "other")
        self.assertEqual(send_probe.frontmost(runner("", 1)), "unknown")
        self.assertTrue(send_probe.messages_running(runner("4242\n")))
        self.assertFalse(send_probe.messages_running(runner("", 1)))

    def test_frontmost_macos27_format(self):
        # macOS 27's lsappinfo prints the name first and a quoted bundle ID on a later line.
        def runner(output):
            return lambda args, stdin=None, timeout=10.0: (0, output, False)
        def front(name, bundle):
            return (f'"{name}" ASN:0x0-0x207207: (in front) \n    bundleID="{bundle}" \n'
                    '    bundle path=[ NULL ] \n')
        self.assertEqual(send_probe.frontmost(runner(front("Terminal", "com.apple.Terminal"))), "terminal")
        self.assertEqual(send_probe.frontmost(runner(front("Messages", "com.apple.MobileSMS"))), "messages")
        self.assertEqual(send_probe.frontmost(runner(front("Claude", "com.example.other"))), "other")
        self.assertEqual(send_probe.frontmost(runner('"Terminal" ASN:0x0-0x1: \n    bundleID=[ NULL ] \n')),
                         "terminal")


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "chat.db"
        self.count = root / "send-count"
        fx.build_chat_db(self.db, wal=True)
        fx.seed_standard(self.db, now_unix=START)
        conn = sqlite3.connect(str(self.db))
        self.group_rowid = conn.execute("SELECT ROWID FROM chat WHERE style = 43").fetchone()[0]
        conn.close()
        self.config = {"group": {"chat_id": fx.SENTINEL_GROUP_GUID, "handles": list(GROUP_HANDLES)}}
        self.clock = FakeClock()

    def tearDown(self):
        self.tmp.cleanup()

    def probe(self, runner, preflight=False, tamper=False, confirm=lambda prompt: "SEND", label="c2"):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            report = send_probe.run_probe(self.config, "group", label, preflight_only=preflight, tamper=tamper,
                                          id_prefix=None, runner=runner, confirm=confirm, db_path=str(self.db),
                                          clock=self.clock.clock, sleep=self.clock.sleep, count_path=self.count)
        return report, out.getvalue()

    def test_no_send_without_SEND(self):
        runner = FakeRunner()
        with self.assertRaises(spikelib.ProbeError):
            self.probe(runner, confirm=lambda prompt: "send")
        self.assertEqual(runner.osascript_calls(), [])
        self.assertEqual(send_probe.read_count(self.count), 0)

    def test_send_cap(self):
        self.count.write_text("6\n")
        prompts = []
        runner = FakeRunner()
        with self.assertRaises(spikelib.ProbeError):
            self.probe(runner, confirm=lambda prompt: prompts.append(prompt) or "SEND")
        self.assertEqual(prompts, [])
        self.assertEqual(runner.calls, [])

    def test_preflight_needs_no_confirm_and_counts_nothing(self):
        runner = FakeRunner(osascript=(0, "READY", False))
        report, _ = self.probe(runner, preflight=True, confirm=lambda prompt: self.fail("asked to confirm"))
        self.assertEqual(report["outcome"], "ready")
        self.assertNotIn("send ", runner.osascript_calls()[0][1])
        self.assertEqual(send_probe.read_count(self.count), 0)
        self.assertIsNone(report["anchor_rows"])

    def test_ambiguous_is_not_retried(self):
        runner = FakeRunner(osascript=(0, "UNCERTAIN:-1712", False))
        report, _ = self.probe(runner)
        self.assertEqual(len(runner.osascript_calls()), 1)
        self.assertEqual((report["outcome"], report["code"]), ("ambiguous", -1712))
        self.assertEqual(send_probe.read_count(self.count), 1)
        self.assertEqual(report["anchor_rows"], 0)

    def test_sent_finds_one_anchor(self):
        runner = FakeRunner(deliver_to=(self.db, self.group_rowid), clock=self.clock)
        report, _ = self.probe(runner)
        self.assertEqual(report["outcome"], "sent")
        self.assertEqual(report["anchor_rows"], 1)
        self.assertIsNotNone(report["anchor_delay_s"])
        self.assertEqual(send_probe.read_count(self.count), 1)
        self.assertEqual(runner.osascript_calls()[0][2], 35)

    def test_tamper_changes_expected_set(self):
        runner = FakeRunner(osascript=(0, "READY", False))
        self.probe(runner, preflight=True, tamper=True)
        script = runner.osascript_calls()[0][1]
        self.assertIn(send_probe.literal(send_probe.TAMPER_HANDLE), script)
        self.assertNotIn(send_probe.literal(GROUP_HANDLES[-1]), script)
        self.assertIn("is not 3", script)
        self.assertEqual(self.config["group"]["handles"], GROUP_HANDLES)

    def test_id_prefix_rewrites_service(self):
        runner = FakeRunner(osascript=(0, "READY", False))
        with contextlib.redirect_stdout(io.StringIO()):
            send_probe.run_probe(self.config, "group", "pre1", preflight_only=True, tamper=False, id_prefix="any",
                                 runner=runner, db_path=str(self.db), clock=self.clock.clock,
                                 sleep=self.clock.sleep, count_path=self.count)
        self.assertIn('chat id "any;+;chatSENTINEL"', runner.osascript_calls()[0][1])

    def test_rejects_bad_label_and_missing_target(self):
        with self.assertRaises(spikelib.ProbeError):
            self.probe(FakeRunner(), label="Has Spaces")
        with self.assertRaises(spikelib.ProbeError):
            send_probe.run_probe({}, "one_to_one", "c1", preflight_only=True, tamper=False, id_prefix=None,
                                 runner=FakeRunner(), db_path=str(self.db), count_path=self.count)

    def test_report_has_no_sentinels(self):
        runner = FakeRunner(deliver_to=(self.db, self.group_rowid), clock=self.clock)
        report, printed = self.probe(runner)
        dumped = json.dumps(report) + printed
        for sentinel in fx.SENTINELS:
            self.assertNotIn(sentinel, dumped)
        spikelib.assert_counts_only(report, send_probe.ALLOWED | {"c2"})


class PickChatTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "chat.db"
        self.config_path = root / "config.json"
        fx.build_chat_db(self.db)
        fx.seed_standard(self.db, now_unix=START)

    def tearDown(self):
        self.tmp.cleanup()

    def pick(self, kind, name_contains=None, handle=None):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = pick_chat.pick_chat(str(self.db), kind, name_contains, handle, self.config_path)
        return code, out.getvalue() + err.getvalue()

    def test_pick_chat_requires_unique_match_and_prints_no_identifiers(self):
        code, printed = self.pick("group", name_contains="sentinel")
        self.assertEqual(code, 0)
        self.assertEqual(printed.strip(), "wrote group target with 3 participants")
        code, printed_one = self.pick("one_to_one", handle=fx.SENTINEL_EMAIL)
        self.assertEqual(code, 0)
        config = json.loads(self.config_path.read_text())
        self.assertEqual(config["group"]["chat_id"], fx.SENTINEL_GROUP_GUID)
        self.assertEqual(sorted(config["group"]["handles"]), sorted(GROUP_HANDLES))
        self.assertEqual(config["one_to_one"]["handles"], [fx.SENTINEL_EMAIL])
        self.assertEqual(self.config_path.stat().st_mode & 0o777, 0o600)

        conn = sqlite3.connect(str(self.db))
        fx.add_chat(conn, "iMessage;+;chatOTHER", 43, [fx.SENTINEL_PHONE, fx.SENTINEL_EMAIL],
                    display_name=fx.SENTINEL_GROUP_NAME + " 2")
        conn.commit()
        conn.close()
        code, printed_dup = self.pick("group", name_contains="sentinel")
        self.assertNotEqual(code, 0)
        code, printed_none = self.pick("one_to_one", handle="nobody@example.invalid")
        self.assertNotEqual(code, 0)
        self.assertEqual(json.loads(self.config_path.read_text())["group"]["chat_id"], fx.SENTINEL_GROUP_GUID)
        for text in (printed, printed_one, printed_dup, printed_none):
            for sentinel in fx.SENTINELS:
                self.assertNotIn(sentinel, text)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import plistlib
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "companion"))
sys.path.insert(0, str(ROOT / "companion/spikes"))

import build_fork_app  # noqa: E402
import preview_apps as preview  # noqa: E402
import sign_check  # noqa: E402
import spikelib  # noqa: E402

BUNDLE_ID = "io.github.goldalex98.msgblast-imessage"


class ForkVariantTests(unittest.TestCase):
    def test_fork_variant_info(self):
        with open(ROOT / "msgblast/Info.plist", "rb") as file:
            info = preview.configure_info(plistlib.load(file), build_fork_app.FORK_VARIANT, "0" * 40)
        preview.verify_configured_info(info, build_fork_app.FORK_VARIANT, "0" * 40)
        self.assertEqual(info["CFBundleIdentifier"], BUNDLE_ID)
        for key in ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "msgblastDemo"):
            self.assertIs(info[key], False, key)
        self.assertIs(info["msgblastDisableUpdates"], True)
        self.assertEqual(info["SUFeedURL"], "")
        self.assertEqual(info["SUPublicEDKey"], "")
        self.assertEqual(info["msgblastSupportDirectory"], "msgblast-iMessage")
        # Telemetry.swift:134 sends only for upstream's two bundle IDs and the msgblast.app endpoint;
        # the Debug build expands this placeholder to "".
        self.assertNotEqual(info.get("msgblastTelemetryEndpoint"), "https://msgblast.app/api/telemetry")

    def test_fork_identity_is_not_upstream(self):
        variant = build_fork_app.FORK_VARIANT
        self.assertEqual(variant["bundle_id"], BUNDLE_ID)
        self.assertNotIn(variant["bundle_id"], {"com.msgblast.mac", "com.msgblast.development", "com.msgblast.demo"})
        self.assertTrue(variant["support_directory"].startswith("msgblast-"))
        self.assertEqual(variant["app_name"], "msgblast iMessage.app")
        self.assertEqual((variant["icon_name"], variant["icon_source"]), ("AppIconDemo", preview.BLUE))
        self.assertEqual(preview.expected_icon_color(variant), "blue")
        self.assertFalse(variant["fixture"])
        self.assertFalse(variant["demo"])
        self.assertEqual(build_fork_app.FORK_IDENTITY, "msgblast-imessage local signing")

    def test_resign_commands(self):
        app = Path("/out/msgblast iMessage.app")
        executable = app / "Contents/MacOS/msgblast"
        framework = app / "Contents/Frameworks/Sparkle.framework"
        helper = framework / "Versions/B/XPCServices/Installer.xpc"
        dylib = app / "Contents/MacOS/msgblast.debug.dylib"
        commands = build_fork_app.resign_commands(app, Path("/ws/msgblast/msgblastDebug.entitlements"),
                                                  build_fork_app.FORK_IDENTITY,
                                                  [framework, executable, dylib, helper], executable)
        signs = [c for c in commands if c[:2] == ["codesign", "--force"]]
        self.assertTrue(all("--timestamp" not in c for c in commands))
        self.assertTrue(all(c[c.index("--sign") + 1] == build_fork_app.FORK_IDENTITY for c in signs))
        self.assertTrue(all("--options" in c and c[c.index("--options") + 1] == "runtime" for c in signs))
        signed_paths = [c[-1] for c in signs]
        self.assertNotIn(str(executable), signed_paths[:-1])
        self.assertLess(signed_paths.index(str(helper)), signed_paths.index(str(framework)))
        for command in signs[:-1]:
            self.assertIn("--preserve-metadata=entitlements", command)
        self.assertEqual(signs[-1][-1], str(app))
        self.assertIn("--entitlements", signs[-1])
        self.assertIs(commands[-2], signs[-1])
        self.assertEqual(commands[-1], ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])


META = """Executable=/Applications/msgblast iMessage.app/Contents/MacOS/msgblast
Identifier={identifier}
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=30+7 location=embedded
Authority={authority}
Signed Time=7 Nov 2026 at 22:10:00
"""


def canned(identifier=BUNDLE_ID, authority="msgblast-imessage local signing",
           requirement=f'designated => identifier "{BUNDLE_ID}" and certificate leaf = H"ab12"'):
    def runner(args):
        if "-r-" in args:
            return (0, "Executable=/Applications/msgblast iMessage.app/Contents/MacOS/msgblast\n" + requirement + "\n")
        return (0, META.format(identifier=identifier, authority=authority))
    return runner


class SignCheckTests(unittest.TestCase):
    def test_resign_commands_timestamp_only_when_asked(self):
        app = Path("/out/msgblast iMessage.app")
        commands = build_fork_app.resign_commands(app, Path("/ws/e.entitlements"), "ABCDEF0123", [], None,
                                                  timestamp=True)
        signs = [c for c in commands if c[:2] == ["codesign", "--force"]]
        self.assertTrue(signs and all("--timestamp" in c for c in signs))
        self.assertNotIn("--timestamp", commands[-1])

    def test_identity_defaults_to_the_self_signed_one(self):
        missing = Path("/nonexistent/signing-identity")
        self.assertEqual(build_fork_app.resolve_identity({}, missing), build_fork_app.FORK_IDENTITY)

    def test_identity_from_the_local_file(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "signing-identity"
            f.write_text("  0123456789ABCDEF0123456789ABCDEF01234567\n# comment\n")
            self.assertEqual(build_fork_app.resolve_identity({}, f), "0123456789ABCDEF0123456789ABCDEF01234567")
            f.write_text("\n")
            self.assertEqual(build_fork_app.resolve_identity({}, f), build_fork_app.FORK_IDENTITY)

    def test_identity_env_wins_over_the_file(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "signing-identity"
            f.write_text("FROMFILE\n")
            env = {build_fork_app.IDENTITY_ENV: "FROMENV"}
            self.assertEqual(build_fork_app.resolve_identity(env, f), "FROMENV")
            self.assertEqual(build_fork_app.resolve_identity({build_fork_app.IDENTITY_ENV: " "}, f), "FROMFILE")

    def test_identity_file_lives_outside_the_repo(self):
        path = build_fork_app.IDENTITY_FILE
        self.assertFalse(str(path).startswith(str(ROOT)))
        self.assertEqual(path, Path.home() / ".config/msgblast-imessage/signing-identity")

    def test_only_the_self_signed_identity_skips_the_timestamp(self):
        self.assertFalse(build_fork_app.wants_timestamp(build_fork_app.FORK_IDENTITY))
        self.assertTrue(build_fork_app.wants_timestamp("0123456789ABCDEF0123456789ABCDEF01234567"))

    def test_signature_facts(self):
        app = Path("/Applications/msgblast iMessage.app")
        facts = sign_check.signature_facts(app, canned())
        self.assertTrue(facts["identifier_ok"])
        self.assertTrue(facts["authority_is_fork_identity"])
        self.assertFalse(facts["requirement_uses_cdhash"])
        self.assertRegex(facts["requirement_sha256"], r"^[0-9a-f]{64}$")

        adhoc = sign_check.signature_facts(app, canned(authority="(none)",
                                                       requirement='designated => cdhash H"0123abcd"'))
        self.assertFalse(adhoc["authority_is_fork_identity"])
        self.assertTrue(adhoc["requirement_uses_cdhash"])
        self.assertNotEqual(adhoc["requirement_sha256"], facts["requirement_sha256"])
        self.assertFalse(sign_check.signature_facts(app, canned(identifier="com.msgblast.development"))["identifier_ok"])

    def test_unsigned_app_gives_false_facts(self):
        facts = sign_check.signature_facts(Path("/nope.app"), lambda args: (1, "code object is not signed at all"))
        self.assertEqual(facts, {"identifier_ok": False, "authority_is_fork_identity": False,
                                 "requirement_uses_cdhash": False, "requirement_sha256": None})

    def test_compare_reports(self):
        first = {"requirement_sha256": "a" * 64, "fda": True, "automation": True}
        self.assertEqual(sign_check.compare_reports(first, dict(first)), {"same_requirement": True, "grants_kept": True})
        self.assertEqual(sign_check.compare_reports(first, {**first, "requirement_sha256": "b" * 64, "fda": False}),
                         {"same_requirement": False, "grants_kept": False})
        self.assertFalse(sign_check.compare_reports({**first, "requirement_sha256": None},
                                                    {**first, "requirement_sha256": None})["same_requirement"])

    def test_record_report_is_counts_only(self):
        report = sign_check.record_report(Path("/Applications/msgblast iMessage.app"), "build1", True, False, canned())
        self.assertNotIn("/Applications", str(report))
        spikelib.assert_counts_only(report, sign_check.allowed_for(report))
        with self.assertRaises(spikelib.ProbeError):
            sign_check.record_report(Path("/x.app"), "Build 1!", True, True, canned())


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import ci_native_scope as scope  # noqa: E402


class NativeScopeTests(unittest.TestCase):
    def test_docs_and_claude_only_skip_native(self):
        self.assertEqual(scope.decide(["docs/x.md", ".claude/STATUS.md", "FORK.md", ".claude/agents/a.md"]),
                         ("false", "none"))

    def test_no_files_skips_native(self):
        self.assertEqual(scope.decide([]), ("false", "none"))

    def test_companion_only_runs_companion_suites(self):
        files = ["msgblast/Core/Companion/CompanionReader.swift", "msgblastTests/CompanionReaderTests.swift",
                 "msgblast/Companion/CompanionStatusView.swift", "companion/spikes/spikelib.py",
                 "scripts/tests/test_companion_bodies.py", "docs/superpowers/plans/p.md"]
        self.assertEqual(scope.decide(files), ("true", "companion"))

    def test_any_other_file_runs_the_full_suite(self):
        for other in ["msgblast/Core/MessagesSendScript.swift", "msgblast.xcodeproj/project.pbxproj",
                      ".github/workflows/fork-ci.yml", "scripts/ci_native_scope.py", "msgblastTests/WebServiceTests.swift"]:
            with self.subTest(other=other):
                self.assertEqual(scope.decide(["msgblast/Core/Companion/CompanionReader.swift", other]), ("true", "full"))

    def test_only_testing_flags(self):
        self.assertEqual(scope.only_testing("full"), ["-only-testing:msgblastTests"])
        flags = scope.only_testing("companion")
        self.assertIn("-only-testing:msgblastTests/CompanionServiceTests", flags)
        self.assertEqual(len(flags), len(scope.COMPANION_SUITES))

    def test_every_companion_suite_exists(self):
        for suite in scope.COMPANION_SUITES:
            with self.subTest(suite=suite):
                self.assertTrue((ROOT / "msgblastTests" / f"{suite}.swift").is_file())

    def test_every_companion_test_file_is_listed(self):
        for path in (ROOT / "msgblastTests").glob("*.swift"):
            if scope.is_companion(f"msgblastTests/{path.name}") and path.stem != "CompanionFixture":
                with self.subTest(path=path.name):
                    self.assertIn(path.stem, scope.COMPANION_SUITES)


if __name__ == "__main__":
    unittest.main()

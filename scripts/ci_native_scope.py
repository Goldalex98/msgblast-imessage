#!/usr/bin/env python3
"""Decide how much of the native (macOS) test suite fork CI runs for a change.

- Pushes to main and manual runs: the full suite.
- A PR touching only docs, `.claude/` or Markdown: no native job (the Linux job still runs).
- A PR whose other files are all companion code or companion tests: the companion suites only.
- Any other PR: the full suite.

In CI it reads EVENT and BASE (the PR's base SHA), diffs BASE...HEAD and writes `native`, `scope`
and `only_testing` to $GITHUB_OUTPUT. Fork-only file; not sent upstream.
"""
from __future__ import annotations

import fnmatch
import os
import subprocess
import sys

DOC_PATTERNS = ["docs/*", ".claude/*", "*.md", "LICENSE*"]
COMPANION_PATTERNS = [
    "msgblast/Companion/*",
    "msgblast/Core/Companion/*",
    "companion/*",
    "scripts/tests/test_companion_*.py",
    "scripts/tests/companion_fixture.py",
    "msgblastTests/Companion*.swift",
    "msgblastTests/AttributedBodyDecoderTests.swift",
    "msgblastTests/ContactNameResolverTests.swift",
    "msgblastTests/UplinkClientTests.swift",
]
COMPANION_SUITES = [
    "AttributedBodyDecoderTests",
    "CompanionConfigTests",
    "CompanionModelsTests",
    "CompanionReaderTests",
    "CompanionScrubberTests",
    "CompanionServiceTests",
    "ContactNameResolverTests",
    "UplinkClientTests",
    "CompanionSendModelsTests",
]


def _matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, p) for p in patterns)


def is_doc(path: str) -> bool:
    return _matches(path, DOC_PATTERNS)


def is_companion(path: str) -> bool:
    return _matches(path, COMPANION_PATTERNS)


def decide(files: list[str]) -> tuple[str, str]:
    """(native, scope) for a PR's changed files: native is "true"/"false", scope "none"/"companion"/"full"."""
    code = [f for f in files if not is_doc(f)]
    if not code:
        return "false", "none"
    if all(is_companion(f) for f in code):
        return "true", "companion"
    return "true", "full"


def only_testing(scope: str) -> list[str]:
    if scope == "companion":
        return [f"-only-testing:msgblastTests/{s}" for s in COMPANION_SUITES]
    return ["-only-testing:msgblastTests"]


def main() -> int:
    event = os.environ.get("EVENT", "")
    if event == "pull_request":
        base = os.environ["BASE"]
        out = subprocess.run(["git", "diff", "--name-only", f"{base}...HEAD"], check=True,
                             capture_output=True, text=True).stdout
        files = [line for line in out.splitlines() if line]
        native, scope = decide(files)
    else:
        files, native, scope = [], "true", "full"
    print(f"event={event or 'unknown'} changed={len(files)} native={native} scope={scope}")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as fh:
            fh.write(f"native={native}\nscope={scope}\nonly_testing={' '.join(only_testing(scope))}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

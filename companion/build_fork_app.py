#!/usr/bin/env python3
"""Build the fork's own app, "msgblast iMessage.app", signed with the owner's self-signed identity.

Run on the Mac:  python3 -I companion/build_fork_app.py [--sha <commit>] [--output build/fork-app]
It reuses upstream's preview builder (scripts/build_preview_apps.py) without editing it: an isolated
workspace copy, a Debug build with Sparkle's feed and key empty, the fork's bundle ID and support folder,
then a re-sign with FORK_IDENTITY so macOS keeps Full Disk Access and Automation across rebuilds.
Never publishes, notarizes or uploads anything.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_preview_apps as build  # noqa: E402
import preview_apps as preview  # noqa: E402

FORK_VARIANT = {
    **preview.VARIANTS["development"],
    "id": "imessage",
    "label": "iMessage companion fork",
    "app_name": "msgblast iMessage.app",
    "bundle_id": "io.github.goldalex98.msgblast-imessage",
    "bundle_name": "msgblast iMessage",
    "display_name": "msgblast iMessage",
    "icon_name": "AppIconDemo",
    "icon_source": preview.BLUE,
    "replace_app_icon": False,
    "support_directory": "msgblast-iMessage",
    "artifact_prefix": "msgblast-imessage",
}
FORK_IDENTITY = "msgblast-imessage local signing"
DEFAULT_OUTPUT = ROOT / "build" / "fork-app"


def resign_commands(app: Path, entitlements: Path, identity: str, nested: List[Path],
                    executable: Optional[Path]) -> List[List[str]]:
    """Upstream sign_bundle's flags and order, minus --timestamp (offline, self-signed).

    Everything nested was already ad-hoc signed by package_variant, so each nested item keeps its
    entitlements. The main executable is sealed by the final outer signature.
    """
    base = ["codesign", "--force", "--sign", identity, "--options", "runtime"]
    commands = [[*base, "--preserve-metadata=entitlements", str(path)]
                for path in build.signing_order(nested) if path != executable]
    commands.append([*base, "--entitlements", str(entitlements), str(app)])
    commands.append(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    return commands


def nested_code(app: Path) -> List[Path]:
    """The same discovery as upstream sign_bundle."""
    found = []
    for path in app.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_dir() and path.suffix in {".framework", ".xpc", ".app"}:
            found.append(path)
        elif path.is_file() and build.is_mach_o(path):
            found.append(path)
    return found


def identity_available(identity: str) -> bool:
    listed = subprocess.run(["security", "find-identity", "-p", "codesigning"],
                            capture_output=True, text=True).stdout
    return f'"{identity}"' in listed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sha", default=None, help="source revision to stamp (default: HEAD)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if not identity_available(FORK_IDENTITY):
        print(f'No code-signing identity named "{FORK_IDENTITY}" in the keychain; create it first '
              "(Keychain Access > Certificate Assistant > Create a Certificate, type Code Signing).", file=sys.stderr)
        return 2
    sha = args.sha or subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                                     text=True, check=True).stdout.strip()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="msgblast-imessage-build-") as scratch:
        workspace = preview.copy_workspace(Path(scratch) / "workspace")
        record = build.package_variant(workspace, FORK_VARIANT, sha, output, enable_dev_telemetry=False)
        app = output / FORK_VARIANT["app_name"]
        entitlements = workspace / "msgblast/msgblastDebug.entitlements"
        for command in resign_commands(app, entitlements, FORK_IDENTITY, nested_code(app), build.bundle_executable(app)):
            build.run(command, app.parent)
    stale = output / record["zip"]
    if stale.exists():
        stale.unlink()  # the zip holds the ad-hoc signature, not the fork identity
    print(f"Built {app}\nInstall: quit any running copy, then replace /Applications/{FORK_VARIANT['app_name']} with it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

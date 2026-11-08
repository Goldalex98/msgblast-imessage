"""Spike (g): does a rebuilt fork app keep the same code identity, so Full Disk Access and Automation survive?

Run on the Mac by Alex:
  python3 -I companion/spikes/sign_check.py record --app "/Applications/msgblast iMessage.app" \\
      --label build1 --fda yes --automation yes
  python3 -I companion/spikes/sign_check.py compare <report-a> <report-b>
--fda and --automation are what the app's own permission screen shows. Reports hold booleans and a
hash of the designated requirement only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402

BUNDLE_ID = "io.github.goldalex98.msgblast-imessage"
FORK_IDENTITY = "msgblast-imessage local signing"
LABEL_RE = re.compile(r"^[a-z0-9]{1,16}$")

Runner = Callable[[list], Tuple[int, str]]


def run_command(args: list) -> Tuple[int, str]:
    """codesign -d writes to stderr, so both streams are returned together."""
    done = subprocess.run(args, capture_output=True, text=True)
    return (done.returncode, done.stdout + done.stderr)


def signature_facts(app: Path, runner: Runner = run_command) -> dict:
    code, meta = runner(["codesign", "-dv", "--verbose=4", str(app)])
    lines = set(meta.splitlines()) if code == 0 else set()
    code, req_out = runner(["codesign", "-d", "-r-", str(app)])
    requirement = ""
    if code == 0 and "designated =>" in req_out:
        requirement = req_out.split("designated =>", 1)[1].strip()
    return {
        "identifier_ok": f"Identifier={BUNDLE_ID}" in lines,
        "authority_is_fork_identity": f"Authority={FORK_IDENTITY}" in lines,
        "requirement_uses_cdhash": "cdhash" in requirement,
        "requirement_sha256": hashlib.sha256(requirement.encode()).hexdigest() if requirement else None,
    }


def record_report(app: Path, label: str, fda: bool, automation: bool, runner: Runner = run_command) -> dict:
    if not LABEL_RE.match(label or ""):
        raise spikelib.ProbeError(4, "--label must be 1-16 lowercase letters or digits")
    return {"label": label, "fda": fda, "automation": automation, **signature_facts(app, runner)}


def allowed_for(report: dict) -> frozenset:
    """The label and the requirement hash are the only strings a report may hold."""
    return frozenset(value for value in (report.get("label"), report.get("requirement_sha256")) if value)


def compare_reports(first: dict, second: dict) -> dict:
    same = bool(first.get("requirement_sha256")) and first.get("requirement_sha256") == second.get("requirement_sha256")
    kept = all(bool(report.get(key)) for report in (first, second) for key in ("fda", "automation"))
    return {"same_requirement": same, "grants_kept": kept}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    record = commands.add_parser("record")
    record.add_argument("--app", type=Path, required=True)
    record.add_argument("--label", required=True)
    record.add_argument("--fda", choices=("yes", "no"), required=True)
    record.add_argument("--automation", choices=("yes", "no"), required=True)
    compare = commands.add_parser("compare")
    compare.add_argument("first", type=Path)
    compare.add_argument("second", type=Path)
    args = parser.parse_args()
    if args.command == "record":
        report = record_report(args.app, args.label, args.fda == "yes", args.automation == "yes")
        print(spikelib.write_report(f"sign-{args.label}", report, allowed_for(report)))
        return 0
    reports = [json.loads(path.read_text()) for path in (args.first, args.second)]
    print(spikelib.write_report("sign-compare", compare_reports(*reports), frozenset()))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

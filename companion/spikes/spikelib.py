"""Shared helpers for the phase 0 spike probes.

Probes open chat.db read-only and write counts-only reports to .local/spikes/ (git-ignored).
Python 3.9+, standard library only.
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
import urllib.parse
from pathlib import Path
from typing import Callable, Optional

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / ".local" / "spikes"
DEFAULT_CONFIG = DEFAULT_OUT / "config.json"
DEFAULT_DB = str(Path.home() / "Library" / "Messages" / "chat.db")
APPLE_EPOCH_UNIX = 978307200.0
FDA_HINT = ("Can't open chat.db read-only. Grant Full Disk Access to the app running this command "
            "(System Settings > Privacy & Security > Full Disk Access), then retry.")
# SQL expression for a message date in seconds since 2001 (nanoseconds on modern macOS, seconds on old ones).
APPLE_SECONDS_SQL = "(CASE WHEN m.date > 1000000000000 THEN m.date / 1000000000.0 ELSE m.date END)"
REACTION_FILTER_SQL = "COALESCE(m.associated_message_type, 0) NOT BETWEEN 2000 AND 3999"


class ProbeError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code


def open_ro(path: str) -> sqlite3.Connection:
    """Open chat.db read-only (msgblast: SQLITE_OPEN_READONLY, 1500 ms busy timeout)."""
    try:
        conn = sqlite3.connect("file:" + urllib.parse.quote(path) + "?mode=ro", uri=True, timeout=1.5)
        conn.execute("SELECT 1 FROM sqlite_master LIMIT 1").fetchall()
    except sqlite3.DatabaseError as error:
        raise ProbeError(2, FDA_HINT) from error
    return conn


def apple_seconds(raw: int) -> float:
    return raw / 1e9 if raw > 1e12 else float(raw)


def unix_time(raw: int) -> float:
    return apple_seconds(raw) + APPLE_EPOCH_UNIX


def assert_counts_only(report: dict, allowed: frozenset) -> None:
    """Reports may hold only keys, numbers, booleans, null and strings from a fixed enum."""
    def check(value, where: str) -> None:
        if value is None or isinstance(value, (bool, int, float)):
            return
        if isinstance(value, str):
            if value in allowed:
                return
            raise ValueError(f"report is not counts-only at {where}")
        if isinstance(value, dict):
            for key, inner in value.items():
                if not isinstance(key, str):
                    raise ValueError(f"report has a non-string key under {where}")
                check(inner, f"{where}.{key}" if where else key)
            return
        if isinstance(value, (list, tuple)):
            for index, inner in enumerate(value):
                check(inner, f"{where}[{index}]")
            return
        raise ValueError(f"report is not counts-only at {where}")

    check(report, "")


def write_report(name: str, report: dict, allowed: frozenset, out_dir: Optional[Path] = None) -> Path:
    assert_counts_only(report, allowed)
    directory = Path(out_dir) if out_dir else DEFAULT_OUT
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / f"{name}-{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}.json"
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump(report, file, indent=2, sort_keys=True)
        file.write("\n")
    return path


def load_config(path: Optional[Path] = None) -> dict:
    target = Path(path) if path else DEFAULT_CONFIG
    if not target.exists():
        raise ProbeError(3, "No .local/spikes/config.json yet: run pick_chat.py (or add the key by hand) first.")
    with target.open() as file:
        return json.load(file)


def save_config(config: dict, path: Optional[Path] = None) -> None:
    target = Path(path) if path else DEFAULT_CONFIG
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(str(target), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump(config, file, indent=2, sort_keys=True)


def run_main(fn: Callable[[], int]) -> int:
    try:
        return fn()
    except ProbeError as error:
        print(str(error), file=sys.stderr)
        return error.code

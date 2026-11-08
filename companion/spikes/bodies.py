"""Spike (a): how many recent messages have a body only in attributedBody, and does a decoder recover it.

Run on the Mac by Alex:  python3 -I companion/spikes/bodies.py [--days 14]
Prints only the path of a counts-only report in .local/spikes/.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402


def decode_attributed_body(blob: Optional[bytes]) -> Optional[str]:
    """Pull the NSString payload out of a typedstream NSAttributedString blob."""
    if not blob:
        return None
    i = blob.find(b"NSString")
    if i < 0:
        return None
    j = blob.find(b"\x01+", i)
    if j < 0:
        return None
    k = j + 2
    if k >= len(blob):
        return None
    n = blob[k]
    k += 1
    if n == 0x81:
        n = int.from_bytes(blob[k:k + 2], "little")
        k += 2
    elif n == 0x82:
        n = int.from_bytes(blob[k:k + 4], "little")
        k += 4
    raw = blob[k:k + n]
    if len(raw) != n:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def probe_bodies(conn, days: int = 14, now_unix: Optional[float] = None) -> dict:
    now = time.time() if now_unix is None else now_unix
    cutoff = now - days * 86400 - spikelib.APPLE_EPOCH_UNIX
    rows = conn.execute(
        f"SELECT m.text, m.attributedBody, COALESCE(m.cache_has_attachments, 0) FROM message m"
        f" WHERE {spikelib.APPLE_SECONDS_SQL} >= ? AND {spikelib.REACTION_FILTER_SQL}", (cutoff,))
    report = dict.fromkeys(("total", "text_present", "attributed_only", "attributed_only_decoded",
                            "attributed_only_failed", "neither", "neither_with_attachment",
                            "cross_check_total", "cross_check_equal"), 0)
    for text, blob, has_attachment in rows:
        report["total"] += 1
        has_text = bool(text)
        has_blob = bool(blob)
        if has_text:
            report["text_present"] += 1
            if has_blob:
                report["cross_check_total"] += 1
                report["cross_check_equal"] += int(decode_attributed_body(blob) == text)
        elif has_blob:
            report["attributed_only"] += 1
            decoded = decode_attributed_body(blob) is not None
            report["attributed_only_decoded" if decoded else "attributed_only_failed"] += 1
        else:
            report["neither"] += 1
            report["neither_with_attachment"] += int(bool(has_attachment))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=spikelib.DEFAULT_DB)
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args()
    report = probe_bodies(spikelib.open_ro(args.db), days=args.days)
    print(spikelib.write_report("bodies", report, frozenset()))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

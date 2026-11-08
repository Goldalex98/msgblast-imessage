"""Spike (b): what reading group threads from chat.db looks like.

Run on the Mac by Alex:  python3 -I companion/spikes/groups.py [--days 14]
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

GROUP_STYLE = 43
ONE_TO_ONE_STYLE = 45


def _bucket(participants: int) -> str:
    if participants <= 2:
        return "p2"
    if participants == 3:
        return "p3"
    if participants <= 6:
        return "p4_6"
    return "p7_plus"


def probe_groups(conn, days: int = 14, now_unix: Optional[float] = None) -> dict:
    now = time.time() if now_unix is None else now_unix
    cutoff = now - days * 86400 - spikelib.APPLE_EPOCH_UNIX
    report = {
        "chats_by_style": {"group_43": 0, "one_to_one_45": 0, "other": 0},
        "style_count_mismatch": 0,
        "groups_active": 0,
        "participants": {"p2": 0, "p3": 0, "p4_6": 0, "p7_plus": 0},
        "group_inbound": 0,
        "group_inbound_with_sender": 0,
        "group_outgoing": 0,
        "group_with_reply_link": 0,
        "groups_with_display_name": 0,
    }
    chats = conn.execute(
        "SELECT c.ROWID, c.style, (c.display_name IS NOT NULL AND c.display_name != ''),"
        " (SELECT COUNT(DISTINCT ch.handle_id) FROM chat_handle_join ch WHERE ch.chat_id = c.ROWID)"
        " FROM chat c").fetchall()
    for chat_id, style, has_display_name, participants in chats:
        key = {GROUP_STYLE: "group_43", ONE_TO_ONE_STYLE: "one_to_one_45"}.get(style, "other")
        report["chats_by_style"][key] += 1
        if (style == GROUP_STYLE and participants <= 1) or (style == ONE_TO_ONE_STYLE and participants > 1):
            report["style_count_mismatch"] += 1
        if style != GROUP_STYLE:
            continue
        rows = conn.execute(
            "SELECT m.is_from_me, m.handle_id, (SELECT COUNT(*) FROM handle h WHERE h.ROWID = m.handle_id),"
            " COALESCE(m.thread_originator_guid, '')"
            " FROM message m JOIN chat_message_join cm ON cm.message_id = m.ROWID"
            f" WHERE cm.chat_id = ? AND {spikelib.APPLE_SECONDS_SQL} >= ? AND {spikelib.REACTION_FILTER_SQL}",
            (chat_id, cutoff)).fetchall()
        if not rows:
            continue
        report["groups_active"] += 1
        report["participants"][_bucket(participants)] += 1
        report["groups_with_display_name"] += int(bool(has_display_name))
        for is_from_me, handle_id, handle_exists, reply_to in rows:
            if is_from_me:
                report["group_outgoing"] += 1
            else:
                report["group_inbound"] += 1
                report["group_inbound_with_sender"] += int(bool(handle_id) and handle_exists > 0)
            report["group_with_reply_link"] += int(bool(reply_to))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=spikelib.DEFAULT_DB)
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args()
    report = probe_groups(spikelib.open_ro(args.db), days=args.days)
    print(spikelib.write_report("groups", report, frozenset()))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

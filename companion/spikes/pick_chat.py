"""Write one test chat's ID and participant handles into .local/spikes/config.json for send_probe.py.

Run on the Mac by Alex:
  python3 -I companion/spikes/pick_chat.py --kind group --name-contains "<test group name>"
  python3 -I companion/spikes/pick_chat.py --kind one_to_one --handle "<test contact handle>"
Refuses unless exactly one chat matches. Prints only the participant count, never an identifier.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402

KINDS = {"group": 43, "one_to_one": 45}


def _handles(conn, chat_rowid: int) -> list:
    rows = conn.execute("SELECT DISTINCT h.id FROM chat_handle_join ch JOIN handle h ON h.ROWID = ch.handle_id"
                        " WHERE ch.chat_id = ? ORDER BY h.id", (chat_rowid,)).fetchall()
    return [row[0] for row in rows]


def pick_chat(db_path: str, kind: str, name_contains: Optional[str], handle: Optional[str],
              config_path: Optional[Path] = None) -> int:
    if kind not in KINDS:
        print("--kind must be group or one_to_one", file=sys.stderr)
        return 4
    if kind == "group" and not name_contains:
        print("--kind group needs --name-contains", file=sys.stderr)
        return 4
    if kind == "one_to_one" and not handle:
        print("--kind one_to_one needs --handle", file=sys.stderr)
        return 4
    conn = spikelib.open_ro(db_path)
    chats = conn.execute("SELECT ROWID, guid, COALESCE(display_name, '') FROM chat WHERE style = ?",
                         (KINDS[kind],)).fetchall()
    matches = []
    for rowid, guid, display_name in chats:
        handles = _handles(conn, rowid)
        if kind == "group" and name_contains.lower() in display_name.lower():
            matches.append((guid, handles))
        elif kind == "one_to_one" and len(handles) == 1 and handles[0].lower() == handle.lower():
            matches.append((guid, handles))
    conn.close()
    if len(matches) != 1:
        print(f"found {len(matches)} matching {kind} chats; need exactly 1, nothing written", file=sys.stderr)
        return 4
    guid, handles = matches[0]
    try:
        config = spikelib.load_config(config_path)
    except spikelib.ProbeError:
        config = {}
    config[kind] = {"chat_id": guid, "handles": handles}
    spikelib.save_config(config, config_path)
    print(f"wrote {kind} target with {len(handles)} participants")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kind", required=True, choices=sorted(KINDS))
    parser.add_argument("--name-contains", default=None)
    parser.add_argument("--handle", default=None)
    parser.add_argument("--db", default=spikelib.DEFAULT_DB)
    args = parser.parse_args()
    return pick_chat(args.db, args.kind, args.name_contains, args.handle)


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))

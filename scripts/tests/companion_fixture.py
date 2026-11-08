"""Synthetic chat.db builder for the companion spike tests. Test-only; never touches a real database."""
from __future__ import annotations

import sqlite3
import time
from pathlib import Path
from typing import Iterable, Optional

APPLE_EPOCH_UNIX = 978307200
SENTINEL_TEXT = "SENTINEL-TEXT-7f3a"
SENTINEL_PHONE = "+15550001111"
SENTINEL_EMAIL = "sentinel@example.invalid"
SENTINEL_GROUP_GUID = "iMessage;+;chatSENTINEL"
SENTINEL_GROUP_NAME = "SENTINEL GROUP"
SENTINEL_PHONE_2 = "+15550002222"
SENTINELS = (SENTINEL_TEXT, SENTINEL_PHONE, SENTINEL_EMAIL, SENTINEL_GROUP_GUID, SENTINEL_GROUP_NAME)

SCHEMA = """
CREATE TABLE chat (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE, style INTEGER,
                   display_name TEXT, service_name TEXT);
CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT, service TEXT);
CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE, text TEXT,
                      attributedBody BLOB, date INTEGER, is_from_me INTEGER DEFAULT 0,
                      handle_id INTEGER DEFAULT 0, service TEXT, thread_originator_guid TEXT,
                      associated_message_type INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0);
"""


def apple_ns(unix_seconds: float) -> int:
    """Unix seconds to chat.db's Apple-epoch nanoseconds."""
    return int((unix_seconds - APPLE_EPOCH_UNIX) * 1_000_000_000)


def build_chat_db(path: Path, wal: bool = False) -> None:
    conn = sqlite3.connect(str(path))
    if wal:
        conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(SCHEMA)
    conn.commit()
    conn.close()


def handle_rowid(conn: sqlite3.Connection, handle: str, service: str = "iMessage") -> int:
    row = conn.execute("SELECT ROWID FROM handle WHERE id = ?", (handle,)).fetchone()
    if row:
        return row[0]
    return conn.execute("INSERT INTO handle(id, service) VALUES (?, ?)", (handle, service)).lastrowid


def add_chat(conn: sqlite3.Connection, guid: str, style: int, handles: Iterable[str] = (),
             display_name: Optional[str] = None, service: str = "iMessage") -> int:
    chat_id = conn.execute("INSERT INTO chat(guid, style, display_name, service_name) VALUES (?, ?, ?, ?)",
                           (guid, style, display_name, service)).lastrowid
    for handle in handles:
        conn.execute("INSERT INTO chat_handle_join(chat_id, handle_id) VALUES (?, ?)",
                     (chat_id, handle_rowid(conn, handle, service)))
    return chat_id


_counter = [0]


def add_message(conn: sqlite3.Connection, chat_id: int, unix_time: float, text: Optional[str] = None,
                attributed: Optional[bytes] = None, is_from_me: bool = False, sender: Optional[str] = None,
                service: str = "iMessage", reply_to: Optional[str] = None, reaction_type: int = 0,
                has_attachment: bool = False, raw_date: Optional[int] = None) -> int:
    _counter[0] += 1
    handle_id = handle_rowid(conn, sender) if sender else 0
    rowid = conn.execute(
        "INSERT INTO message(guid, text, attributedBody, date, is_from_me, handle_id, service,"
        " thread_originator_guid, associated_message_type, cache_has_attachments)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (f"msg-{_counter[0]}-{time.monotonic_ns()}", text, attributed,
         apple_ns(unix_time) if raw_date is None else raw_date, int(is_from_me), handle_id, service,
         reply_to, reaction_type, int(has_attachment))).lastrowid
    conn.execute("INSERT INTO chat_message_join(chat_id, message_id) VALUES (?, ?)", (chat_id, rowid))
    return rowid


def _typed_length(n: int) -> bytes:
    if n <= 0x7F:
        return bytes([n])
    if n <= 0xFFFF:
        return b"\x81" + n.to_bytes(2, "little")
    return b"\x82" + n.to_bytes(4, "little")


def make_attributed_body(text: str) -> bytes:
    """A minimal typedstream NSAttributedString blob, laid out the way Messages stores attributedBody."""
    payload = text.encode("utf-8")
    return (b"\x04\x0bstreamtyped\x81\xe8\x03\x84\x01@\x84\x84\x84\x12NSAttributedString\x00\x84\x84"
            b"\x08NSObject\x00\x85\x92\x84\x84\x84\x08NSString\x01\x94\x84\x01+"
            + _typed_length(len(payload)) + payload
            + b"\x86\x84\x02iI\x01\x01\x92\x84\x84\x84\x0cNSDictionary\x00")


def seed_standard(path: Path, now_unix: Optional[float] = None) -> None:
    """One 1:1 chat and one 3-handle group, all carrying the sentinels.

    In the 14-day window: 1:1 inbound + outgoing; group inbound (from SENTINEL_PHONE) + outgoing;
    one group reaction (type 2000). Outside the window: one group inbound row 30 days old.
    """
    now = time.time() if now_unix is None else now_unix
    conn = sqlite3.connect(str(path))
    one = add_chat(conn, "iMessage;-;" + SENTINEL_EMAIL, 45, [SENTINEL_EMAIL])
    group = add_chat(conn, SENTINEL_GROUP_GUID, 43, [SENTINEL_PHONE, SENTINEL_EMAIL, SENTINEL_PHONE_2],
                     display_name=SENTINEL_GROUP_NAME)
    add_message(conn, one, now - 3600, text=SENTINEL_TEXT, sender=SENTINEL_EMAIL)
    add_message(conn, one, now - 1800, text=SENTINEL_TEXT, is_from_me=True)
    add_message(conn, group, now - 7200, text=SENTINEL_TEXT, sender=SENTINEL_PHONE)
    add_message(conn, group, now - 600, text=SENTINEL_TEXT, is_from_me=True)
    add_message(conn, group, now - 300, text=SENTINEL_TEXT, sender=SENTINEL_PHONE, reaction_type=2000)
    add_message(conn, group, now - 30 * 86400, text=SENTINEL_TEXT, sender=SENTINEL_PHONE)
    conn.commit()
    conn.close()

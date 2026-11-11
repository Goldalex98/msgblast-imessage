# Reader hardening (phase 1 follow-up)

**Goal:** close four silent-failure gaps in the companion reader, found by comparing it with mature open-source `chat.db` readers (`anipottsbuilds/imessage-mcp` releases 1.1.0–3.3.2 and its fork `jaredzimmerman/iMessageMCP`, both MIT). Ideas only: no code is copied.

**Scope:** Mac side only, inside `msgblast/Core/Companion/` and `msgblastTests/`. No contract change, no HomeChat change, no sending. The installed app is unaffected until Alex rebuilds and reinstalls it.

**Gate:** the Linux gate here; the native core tests on fork CI's `xcode-27` runner. Neither proves the installed app; a MacBook run before reinstalling does.

## Tasks (test-first)

### 1. Reopen when Messages replaces `chat.db`
- Problem: `CompanionService` keeps one `CompanionReader` open for its life and reopens only after an error. If Messages replaces the file (a rename over the path, a rebuilt database), the open connection still reads the old file, `data_version` never changes, and the service reports idle while nothing new is read.
- Change: when the reader opens, record the database file's identity (device and inode from `stat`). Each tick, before using the reader, `stat` the path again; if the identity differs or the file is gone, close the reader and open a fresh one. A missing file follows the existing `unreadable` path.
- Test: a service test ticks against a fixture database, replaces it with `rename()` by a second fixture that holds one more message, ticks again, and expects that message read.

### 2. Stop visibly when the cursor is ahead of the database
- Problem: if the database is reset (a rebuilt Messages store, a migration), new ROWIDs can start below the saved cursor. `isCaughtUp` (`max <= cursor`) then reports caught up for ever, and every new message is skipped with no sign.
- Change: when a saved cursor exists and the highest ROWID the database has ever handed out is below it (AUTOINCREMENT's `sqlite_sequence` entry for `message`, else `MAX(ROWID)`; deleting the newest messages lowers `MAX(ROWID)` but is not a reset), stop with the status `stopped("Messages database was reset; the companion needs a fresh start")` and read nothing. Do not lower the cursor on its own: the contract requires batches in rising cursor order, and how HomeChat should take a re-baseline is an open question (below).
- Tests: a config cursor of 10 000 against a fixture whose highest ROWID is 40 gives that stopped state and no post, and clearing the cursor recovers; deleting the newest message after it was uplinked does not stop, and the next message (ROWID 4) is read. The fixture's `message` table now uses AUTOINCREMENT, as chat.db's does.

### 3. Leave system rows out
- Problem: group events (a member joining or leaving, a rename, a group photo) are `message` rows with `item_type` ≠ 0 and no text. The reader treats them as messages, so they go up as `unreadable` (or, from Alex's side, as a reply).
- Change: read `m.item_type` and add it to the required columns. A row with `item_type` ≠ 0 and no text, no `attributedBody` and no attachments is passed over like a chat-less row: the cursor moves past it and nothing is uplinked. A row that carries any of those is read as usual, so an ordinary message is never dropped on `item_type` alone (review finding).
- Test: a fixture with `item_type` 1, 2 and 3 rows between ordinary ones uplinks only the ordinary ones, and the cursor passes the system rows; an `item_type` 2 row with text is still uplinked.

### 4. Body size cap and empty bodies
- Problem: no cap on the `attributedBody` blob handed to `NSUnarchiver`; the tests cover a 70k-character body but not an empty attributed string or a very large one.
- Change: a blob over 4 MiB is not decoded (the message becomes `unreadable`, or `attachment_only` when it has attachments). This matches the 4 MiB limit `imessage-mcp` settled on in 2.1.1.
- Tests: an archived empty string decodes to no text without a crash; a 1.5 MiB body decodes; a blob over 4 MiB returns nil without calling the unarchiver.

## Before reinstalling on the MacBook
Counts-only, read-only queries on the real `chat.db` (print numbers, never text, handles or names), plus the native gate from `docs/testing.md`:
- `SELECT COUNT(*) FROM sqlite_sequence WHERE name = 'message'` is 1: the real `message` table uses AUTOINCREMENT, so task 2 can't stop falsely after the newest messages are deleted.
- `SELECT item_type, COUNT(*), SUM(text IS NOT NULL OR attributedBody IS NOT NULL) FROM message GROUP BY item_type`: how many rows task 3 would pass over, and that non-zero types with a body are few.
- If the reset stop ever shows, don't clear the cursor until HomeChat's handling of a lower `first_run` cursor is confirmed (open question below).

## Not in this plan (recorded for later)
- A reset whose new database has already grown past the saved cursor is not detected; rows at or below the cursor would be skipped.
- Edits, unsends and retractions (contract "Known gaps"): needs a contract change and HomeChat work.
- A reply in a sibling chat with the same person (SMS vs iMessage), and a failed outgoing row (`error` ≠ 0) counting as a reply: both need decisions on the HomeChat side.
- Holding chat-less rows by first-seen time rather than message date, and an alarm when many bodies fail to decode (a format change): plausible, not observed.
- Other non-zero `associated_message_type` values (stickers), unknown `chat.style`, and ambiguous Contacts matches: low impact.

## Open question for Alex
- After a database reset (task 2), how should the companion start again? Options: Alex clears the cursor so the next batch is a first run (3-day window), with HomeChat accepting a lower cursor on `first_run`; or HomeChat gets an explicit reset route. Either needs HomeChat's side checked first.

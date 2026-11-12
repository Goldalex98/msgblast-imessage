# iMessage uplink contract (Mac ↔ HomeChat)

2026-11-08 · implements spec `2026-11-07-imessage-companion-design.md` §4.2 · phase 1 uses `POST /imsg/messages` only · HomeChat's design amendment in `homechat-bot` implements the server side against this file.

## Transport and auth

- **Base URL:** `uplink_url` from the Mac's local config file (the HomeChat bot's public hostname). It is never written in this repo. HTTPS only; the Mac rejects `http://` and refuses redirects.
- **Routes:** everything is under `/imsg/`.
- **Auth:** `Authorization: Bearer <token>`.
  - One token per Mac, issued by HomeChat. The Mac keeps it in the macOS Keychain.
  - HomeChat stores only a hash and compares in constant time.
  - Revoking a token is one server-side switch.
  - A token can only post messages and (phase 3) fetch sends for its own `device_id`.
- **Encoding:** `Content-Type: application/json`, UTF-8. Dates are ISO-8601 UTC strings ending in `Z`.

## `POST /imsg/messages` (phase 1)

### Request body

```json
{
  "device_id": "mac-1a2b3c4d",
  "batch_id": "6f1c2d9e-3a4b-4c5d-8e7f-0a1b2c3d4e5f",
  "cursor": 1234,
  "first_run": false,
  "threads": [
    {
      "guid": "iMessage;+;chat000000000000000000",
      "kind": "group",
      "display_name": null,
      "participants": [
        {"handle": "+15550100001", "name": "Test Person"},
        {"handle": "test@example.invalid", "name": null}
      ],
      "participants_fingerprint": "<64 lowercase hex characters>"
    }
  ],
  "messages": [
    {
      "guid": "00000000-0000-0000-0000-000000000001",
      "rowid": 1234,
      "thread_guid": "iMessage;+;chat000000000000000000",
      "from_me": false,
      "sender_handle": "+15550100001",
      "sent_at": "2026-11-08T21:30:00Z",
      "kind": "text",
      "text": "Are you free Saturday?",
      "reply_to_guid": null,
      "attachment_count": 0
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `device_id` | The Mac's stable ID, `mac-` + 8 hex characters, made on first launch. |
| `batch_id` | A fresh UUID per post attempt. For logs only; idempotency is per message `guid`. |
| `cursor` | The highest `chat.db` ROWID the Mac scanned for this batch. It can be above the last message's `rowid` when rows with no chat, or system rows (non-zero `item_type` with no text, body or attachments, such as group membership changes), were passed over. A saved cursor above the database's highest ROWID stops the Mac with a visible status instead of reading (reader-hardening plan, 2026-11-10). |
| `first_run` | `true` while the Mac has never had a batch accepted. The window is then the last 3 days. |
| `threads` | Every thread that this batch's messages reference, once each. |
| `threads[].kind` | `direct` (one other person) or `group`. |
| `threads[].display_name` | The group's own name, or `null` when it has none (most groups). Build a label from participant names instead. |
| `threads[].participants` | The other people, excluding Alex. `name` comes from the Mac's Contacts and is `null` when unknown or when Contacts access is off. |
| `threads[].participants_fingerprint` | Lowercase hex SHA-256 of the participants' normalized handles, sorted and joined with `\n`. Normalizing means: trim, lowercase. Emails stay as they are. A handle made only of digits and `+()- .` keeps only its digits and `+`. Phase 3 compares this before any send. |
| `messages[].rowid` | The `chat.db` ROWID. Rising, but with gaps. |
| `messages[].from_me` | `true` for Alex's messages, from any of his devices. Any `from_me` message in a thread counts as "Alex replied". |
| `messages[].sender_handle` | The sender's handle for inbound messages, `null` for Alex's. |
| `messages[].kind` | `text`; `reaction` (a tapback, `text: null`); `attachment_only` (no text, ≥1 attachment); `unreadable` (no text could be recovered); `skipped` (a short-code sender or a verification-code message, `text: null`). |
| `messages[].text` | Scrubbed on the Mac: anything shaped like a US SSN is `[SSN removed]`. At most 4000 characters; longer text is cut and ends `…[truncated]`. |
| `messages[].reply_to_guid` | The thread-originator GUID for an inline reply, else `null`. |
| `messages[].attachment_count` | A count only. File names and files are never sent. |

### Responses

| Status | Body | The Mac does |
|---|---|---|
| `200` | `{"accepted_cursor": <int>}` | Saves the cursor as `min(accepted_cursor, batch cursor)` and reads on. |
| `401` | any | Stops uplinking until the token or URL changes. Status: "token rejected". |
| `413` | any | Stops and shows the error (a batch over the limits is a Mac bug). |
| `422` | any | Stops and shows the error (a schema mismatch). |
| `429`, `5xx` | any | Keeps the cursor and retries: 5 s, doubling, at most 300 s. |
| no response | — | Same as `5xx`. Offline is normal, not an error. |

- **Idempotency:** the server stores each message by `guid` once. A replayed batch, which happens after a crash between the server's commit and the Mac saving its cursor, is harmless and still answers `200`.
- **Order:** one batch at a time, in rising `cursor` order.
- **Limits:** ≤ 200 messages per batch; body ≤ 1 MB. The server may reject larger with `413`.

## Sends (phase 3)

Fixed by `docs/superpowers/plans/2026-11-11-phase3-mac-approved-replies.md` (Task 1). One approval sends one message (design §5.5). The Mac fetches only while Alex has "Send approved replies" on and the companion isn't paused.

### `GET /imsg/sends?wait=25`

A long-poll: HomeChat holds the request up to `wait` seconds (at most 25) and answers as soon as a send is ready.

```json
{
  "sends": [
    {
      "send_id": "snd-0001",
      "thread_guid": "iMessage;-;+15555550100",
      "participants_fingerprint": "6b3a…",
      "text": "Sounds good, see you at 6",
      "text_sha256": "<lowercase hex SHA-256 of the UTF-8 text>",
      "approved_at": "2026-11-12T14:00:00Z",
      "expires_at": "2026-11-12T14:10:00Z"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `send_id` | Issued by HomeChat, unique, never re-issued. The Mac never dispatches a `send_id` twice, whatever HomeChat sends back. |
| `thread_guid` | An existing thread the Mac uplinked. |
| `participants_fingerprint` | As in `threads[]` above, taken when the item was created. The Mac refuses the send if the thread's fingerprint is different now. |
| `text` | The exact approved text, sent as is (not trimmed). |
| `text_sha256` | Computed by HomeChat from its stored approved text when it issues the send. The Mac recomputes it from `text` and refuses on a mismatch. |
| `approved_at`, `expires_at` | `expires_at` is at most 10 minutes after `approved_at`. The Mac refuses a send at or after `expires_at`, checked at fetch and again just before sending. |

Only unexpired sends without a stored result, for the token's own device, oldest first, 0 to 5 per page.

| Status | The Mac does |
|---|---|
| `200` | Handles each send in order, one at a time. More than 5 is a bad response. |
| `401` | Stops until the token or URL changes. |
| `429`, `5xx`, no response | Retries: 5 s, doubling, at most 300 s. |
| anything else | Stops and shows the status. |

### `POST /imsg/send-results`

```json
{"send_id": "snd-0001", "outcome": "sent", "anchor_guid": "<guid of the sent chat.db row>", "text_sha256": "<the Mac's own hash of the text>", "detail": "confirmed"}
```

`anchor_guid` is left out when there is none. `outcome` is `sent`, `not_sent` or `ambiguous`. HomeChat treats every outcome as final: `ambiguous` means "may or may not have sent: check Messages" and is never queued again. `detail` is always one of these codes, never free text:

| `detail` | Outcome | Meaning |
|---|---|---|
| `confirmed` | sent | Exactly one new outgoing row with the exact text, marked sent with no error. |
| `recovered_after_restart` | sent or ambiguous | The app stopped mid-send; on relaunch the read-back found exactly one confirmed match (`sent`) or not (`ambiguous`). Never re-sent. |
| `expired` | not_sent | At or after `expires_at`. |
| `approval_too_long` | not_sent | `expires_at` more than 10 minutes after `approved_at`. |
| `hash_mismatch` | not_sent | `text_sha256` doesn't match `text`. |
| `text_rules` | not_sent | Empty after trimming, over 4000 characters, or a control character other than tab, LF, CR. |
| `daily_cap` | not_sent | 30 send attempts in the last 24 h on this Mac. |
| `paused`, `sends_off` | not_sent | Paused, or sends switched off, between fetch and send. |
| `thread_missing` | not_sent | The thread isn't in `chat.db`. |
| `thread_changed` | not_sent | Its participant fingerprint changed. |
| `not_imessage` | not_sent | The thread isn't iMessage (SMS and RCS are refused). |
| `bad_target` | not_sent | A thread GUID or handle the Mac won't pass to AppleScript. |
| `automation_denied` | not_sent | macOS Automation permission for Messages is off. |
| `script_refused` | not_sent | Messages' identity check refused before sending, or the script didn't start. |
| `messages_error` | not_sent | The new row exists but Messages marked it failed. |
| `no_readback` | ambiguous | The script reported the send but no matching row appeared within 20 s. |
| `multiple_matches` | ambiguous | More than one new outgoing row with the exact text. |
| `not_confirmed` | ambiguous | One matching row, not marked sent within 20 s. |
| `script_uncertain` | ambiguous | The script timed out or failed after it may have sent, and no confirmed row appeared. |
| `database_unreadable` | ambiguous | `chat.db` couldn't be read after the send. |

| Status | The Mac does |
|---|---|
| `200` | Marks the result reported. The same body again also gets `200`. |
| `404` | Unknown `send_id`: marks it reported and shows it. |
| `409` | A different result is already stored for this `send_id`: stops sending and shows it. |
| `401` | Stops until the token or URL changes. |
| `429`, `5xx`, no response | Retries: 5 s, doubling, at most 300 s. |

## Known gaps (phase 1)

- Edits, unsends and delivery-state changes rewrite existing rows. The cursor only sees new rows, so they aren't uplinked.
- Times are the Mac's database times. Messages Alex sends from his iPhone carry the iPhone's send time.
- Contacts names are refreshed every 10 minutes, so a contact renamed in between is uplinked under the old name until then.

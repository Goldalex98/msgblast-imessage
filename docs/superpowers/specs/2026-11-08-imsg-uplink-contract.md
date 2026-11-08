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
| `cursor` | The highest `chat.db` ROWID the Mac scanned for this batch. It can be above the last message's `rowid` when rows with no chat were passed over. |
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

## Reserved for phase 3 (shape only)

- `GET /imsg/sends?wait=25`: long-poll for approved sends for this device. Each carries `{send_id, thread_guid, participants_fingerprint, text, approved_at, expires_at}`.
- `POST /imsg/send-results`: body `{send_id, outcome, anchor_guid?, detail}`, where `outcome` is `sent`, `not_sent` or `ambiguous`. The same body gives `200`; a different body for the same `send_id` gives `409`.

These are fixed by the phase 3 plan, not here.

## Known gaps (phase 1)

- Edits, unsends and delivery-state changes rewrite existing rows. The cursor only sees new rows, so they aren't uplinked.
- Times are the Mac's database times. Messages Alex sends from his iPhone carry the iPhone's send time.
- Contacts names are refreshed every 10 minutes, so a contact renamed in between is uplinked under the old name until then.

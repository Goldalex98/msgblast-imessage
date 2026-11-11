# Phase 3 send notes: what to borrow, what to avoid

**Status:** input for the phase 3 (Replies) plan. Not approved and no behaviour change; the design (§4.1, §4.2, §5.5) still rules. Written 2026-11-10 after reading the send code of other open-source iMessage tools. Ideas only: no code is copied.

**Sources read:** `jaredzimmerman/iMessageMCP` (`src/send.ts`, `runtime.ts`, SECURITY.md); `Prpking/imessage-mcp` branch `mac-studio` (`src/send.ts`, `docs/sending.md`); `daveremy/imessage-mcp` (`applescript.ts`); `JonathanRReed/Apple-MCPs` (automation bridge); `BlueBubblesApp/bluebubbles-server` (`messagePromise.ts`). Compared with our `MessagesSendScript.swift`, `MessageSender.swift`, `companion/spikes/send_probe.py` and spikes (c)/(d).

## Borrow

| # | Pattern (source) | Our state | For the plan |
|---|---|---|---|
| 1 | A durable record per send, created exclusively before the AppleScript runs and updated by an atomic rename afterwards (Prpking) | Partly: the server's `send-results` is idempotent (§4.2); the Mac keeps nothing | Mac-side record keyed by HomeChat's `send_id`, written before dispatch. A record still `in_progress` at launch is reported `ambiguous`, never re-sent. |
| 2 | Text and target as script arguments (`on run argv`), never inside the script source (iMessageMCP, Prpking) | No: `MessagesSendScript.literal()` escapes `\`, `"`, CR and LF into the source | Pass chat GUID, handle and text as arguments; check the GUID and handle shapes (no leading `-`). |
| 3 | Text rules: non-empty after trim, at most 4000 characters, no control characters other than tab, LF and CR (iMessageMCP) | No limit in §5.5 or the script | Enforce on HomeChat at approval time and again on the Mac. |
| 4 | Read-back with a ROWID baseline: note the highest outgoing ROWID in the chat before sending, then accept only a later row, and read its `error`, `is_sent` and `is_delivered` (iMessageMCP) | Partly: `anchor_guid` (§4.2); the probe matches `m.text` only and reads no state columns | Require ROWID above the baseline and one matching row. `error` ≠ 0 means `failed`. Match the decoded `attributedBody` as well as `text`, since outgoing `text` may be NULL on current macOS (stated by iMessageMCP; not checked on our data). |
| 5 | A real text binding: HomeChat stores a SHA-256 of the approved text; the Mac hashes what it fetched and echoes it in the result | Not in the design | Add the hash to the send record and the result. |
| 6 | Audit without message text: time, chat id, length, hash, status (iMessageMCP) | §5.5 keeps the exact text on HomeChat | Mac log holds hash and length only; the exact text stays on HomeChat. |
| 7 | Count the attempt, not the success, against the cap; cap outstanding approvals (iMessageMCP: 16 pending, 5 minute expiry) | Cap of 30/day and a 10 minute expiry (§5.5) | Count attempts; cap pending approvals; check expiry at execution as well as at fetch. |
| 8 | Ambiguity as a result of its own (`handed_to_messages`, `unknown`, `AUTOMATION_TIMEOUT`) | Yes (`SendFailure.ambiguous`, §4.1) | Keep, with the wording "check Messages". Optionally add a stderr marker just before `send`, so a kill before that point can be told apart as not sent. |

Already as strict or stricter: chat-GUID targeting only, with the identity re-check (others fall back to a participant handle); iMessage only (SMS and RCS refused); no focus steal (spike d; the others don't activate Messages either); server-issued `send_id` (Prpking lets the model pick its idempotency key).

## Avoid

- **Timeout reported as "not sent".** iMessageMCP and daveremy kill `osascript` after 15 s and report that Messages did not accept the send, with no read-back. The message may already have gone. BlueBubbles' 2 minute timeout has the same shape.
- **Taking the newest outgoing row when no text matches** (iMessageMCP `outgoingAfter`). This can pick a message Alex sent from his phone in the same window. It also reports `sent` when no state column ever turned positive. Require a body match and a positive signal; otherwise `ambiguous`.
- **A hash check inside one process** (iMessageMCP compares a digest it computed from the same in-memory text). It proves nothing; see Borrow 5.
- **An idempotency key chosen by the caller** (Prpking's model-supplied `request_id`). A fresh id bypasses it.
- **Escaping text into script source** (JonathanRReed escapes only `\` and `"`; daveremy builds JXA from `JSON.stringify`). Also "inspect and retry" wording after an automation failure, which invites a retry.

## Questions for Alex (to settle in the phase 3 plan)

1. A send record still `in_progress` at launch: always `ambiguous` with an alert, or resolved to `sent` when exactly one matching row exists after the baseline?
2. How long may the Mac wait for a positive read-back (`is_sent` with `error` = 0) before reporting `ambiguous`: about 30 s, as the probe does?
3. Is "delivered" worth a WhatsApp message, or is "sent" enough?
4. Mac-side audit: hash and length only (recommended), or the exact text too?
5. Does phase 3 stay iMessage-only, for direct and group threads?

## Reader follow-ups that need HomeChat (from the same comparison)

These change the uplink contract or HomeChat's flag logic, so they go through `homechat-bot`:
- Edits, unsends and retractions are invisible to the cursor (contract "Known gaps"). An unsent question stays flagged.
- The same person in two chats (SMS and iMessage): a reply in one doesn't clear a flag raised in the other.
- A failed outgoing row (`error` ≠ 0) goes up as Alex's message and can clear a flag. A field for the send state would let HomeChat ignore it.
- Restarting after a Messages database reset (reader-hardening plan, task 2).

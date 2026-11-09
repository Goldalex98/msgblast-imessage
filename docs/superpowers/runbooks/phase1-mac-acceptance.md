# Phase 1 Mac acceptance: read and uplink

2026-11-08 · plan `docs/superpowers/plans/2026-11-08-phase1-mac-read-and-uplink.md` · contract
`docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md`

This checks the Mac half against a live HomeChat. It needs HomeChat's phase 1 work first: the
`POST /imsg/messages` route, a device token issued for this Mac, and the message store. Nothing here
sends an iMessage.

Alex runs every step at the Mac. HomeChat-side checks are made on the server with HomeChat's own
tooling, never from this repo or a dev session. Don't paste the address, the token, names,
numbers or message text into this repo, a commit, a PR or a chat with Claude: report results as
pass or fail with counts.

## Before you start

- "msgblast iMessage.app" is installed in `/Applications`, built from the merged phase 1 commit with
  `python3 -I companion/build_fork_app.py --sha <sha> --output ~/msgblast-imessage-builds`.
- System Settings › Privacy & Security › Full Disk Access lists "msgblast iMessage" as on.
- Contacts access is optional. Without it names go up as unknown and HomeChat labels threads by
  handle.

## Set up

1. Open the app, then Settings (⌘,). The first section is **iMessage companion**. It reads
   "Not set up".
2. Open **Details**. Paste the HomeChat address (`https://…`) and the device token, then **Save**.
   The token field then shows "Saved", and the device ID appears.

## Checks

| # | Do | Pass when |
|---|---|---|
| 0 | Before saving anything: look at the section, turn **Paused** on, quit and reopen the app, open Settings again. | The section is first in Settings and reads "Not set up". Paused is still on after the relaunch (turn it off again). Details shows Full Disk Access as Allowed. |
| 1 | Wait up to 30 s after saving. | The status line goes from "Uplinking" to "Up to date", and "Last uplink … · N messages" shows. |
| 2 | On the server, list what HomeChat stored for this device. | It holds the last 3 days of threads, groups included, and nothing older. The count roughly matches the Mac's message count for 3 days. |
| 3 | Have the test contact send a text to this Mac's Apple ID. | It is in HomeChat's store within 10 s of arriving in Messages. |
| 4 | Turn **Paused** on and have the test contact send another text. Wait 1 minute. Turn **Paused** off. | Nothing arrives while paused. After unpausing, the text arrives within 10 s. The toggle is still on after quitting and reopening while paused. |
| 5 | Quit the app. Have the test contact send 2 texts. Wait 5 minutes and reopen the app. | Both texts arrive once each. HomeChat shows no duplicates (it stores by message GUID). |
| 6 | Turn Wi-Fi off. Have the test contact send a text (it reaches the Mac later). Turn Wi-Fi on. | While off, the status reads "Mac offline, retrying in … s" with the wait growing toward 5 min. After Wi-Fi is back, the text arrives by the next retry. |
| 7 | Send a text with an SSN-shaped test number, for example `123-45-6789`, from the test contact. | HomeChat stores `[SSN removed]` in its place. |
| 8 | Have the test contact send a fake verification-code text, for example "Your code is 482913". | HomeChat stores it as `skipped` with no text. |

## If something fails

- **"Needs Full Disk Access"**: turn Full Disk Access on for "msgblast iMessage", quit and reopen.
- **"Stopped: token rejected"**: issue a new token in HomeChat, paste it into Details and **Save**.
  Saving a new token or address restarts the uplink.
- **"Stopped: rejected (HTTP 413/422)"**: a schema or size mismatch between the Mac and HomeChat.
  Note the status code and the app's build SHA. Don't retry by hand.

## Result

Record pass or fail per check, with the build SHA and the date, in `.claude/LOG.md`. No content.

Phase 1 as a whole is accepted only when a real unanswered text shows up on the desk and in the
update, and a real reply clears it, seen on Alex's phone and re-read on the desk. That part needs
HomeChat's flagger, update and desk items, built in `homechat-bot`.

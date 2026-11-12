# Phase 3 Mac acceptance: approved replies

2026-11-11 · plan `docs/superpowers/plans/2026-11-11-phase3-mac-approved-replies.md` · contract
`docs/superpowers/specs/2026-11-08-imsg-uplink-contract.md` ("Sends (phase 3)")

This checks the Mac half of phase 3 against a live HomeChat. It needs HomeChat's phase 3 half first:
- the `GET /imsg/sends` and `POST /imsg/send-results` routes;
- the send queue, with `send_id`, `text_sha256` and a 10-minute `expires_at`;
- the `N yes` / `N edit:` flow with its exact-text echo;
- outcome messages in Alex's WhatsApp 1:1.

**These checks send real iMessages.** Each one runs only after Alex types his yes in chat for that check. Each goes to a test contact or a test group he chooses, never anyone else. The recipients' names and numbers stay out of this repo, commits, PRs and any chat with Claude. Report results as pass or fail with counts and outcome codes.

## Before you start

- **Build** "msgblast iMessage.app" from the merged phase 3 commit with `companion/build_fork_app.py` into its own folder.
- **Signing:** check that `codesign` verifies it and that its designated requirement matches the installed copy's, so the Full Disk Access and Automation grants carry over.
- **Install:** quit the running app first, keep the old copy outside `/Applications` for rollback, then install and open.
- **Status:** Settings › iMessage companion reads "Up to date".
- **Off by default:** "Send approved replies" is off. Under Details, Replies reads "Off".
- **Focus baseline:** note which app is frontmost before each send check; it's needed for check G.

## Checks

Turn on **Send approved replies** before check B. For each send, read the outcome in three places:
- the WhatsApp outcome message;
- the Mac's Details "Last reply";
- HomeChat's counts-only readback: `outcome`, `detail` and whether there's an anchor, never the text.

**A. Off means nothing goes out.**
- With the switch off, approve one reply to the test contact.
- Pass:
  - nothing is sent;
  - after 10 minutes HomeChat reports it not sent (Mac offline);
  - the Mac's send ledger folder (`companion-sends` in the app's support folder) has no file for it. Count files only; don't open them.

**B. 1:1 reply.**
- Switch on, then `N edit:` a reply to the test contact that includes an accented letter and an emoji (for example `Café at 6 👍🏽`). This checks that non-ASCII text arrives intact, which unit tests prove only for the test runner's locale.
- Then send a second reply with `N yes` on a plain suggested reply.
- Pass:
  - the test contact receives each reply exactly once, the first with its accent and emoji intact;
  - HomeChat stores `sent` / `confirmed` with an anchor;
  - the phase 1 uplink stores the outgoing message;
  - the flag clears, seen on Alex's phone and re-read on the desk.

**C. Group reply.** The same as B, in the test group. Pass: each member receives it once, and the result is `sent` / `confirmed`.

**D. Mac offline.**
- Turn off the Mac's network, approve a reply, and wait more than 10 minutes. Then turn the network on.
- Pass:
  - HomeChat reports "not sent, Mac offline";
  - the Mac never sends it after it reconnects.

**E. Quit during the read-back.**
- Approve a reply, and quit the app within about 10 s of the send (inside the 20 s read-back). Reopen it.
- Pass:
  - the result is `sent` / `recovered_after_restart` (or `ambiguous` / `recovered_after_restart`);
  - the test contact has exactly one copy;
  - no second send happens on later cycles.

**F. Group changed after approval.**
- Approve a group reply, then add or remove a member before the Mac picks it up. Pausing the Mac for the change works.
- Pass:
  - `not_sent` / `thread_changed`;
  - nothing is sent.

**G. Focus.** During B and C, Messages is not brought to the front, and the frontmost app is the same before and after the send (spike d).

## Not covered here

- **SMS refusal:** only covered if a test SMS thread exists. Unit tests cover `not_imessage`.
- **Automation permission off:** not run, so permissions aren't reset to produce evidence. Unit tests cover `automation_denied`.
- **The daily cap of 30**, an exact-text near-miss, and two matching rows: unit tests only.
- **Overnight and Low Power Mode behaviour of the send loop.**

## Rollback

- Turn **Send approved replies** off. This alone stops every fetch and send.
- For a full rollback, quit the app and restore the kept copy into `/Applications`.
- Records in `companion-sends` stay as they are. They hold no message text and are pruned 90 days after they're reported.

# Phase 0 spike results

Percentages and verdicts only (plan rule: no absolute message counts). Every run is on the MacBook, against the real `chat.db`, read-only, with counts-only reports. Window: the last 14 days, reactions excluded.

| Spike | Question | Result | Verdict |
|---|---|---|---|
| (a) | How many recent bodies are only in `attributedBody`, and does the decoder recover them? | 3.3% `attributedBody`-only; the decoder returned a string for 100% of them. 0.2% have neither column, with no attachment. On rows with both, 96.7% decode exactly to `text`. | Needed; phase 1 uses `NSUnarchiver` (Alex, 2026-11-08) |
| (b) | Can group threads be read with a sender for every inbound message? | 100% of inbound group messages resolve to a sender handle; 0% style/participant mismatches; 11% of active groups have a display name; 1.2% of group messages carry a reply link. | Pass for reading |
| (f awake) | iPhone-to-Mac sync delay while the Mac is awake | All sends seen within one 2 s poll: median 0.6 s, max 1.6 s, all iMessage, no sleeps. | Pass: sync isn't the bottleneck |
| (g) | Do Full Disk Access and Automation survive a rebuild from a new commit? | Two builds from different commits, both signed with the self-signed local certificate: same designated requirement (bundle ID plus certificate, no code hash), new code hash, and both grants still shown by the app after reinstalling over the old copy. | Pass: signing method settled |
| (c) | Can the identity-checked AppleScript path send to an existing 1:1 and group thread exactly once, and refuse a changed member set? | 1:1 and group (Messages running and not running): sent, each found exactly once in `chat.db` within 0.5–2.6 s. Tampered member list: refused before submitting (9004), nothing sent. | Pass: group sends go (spec §10.8) |
| (d) | Does a send pull Messages to the front? | Terminal stayed frontmost before and after every send it measured (1:1, and group with Messages quit). With Messages quit, the send launched it in the background and took 2.3 s instead of 0.2 s. | Pass: no focus steal |

## (a) Bodies stored only in `attributedBody` (2026-11-08)

- One message in 30 has no `text`, so without a decoder upstream's "[Message body unavailable]" would hide real messages. A decoder is required in phase 1.
- "Decoded" only means the decoder returned a UTF-8 string. Whether that string is the right text can only be checked on rows that have both columns, and there 3.3% differ. Those differences are unexplained: the probe doesn't say how they differ, by design.
- Likely causes, unconfirmed: `text` holding U+FFFC placeholders for attachments or mentions, edited messages whose `attributedBody` holds a different version, or a first-`NSString` match that isn't the body.
- **Phase 1 decoder decision (Alex, 2026-11-08):** use the system's own typedstream reader in Swift (`NSUnarchiver` into `NSAttributedString`), not a port of the byte scanner. The Python decoder stays as the test oracle for synthetic fixtures. No mismatch-shape probe is needed for this choice.

## (b) Reading group threads (2026-11-08)

- Group chats are about a third of all chats, and style 43 / 45 always agree with the participant count, so style is a safe group test.
- Active groups by size: 39% with 2 other people, 33% with 3, 22% with 4–6, 6% with 7 or more.
- Every inbound group message names its sender, so "waiting on Alex" can say who asked.
- Only about one active group in nine has a display name, so phase 1 must build group names from participants' Contacts names (spec §5.2), never from handles.
- Reply links are rare, so phase 1 can treat them as a hint, not a requirement.
- This covers reading only. Group sends are spike (c), Task 10.

## (f) awake: iPhone-to-Mac sync (2026-11-08)

- 10-minute watch, polling every 2 s. It counts every message Alex sent from any device in that window (the 3 test texts plus his other sends and tapbacks), timed from the message's own timestamp to the poll that saw it.
- Every delay fell inside one poll interval (median 0.6 s, max 1.6 s), so the true sync delay is under the probe's 2 s resolution. The two clocks are both network-synced; skew isn't measured.
- **Phase 1 effect:** while the Mac is awake, "Alex replied on his phone" can clear a flag within seconds, so phase 1's reply detection is limited by its own polling, not by iCloud sync. The 24 h "replied on your phone?" fallback (spec §10.1) waits on the asleep run (Task 11).
- Only iMessage was seen; SMS relay timing is untested.

## (g) Permission grants across rebuilds (2026-11-08)

- Built twice through `companion/build_fork_app.py`, from two different docs commits, each re-signed with the self-signed "local signing" certificate and reinstalled over the previous copy in `/Applications`.
- `sign_check.py compare`: `same_requirement=true`, `grants_kept=true`. Full Disk Access and Automation → Messages stayed granted on the app's own permission screen (as Alex read it) with no re-grant. The code hash changed between builds, as expected.
- **Signing decision:** the self-signed local certificate is enough. Xcode Personal Team signing and the paid Developer Program aren't needed for phase 1.
- One-time setup per Mac: `codesign` must be allowed to use the certificate's key. From a process with no window (Claude's shell) a new key fails with `errSecInternalComponent`; one build from Terminal.app with Always Allow fixes it for later builds.
- The first pair was redone as build 2 → build 3 because build 1's record wasn't saved.

## (c) and (d) Real sends and focus (2026-11-08)

- Run by Alex in Terminal.app after his typed yes, to a 1:1 test chat and a group with two other people; every send needed `SEND` typed at the prompt. 3 real sends of the 6 allowed; the tampered run was refused, so its slot was released.
- c1, 1:1, Messages open: `sent`, `anchor_rows=1`, found in 0.6 s; arrival confirmed.
- c2, group, Messages open: `sent`, `anchor_rows=1`, found in 0.5 s; arrival confirmed by Alex. Its focus readings were lost to a probe bug (below).
- c3, group, Messages quit: `sent`, `anchor_rows=1`, found in 2.6 s; Messages was launched by the send and stayed in the background; arrival confirmed.
- c4, group with one expected member swapped for a fake address: `not_sent`, code 9004 (member check), before any submission.
- **(d) verdict:** Terminal stayed frontmost on c1, c3 and c4, so a send doesn't raise Messages, even when it has to launch it. Phase 1's send executor can run from the background app.
- **Group sends:** go. The identity, service, member-count and member checks all ran on a real group and refused a changed member set.
- Probe fix found here: macOS 27's `lsappinfo` output broke the frontmost check (all `unknown` on c2); fixed test-first before c1 and c3.
- Alex confirmed c1, c2 and c3 all arrived. Not proven: SMS sends; sends from the fork app itself rather than `osascript` in Terminal.

## Still to run

- (e) reach and (f) asleep (Task 11).

# iMessage companion: design

2026-11-07 · from a brainstorm with Alex · **approved by Alex 2026-11-07 13:00 ET** · nothing built yet; Alex re-reviews it while writing the build plan

This file lives in HomeChat's `research_notes/` until the new project exists. Then it moves to that repo's `docs/superpowers/specs/`. HomeChat's half also needs its own design amendment in `homechat-bot` (§9).

Background research: `research_notes/msgblast-evaluation.md` (same folder).

Labels: **Alex** = decided by Alex in the brainstorm. **My call** = Claude's default, which Alex can override.

## 1. Intent

Alex gets a lot of texts. He reads one on the go, tells himself he'll answer later, and forgets. Typical cases are a question, a request for his availability, a date for something, or a plain check-in. When a text carries a date, he often doesn't add it to the calendar or check whether he's free, because opening the calendar is a chore. (Alex)

He wants HomeChat and Home Desk to catch these:
- Flag every text where someone is waiting on him.
- Put each one on the desk.
- Give him a readable update in WhatsApp with one-tap actions.
- Clear each flag by itself once he replies.
- Check the calendar for him when a text mentions a date.
- Let him send a reply, typed or AI-suggested, but never without his approval. (Alex)

**Success:** no text he meant to answer is forgotten, and he never ticks anything off by hand when he replied anyway.

## 2. Goals, non-goals, anti-goals

**Goals**
- Read all of Alex's iMessage conversations on his MacBook: 1:1 and group chats (Alex).
- Flag texts waiting on him, put them on Home Desk, and summarise them in his HomeChat WhatsApp 1:1 with actions (Alex).
- Clear a flag automatically when he replies in that thread (Alex).
- Spot dates and availability questions, check his Google Calendar, say "free" or what clashes, and offer to add the event (Alex).
- Send replies (his own words or an AI suggestion) back to the iMessage thread, only after he approves the exact text (Alex).
- Duet (claude.ai) can see the waiting texts and help, through the existing HomeChat connector (Alex: "duet is good for that too").

**Non-goals (v1)**
- Muse. It comes later, read-only, and only after the connection test in `docs/research/Muse and Dot MCP connections/report.md` passes (my call, from that research and the screen-takeover concern).
- His wife's texts (they aren't on his Mac), SMS-only threads as send targets, starting new conversations, attachments in replies (my call).
- Using msgblast's other agents (Muse/ChatGPT apps, websites, CLIs) from HomeChat. The fork keeps them for Alex's own use at the Mac (§3).

**Anti-goals (a failure even if it works)**
- Anything sent under Alex's name without his approval of the exact words (Alex).
- A reply landing hours late and out of context (my call).
- A Social Security number reaching Claude, the desk or WhatsApp (Alex).
- The tool getting in Alex's way on his MacBook: taking over the screen, stealing focus, or marking texts read (Alex's concern; my call on read state).
- Nag spam: a ping per text (my call; Alex asked for a summary).
- Personal data (names, numbers, HomeChat host, tokens) in the public repo (Alex chose a public fork; my call on the hygiene).

## 3. Constraints and facts

**The Mac app is a public fork of [mgalpert/msgblast](https://github.com/mgalpert/msgblast)**, GPL-3.0-only (Alex: public fork, no private/public split).
- The fork keeps the whole app, so Alex keeps msgblast's own features at the Mac, and the fork can keep merging upstream fixes. The author ships fixes often (557 commits in 5 weeks).
- Our additions should live in new, self-contained files where possible, to keep upstream merges cheap.
- A generic, opt-in local automation API may later be offered upstream as a separate PR (see the evaluation). It is not required for this project.
- Turn off Sparkle auto-update in the fork's builds (`SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` are both `true` upstream).
- Leave the upstream telemetry and feedback opt-ins off in Alex's build (my call).

**What msgblast already provides:**
- a read-only `chat.db` reader that polls `PRAGMA data_version`, folds tapbacks, follows reply threads and reads delivery and error state;
- an AppleScript send to an existing chat, with an identity check inside the script;
- a send result that is sent, not sent or ambiguous, and never resends an ambiguous one;
- a step that ties each send to its row in the message history;
- probes for Full Disk Access and Automation permission.

**What msgblast does not provide:**
- **Group chats.** Both reading and sending are 1:1-only today (`Models.swift:36`, `MessageSender.swift:6`).
- **Bodies stored only in `attributedBody`.** It shows "[Message body unavailable]" for those.
- **A global "last seen" cursor.**
- **Headless or background operation, or any external API.**

**Screen:**
- iMessage reads are database reads.
- iMessage sends don't activate Messages (no `activate` in the script). Whether macOS raises it anyway is unverified.
- Only msgblast's native-app agents (Muse, ChatGPT, Dots, Grok Bot, Wabi) take over the screen. This project never drives them.

**The Mac:**
- Alex's MacBook, which Alex says he will leave on with the app running.
- It needs Full Disk Access (to read `chat.db`) and Automation → Messages.
- Asleep, offline or app-closed is a normal state, not an error.

**HomeChat** (Linux container on OVH, `homechat-bot`), relevant rules from its `CLAUDE.md` and design:
- One guarded sender for WhatsApp.
- Runs started by untrusted content are read-only, and only Alex's own text or `yes` produces actions.
- Labels: `shared` / `alex-only`.
- Never put account numbers, codes, passwords or medical details in a message or desk item.
- Secrets never in git.
- **Rule change needed:** "the bot never replies to anyone". Approved iMessage replies need an explicit, narrow exception (§6).

**Home Desk writes** go through HomeChat's desk routine.
- Today it allows `set` only for new `cap-…` IDs with `source: "capture"`, and `update` only on `status`, `snoozeUntil`, `closedAt`, `dueDate` and `tier`.
- Text-sourced items therefore need a new allowed source and ID prefix in the desk client and the routine. Routine changes keep their own approval.

## 4. Architecture

```
MacBook                                         OVH (HomeChat)                       Alex
┌────────────────────────────┐   HTTPS, out    ┌──────────────────────────────┐
│ msgblast fork              │ ──────────────▶ │ /imsg routes (new)           │
│  • reader (all chats)      │  new messages,  │ store: threads, recent msgs  │
│  • scrubber (SSN, codes)   │  read state     │ flagger (claude -p, batch,   │──▶ Home Desk items
│  • uplink client           │ ◀────────────── │   read-only, drafts replies) │
│  • send executor           │  approved sends │ calendar check (read)        │──▶ WhatsApp 1:1 update
│  • status pane (UI)        │ ──────────────▶ │ approval + send queue        │◀── "1 yes" / "1 edit: …"
└────────────────────────────┘  send results   │ Duet tools (connector)       │◀── Duet
                                               └──────────────────────────────┘
```

### 4.1 Mac side (the fork)

- **Reader:**
  - extends msgblast's `chat.db` adapter to group chats;
  - adds an `attributedBody` decoder;
  - keeps a global ROWID cursor, persisted, so nothing is missed across restarts.
- **What it reads:** for each message, the thread GUID, the thread type (1:1 or group), participant handles and display names (from Contacts when allowed), sender, direction (in/out), time, text and the reply-to GUID. Attachments are named only, never uploaded (my call).
- **Scrubber,** run on the Mac before anything leaves it:
  - replaces anything shaped like a US SSN with `[SSN removed]` (Alex: the only thing he doesn't want in Claude);
  - also marks verification-code, short-code and bank-alert threads as `skip_flagging`, because nobody is waiting on him there (my call).
  - Those threads are still uplinked so that his replies there can clear nothing by mistake. Simpler alternative for the builder: don't uplink them at all.
- **Uplink:**
  - outbound HTTPS only, to HomeChat;
  - no listening port, no tunnel (my call; avoids exposing the Mac);
  - a per-device bearer token in the macOS Keychain;
  - the HomeChat URL in local config outside the repo.
- **Send executor:**
  - fetches approved sends, re-checks the target thread's identity (msgblast's preflight, extended to groups: same chat GUID, same participant set), sends via AppleScript and reports `sent` / `not_sent` / `ambiguous` with the history-row anchor;
  - never retries `ambiguous`;
  - refuses a send whose approval is older than the expiry (§5.5).
- **Status pane in the app:** connected or not, last uplink, permissions, a pause switch (stop reading and sending), recent sends.
- **First run:** uplink only the last 3 days, so the old backlog is never flagged (my call; mirrors HomeChat's "never answer a backlog").

### 4.2 Interface (Mac ↔ HomeChat)

Three routes on HomeChat, behind its existing Caddy/Cloudflare edge (exact edge rules: §8 and the builder). Field names are the builder's; the shape is my call.

- `POST /imsg/messages`
  - Body: a batch of new messages plus `{device_id, cursor}`.
  - Idempotent on message GUID; a replayed batch is harmless.
  - Response: the accepted cursor.
- `GET /imsg/sends?wait=25`
  - Long-poll for approved sends for this device.
  - Each send carries `{send_id, thread_guid, participants_fingerprint, text, approved_at, expires_at}`.
- `POST /imsg/send-results`
  - Body: `{send_id, outcome, anchor_guid?, detail}`.
  - Idempotent: same body → 200; a different body for the same `send_id` → 409. This is msgblast's callback pattern.
- **Auth:** per-device bearer, stored hashed on OVH, compared in constant time. Revoking it is one server-side switch.

### 4.3 HomeChat side

- **Store:**
  - threads (GUID, type, display name, participants, last in/out times, Alex's last outgoing time);
  - a rolling window of recent messages per thread for context: last 30 messages or 14 days, whichever is smaller (my call);
  - flags, pending sends and the send audit.
- **Flagger:**
  - a batched run with **no tools at all**, trust `untrusted` (the texts are other people's words);
  - no desk client and no send tools;
  - the calendar lookup is a separate step (§10.3);
  - runs on threads with new inbound messages since the last run, every 30 min from 07:00 to 22:00 (my call).
  - For each thread it decides "waiting on Alex?" and why, extracts any date or time, and drafts a short suggested reply in Alex's voice.
  - Its output is data, checked by plain code against a schema.
- **"Waiting on you" rules** (my call; tune in the eval):
  - **1:1:** the latest inbound message asks something, proposes something, gives a date, or is a check-in, and Alex hasn't sent anything in that thread since.
  - **Group:** only when Alex is addressed: his name is mentioned, someone replies to his message, or someone asks a direct question after his last message. Otherwise every group question would flag.
  - **Grace period:** a thread flags only if unanswered for 3 h. A text with a date or time within the next 48 h skips the grace period.
- **Auto-clear:**
  - any outgoing message from Alex in that thread after the flagged message clears the flag and closes its desk item (`status: done`, `closedAt`).
  - Groups use the same rule (my call; judging whether the reply actually answered is error-prone).
- **Calendar:**
  - for a flagged date, a read-only Calendar lookup gives `free` or the clashing events;
  - "add" goes through HomeChat's existing calendar-add path, and only on Alex's `yes`.
- **Desk items:**
  - one per flagged thread, `source: "text"`, an ID prefix such as `txt-`;
  - fields: title (who and what), `why` (≤ 200 chars, scrubbed), `dueDate` if any, a lane or tier as the desk uses them;
  - closed by auto-clear, `done` or `dismiss`;
  - snoozed by `snooze`.
  - No message text beyond a short paraphrase (my call: the desk is shared with other routines).
- **WhatsApp update:**
  - to Alex's 1:1 only, labelled `alex-only`, never to the Home group or his wife (my call; matches the label rule);
  - twice a day, at 08:00 and 17:30 (my call; Alex asked for "a summary/update", times are open);
  - plus one quick nudge when a dated item within 48 h flags;
  - nothing during quiet hours (22:00–06:30).
  - Format: a numbered list. Each line gives who, how long ago and a one-line gist, plus free or clash for dates, the suggested reply, and the actions.
- **Actions** (replies in the 1:1; exact words are the builder's):
  - `N yes`: send the suggested reply.
  - `N edit: <text>`: send Alex's text instead.
  - `N add`: add the event to the calendar.
  - `N snooze` (until the next update), `N done` (no reply needed), `N show` (see the last few messages).
  - Every send action is confirmed back with the exact text and recipient before it goes out (§5.5).
- **Duet tools** (on the existing HomeChat connector):
  - read: list waiting texts with gists and suggestions;
  - write: propose a reply.
  - A Duet proposal never sends. It creates a pending send that Alex approves in his WhatsApp 1:1 (my call: one approval surface, from his phone, with the exact words). This can widen later if Duet's tool confirmations prove to show the exact text.

## 5. Behaviour details

### 5.1 Read state and presence
The Mac app never marks messages read, sends typing indicators or touches Messages' UI state (my call). Read state isn't used for flagging; only "has Alex sent a message since" counts.

### 5.2 Names
Thread and person names come from the Mac (Contacts or chat display names). In WhatsApp they appear as names, never as phone numbers. This follows HomeChat's `textrules` habit of not putting phone numbers in model text.

### 5.3 Calendar
Calendars to check are the ones HomeChat already uses (server config). If a date is ambiguous ("next Friday"), the gist says what it assumed.

### 5.4 Usage budget
The flagger's spend is counted in dollars on HomeChat's existing form-filler spend ledger, as its own kind (§10.3). It has its own monthly cap, default $10, in config. When the cap is hit, flagging pauses and Alex gets one notice (my call; same shape as the 4b listener's $25 cap on that ledger).

### 5.5 Sending (the narrow exception)
- **Who can trigger it:** only Alex's own messages in his HomeChat WhatsApp 1:1 (`yes`, `edit:`). Never the Home group, never his wife, never a Duet proposal on its own, never a run started by untrusted content.
- **What it sends:** one approval sends one message. Text only, to an existing thread the reader has seen, with the participant set unchanged since the item was created.
- **Expiry:** an approval lapses if the Mac hasn't picked it up within 10 minutes. Alex then gets "not sent, Mac offline" (my call).
- **Ambiguous sends:** never resent. Alex gets "may or may not have sent: check Messages".
- **Cap:** at most 30 sends a day (my call; a safety ceiling, not a target).
- **Audit:** every send row logs the thread, exact text, approval message ID, outcome and anchor.
- **Content rules:** HomeChat's output rules still apply to suggested replies: no links, phone numbers, account numbers, codes, passwords or medical details. Alex's own `edit:` text is sent as typed (my call).

## 6. Security and privacy

- **What goes where:**
  - Other people's texts go to Claude (Anthropic) under Alex's claude.ai login. Alex accepted this, with SSNs removed on the Mac.
  - None of it goes to Muse/Meta in v1.
- **Untrusted content:** the flagger is read-only, has no send or desk tools, and its output is schema-checked data. Desk and WhatsApp text from it is scrubbed again on OVH: SSN pattern, links, codes.
- **Labels:** everything from this project is `alex-only`.
- **Rule change for HomeChat's `CLAUDE.md`, needing Alex's explicit approval when the HomeChat amendment is written:**
  - "The bot may send an iMessage reply as Alex only to an existing thread, only text, only after Alex's own `yes` or `edit:` in his 1:1, one approval per send, through the Mac send queue with expiry and audit."
  - Everything else in "never replies to anyone" stays.
- **Public repo hygiene:**
  - No names, numbers, chat GUIDs, HomeChat host or tokens in the fork.
  - Config lives in a local file outside the repo, plus the Keychain.
  - Test fixtures use synthetic `chat.db` data only. msgblast's tests already build synthetic databases.
- **The Mac's permissions** (Full Disk Access, Automation) belong to the fork's app only. The uplink token can only post messages and fetch approved sends for its own device.

## 7. Phases and acceptance (my call on order)

0. **Spikes on the MacBook** (throwaway). Each answers one unknown:
   - (a) how many recent bodies are `attributedBody`-only, and whether a decoder recovers them;
   - (b) reading group threads from `chat.db`;
   - (c) AppleScript send to a group chat with an identity check;
   - (d) whether a send raises Messages or steals focus;
   - (e) whether the Mac can reach a HomeChat route through Cloudflare (the edge currently admits only Anthropic for some paths);
   - (f) iPhone replies syncing to the Mac (§10.1);
   - (g) whether permission grants survive a rebuild (§10.4).
1. **Read and flag.** Reader, scrubber, uplink, store, flagger, desk items, auto-clear and the WhatsApp update. No sending.
   - Accept when a real unanswered text shows up on the desk and in the update, and a real reply clears it, seen on Alex's phone and re-read on the desk.
2. **Calendar.** Free/clash in the update, `add` on `yes`.
   - Accept when a texted date lands on the calendar after `yes`, and the event is re-read.
3. **Approved replies.** Send queue, executor, expiry, audit.
   - Accept when a `yes` sends a reply that the recipient (a test contact) receives once, and the flag clears.
   - Also accept: an offline Mac produces "not sent", and an ambiguous send is not resent.
4. **Duet tools.** Read waiting texts; propose a reply that is approved in WhatsApp.
5. **Later, not v1:** Muse read-only (after its connection test); the upstream generic-API PR to msgblast.

## 8. Left to the builder

- Swift structure inside the fork, the `attributedBody` decoder approach, and how group participants are fingerprinted.
- Exact route names, payload fields and long-poll timing, within §4.2's shape.
- How the Mac reaches HomeChat through Cloudflare and Caddy: a new hostname or path rule, or a Cloudflare Access service token. Edge changes need Alex's approval under HomeChat's rules.
- The flagger's model, prompt and batch size. An eval with synthetic threads (1:1, group, check-ins, dates, already-answered) is part of phase 1, like HomeChat's chat-brain eval.
- The desk routine and desk client changes for `source: "text"`. The routine change needs approval.
- The WhatsApp update's exact wording and length within the 4096-char limit.
- Retention clean-up jobs, and the `skip_flagging` heuristics.

## 10. Reviewer questions settled (my calls unless marked)

A fresh builder read this design and raised 9 questions. These are settled as my calls; Alex can override any of them.

1. **iPhone replies:** auto-clear depends on Alex's iPhone replies syncing to the Mac's `chat.db` through Messages in iCloud.
   - **Alex: yes, his iPhone replies show up on the MacBook** (2026-11-07).
   - Add **spike (f)** anyway, to measure the delay in phase 0: send from the iPhone with the Mac awake, then with it asleep, and measure when the row appears on the Mac.
   - Fallback: `N done` always works. A flag older than 24 h with no reply seen says "replied on your phone? reply `N done`".
2. **Where the HomeChat half runs:**
   - The `/imsg` routes, store, flagger, send queue and audit live in the **bot** container, next to the DB, the guarded sender and the desk client.
   - Phase 4's Duet tools live in the **gateway** and call the bot the same way existing connector tools do.
   - The Mac reaches the bot through Caddy on a path or host the builder proposes. Edge changes need Alex's approval.
3. **Runs and credentials:**
   - **Flagger:** classify, extract dates, draft replies. It has no tools and no connector, and is trust `untrusted`. It runs on HomeChat's form-filler API path, with spend in dollars on that ledger under its own kind and its own cap (§5.4), so it doesn't eat Alex's claude.ai usage.
   - **Calendar check:** a separate `claude -p` run with Calendar *read* only and no message text. Plain code first validates the flagger's extracted date and time (no free text), so the run sees only dates. This satisfies the untrusted-run rule: message text never reaches a tool-holding run.
   - **Calendar add:** stays on HomeChat's existing path after `yes`.
4. **Signing:** macOS ties Full Disk Access and Automation grants to the app's code signature. An ad-hoc build can lose them on every rebuild.
   - Phase 0 adds **spike (g)**: build, grant, rebuild, and check the grants survive.
   - **Alex: no paid Apple Developer account, and he would rather not pay $99/yr** (2026-11-07).
   - So sign with a stable, local, self-signed code-signing certificate made in Keychain Access, and keep the same certificate for every build.
   - If spike (g) shows grants still reset, the free Apple ID "Personal Team" development signing in Xcode is the next try. Paying is the last resort, and Alex decides.
   - Install the fork in `/Applications` under its own bundle ID, so it never replaces an installed upstream msgblast.
5. **Phase 1 without the desk:** desk writes are the last task of phase 1.
   - If the desk-routine approval or the 4b queue slips, phase 1 may be accepted as **1a** (WhatsApp update only).
   - **1b** adds desk items.
6. **Alex's own Home Desk routines** (morning brief, midday, evening): text items will appear in them, because they read the whole desk. That is intended: it's his desk. Those routines are not changed.
   - Desk items carry only a short scrubbed paraphrase, never message text, so they hold nothing more sensitive than email-derived items.
7. **Reply grammar:**
   - A deterministic pre-router runs ahead of the chat brain.
   - Each update stores its N → item-ID map. A number is valid only until the next update, and acting on a stale number replies "that list changed; here's the current one".
   - **Sends accept only the literal forms** `N yes` and `N edit: <text>`. Natural phrasing ("yes to the Sam one") goes to the chat brain, which can only *propose*: it echoes the exact text and recipient, then needs a literal `yes`.
   - Non-send actions (`add`, `snooze`, `done`, `show`) may be phrased naturally.
8. **Groups:**
   - "Addressed to Alex" uses names and nicknames from local config on OVH, never in git.
   - A group whose membership changed after approval cancels the send and re-shows the item.
   - **Groups are flag-only until spike (c) passes.** Group sends then join phase 3, with acceptance in a test group.
9. **Retention on OVH:**
   - the message window: 14 days;
   - flag context: deleted 14 days after the flag closes;
   - pending sends: deleted 7 days after they expire or finish;
   - the send audit keeps exact text for 90 days, then only metadata.
   - A daily clean-up job does this.

## 9. Where things go

- **New repo:** the public fork, created under Alex's GitHub at project setup (on the MacBook), seeded per Alex's project conventions (CLAUDE.md, agents, STATUS/LOG). This design moves there.
- **`homechat-bot`:**
  - a design amendment for the HomeChat half (§4.2, §4.3, §5, §6);
  - the `CLAUDE.md` rule change;
  - a plan, each through its own PR under the repo's rules.
- **Approval for the HomeChat half (Alex, 2026-11-07 17:10 ET):** "Approved to make whatever updates are needed after 4b for home-chat." Once phase 4b is live, the agent may write and merge the HomeChat design amendment, the `CLAUDE.md` iMessage-reply exception (§6), the plan and the code without asking again. The same approval covers the desk client and HomeChat desk-routine changes for `source: "text"`, the Caddy/Cloudflare route for the Mac uplink, and their deploys. Limits that still hold: Alex's own Home Desk routines stay unchanged, the runtime rules stay as designed (no send without Alex's exact-text `yes`/`edit:`), and the other services on OVH stay untouched.
- **Timing:** Alex sets up the new project on the evening of 2026-11-07 (Alex). Phase 0 spikes and the Mac-side work can start then. HomeChat-side changes queue behind the in-flight phase 4b build in `homechat-bot`, so the two don't touch the same files at once (my call).

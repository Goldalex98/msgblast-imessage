# Phase 2 acceptance: calendar free/clash and `N add`

2026-11-14 · HomeChat spec `docs/superpowers/specs/2026-11-14-imsg-phase2-calendar-amendment.md` and plan
`docs/superpowers/plans/2026-11-14-imsg-phase2-calendar-plan.md` (both in `homechat-bot`)

Phase 2 is HomeChat-only. The Mac app does not change, so there is no build or install step. These checks need HomeChat's phase 2 code deployed with `HOMECHAT_IMSG_CALENDAR=on`, which happens only after Alex's yes.

**These checks write real calendar events.** Each `N add` runs only when Alex types it himself, on a text from a test contact he chooses. Nothing here sends an iMessage. The test contact's name, number and message text stay out of this repo, commits, PRs and any chat with Claude. Report results as pass or fail, with the reply line's shape (for example "Added to <calendar>: <title>, <when>"), never the title itself.

## Before you start

- **Deployed:** HomeChat runs the merged phase 2 commit, and its status shows the calendar switch on.
- **Off first:** before the switch is turned on, `1 add` on any item answers "Calendar isn't switched on for texts yet." and writes nothing.
- **Baseline:** note how many events the default calendar holds on the test date, so check D can count new ones.

## Checks

**A. Free.**
- The test contact texts a question with a date and time, and nothing is on any read calendar at that time (for example "dinner Saturday at 7?").
- Pass:
  - the next update shows the item with ` · free · "N add"`;
  - Alex sees it on his phone.

**B. Clash.**
- Use a second dated text whose time overlaps an existing event.
- Pass: the item shows that event's title and time instead of "free", and offers `N add`.

**C. Date only.**
- Use a text with a date and no time.
- Pass: the item lists that day's events (up to 3, then "+N more"), or "free". `N add` makes an all-day event.

**D. Add.**
- Alex types `N add` on the item from check A.
- Pass:
  - the reply reads "Added to <default calendar>: <title>, <when>", and the date and time match what the update showed;
  - the event appears once in Calendar on Alex's phone;
  - the default calendar has exactly one more event on that date than the baseline;
  - the flag stays open (adding does not clear it).

**E. Second add.**
- Alex types the same `N add` again.
- Pass: the reply reads "Already on your calendar: <title>, <when>." and no second event appears.

**F. Changed item.**
- The test contact sends a follow-up that changes the time, before the next update.
- Alex types `N add` against the old list.
- Pass: the reply is "That item changed; here's the current one." with the new line, and nothing is added.

**G. Shown on the calendar.**
- After check D, the next update shows that item as "on your calendar", not "free" or a clash with itself, and offers no `N add`.

## Afterwards

- Alex deletes the test events in Calendar himself.
- Record each check's pass or fail in `.claude/STATUS.md` EVIDENCE, with the HomeChat commit and the date. Name anything not exercised (for example "cap of 10 not exercised live; covered by tests").

# Phase 2 acceptance: calendar free/clash and `N add`

2026-11-14 · HomeChat spec `docs/superpowers/specs/2026-11-14-imsg-phase2-calendar-amendment.md` and plan
`docs/superpowers/plans/2026-11-14-imsg-phase2-calendar-plan.md` (both in `homechat-bot`)

Phase 2 is HomeChat-only; the Mac app doesn't change. HomeChat runs it with `HOMECHAT_IMSG_CALENDAR=on` (live since 2026-11-14 14:05 ET).

**The test contact sends one text. Everything after that is Alex on his own phone.** `N add` writes a real calendar event and never sends an iMessage. The contact's name, number and message text stay out of this repo, commits, PRs and any chat with Claude.

Clashes, date-only texts, a changed item, a stale `N add` and the daily cap are covered by HomeChat's tests, not here.

## The check

1. **One text.** The test contact texts Alex a question with a day and a time (for example "dinner Saturday at 7?").
2. **The update.** In the next iMessage update on WhatsApp, the item ends with ` · free` (or the event it clashes with) and ` · "N add"`.
3. **Add it.** Alex replies `N add`.
   - The reply reads "Added to <calendar>: <title>, <when>", with the day and time from the update.
   - The event is in Calendar on his phone, once.
4. **Add it again.** Alex replies the same `N add`.
   - The reply reads "Already on your calendar: …".
   - Calendar still shows one event.

Pass is all four. Then Alex deletes the test event in Calendar.

Record pass or fail in `.claude/STATUS.md` EVIDENCE, with the HomeChat commit and the date, never the title or text.

# Calendar and Reminders — Today milestone

## Implementation

`TodayModels` defines value-only CalendarSnapshot, ReminderSnapshot, TodayEvent, TodayReminder and TodaySource models. `CalendarService` and `ReminderService` own their state and generation checks. A single `EventKitTodayStore` implements both provider protocols; the old EventKit store and string-fetch implementation in WidgetServices were removed. WidgetServices derives its compatibility title/count summaries from these shared snapshots. Weather, timer and lock-screen ownership remain in their existing modules.

Settings → Today independently enables Calendar and Reminders. Enable does not prompt. Only Connect Calendar / Connect Reminders invokes EventKit authorization. Refresh only checks current access and fetches data that is already authorized. Not-connected, denied, restricted, loading, unavailable, disabled and empty states are distinct. Write-only Calendar permission is insufficient for this read UI.

New installations default both services off. Existing lockCalendar/lockReminders opt-ins migrate to the corresponding service being enabled, preserving existing widget usage without changing privacy preferences. Persisted source selection distinguishes All from an explicit set. None is an empty set, including when EventKit has no matching sources; no empty list is passed to EventKit as a query for all calendars. Missing source identifiers remain selected until the user changes them, so temporary account removal does not silently select unrelated lists.

Today displays ongoing and upcoming events through the end of the current local day. Calendar-day arithmetic handles 23/25-hour days. It includes all-day state, calendar color, title, local start/end time, location and an HTTP(S) event/location/notes meeting link where available. Multi-day timed events include the end date. Reminders include all incomplete items from selected lists, sorted by due date, with a separate No due date section. Date-only reminders become overdue at the following midnight in their due-date calendar/time zone; timed reminders become overdue at their due instant. Undated reminders are never overdue.

Reminder completion is only invoked by its completion button. The row remains incomplete while saving; read-only lists and in-flight controls are disabled. A save error retains the original row and shows an error, and EventKit's in-memory completion properties are restored when saving throws. EventKit updates during a write are refreshed after the write settles. No automatic refresh, view rendering, opening the island or sample preview completes real reminders.

## Lifecycle and presentation

TodayServices listens for EventKit changes, local day rollover, clock/time-zone changes, app activation, session activation and wake. A one-shot task targets the next event end, reminder overdue boundary or midnight. Notification bursts are debounced; there is no Calendar/Reminders polling loop. New refreshes/configurations invalidate earlier generations before asynchronous callbacks can publish. Revoked permission clears old personal content. Stop cancels work and removes observers; restart refreshes again.

The existing island owns the silhouette, camera clearance, glass/material fallback and appearance preferences. A small Music/Today switch sits beneath the camera header. Today has its own selected page in IslandState and stays visible with Media disabled or hidden after pause. Pause-driven collapse only affects the Music page. PopupCoordinator retains priority, deduplication, interaction deferral and dismissal. Popups overlay the page without changing it; explicit reminder saves participate in the interaction-busy state.

LockWidgetStrip retains the existing privacy gates: personal event title and reminder count are included only for their corresponding opt-in. Enabling Today alone does not enable lock-screen exposure. The strip stays click-through and has no completion controls.

## Manual acceptance still required

- Signed app: grant, deny, revoke and restore Calendar and Reminders separately through macOS. Verify source/list changes and external EventKit edits, including deleted and read-only lists.
- Test real events across midnight, DST and time-zone changes, wake and account changes; inspect all-day, multi-day and meeting-link cases.
- Complete a disposable reminder with a direct button press; exercise a real save rejection/read-only account. Automated injected failure tests do not prove provider-specific failures.
- Actual notch: keyboard/VoiceOver, scrolling, smallest sizing, glass/material/gradient and increased contrast, Music/Today switching while paused, popup interruption and restore.
- Genuine locked Mac: verify each privacy switch independently, real panel rendering, authentication routing, unlock and sleep/wake. Offscreen and unlocked previews do not verify lock-screen behavior.

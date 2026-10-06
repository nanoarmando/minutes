## Context

`CalendarService.planNextSuggestion` sleeps until the next qualifying `startDate`, then `suggestEvents(startedSince:)`
posts for events whose start is in `[since, now]`, deduplicated per occurrence. Wake calls it with
`now - 5 min`. Nothing runs at launch or on calendar changes for events that already started.

## Goals / Non-Goals

**Goals:** suggest one minute before the start; late discovery still suggests once.

**Non-Goals:** a configurable lead time, changes to call detection, changing the Settings label.

## Decisions

- One constant `leadTime = 60 s`. A pending suggestion is any qualifying event with
  `start - leadTime <= now` and `start > now - wakeGrace` (5 min), not yet in `notified`.
- `planNextSuggestion` first posts pending suggestions (covers launch, preference changes, `EKEventStoreChanged`
  and wake, which all call `reload()`), then sleeps until the earliest `start - leadTime` among later events.
  This replaces the special wake call: wake only needs `reload()`.
- The occurrence key and the "not while recording" rule stay as today. Skipped-while-recording events are not
  marked notified, matching current behavior.
- Title becomes "<event> starts in 1 minute" in `MeetingNotifications.postEventStarting`; for a late discovery after
  the start the same title is used (kept simple; the body still asks to record).

## Risks / Trade-offs

- [Launching Minutes in the five minutes after an event started now suggests it] → intended; it was only done after
  wake before.
- [Late-discovered events show "starts in 1 minute" even if they already started] → accepted to keep one message.

## Context

`CalendarService.qualifies(_:)` is the only filter on both suggestion paths (planning the next timer and posting events already due). Today it returns `meetingLink(of:) != nil || !attendees(of:).isEmpty` and never reads `EKEvent.status` or the user's participation status. `events(from:to:)` is shared with `event(at:)`, which fills the note's front matter when a recording starts.

## Goals / Non-Goals

**Goals:** suggest recording only for events that are not cancelled, accepted by the user and with a meeting link.

**Non-Goals:** changing which event fills the note at recording start; changing how a meeting link is detected; withdrawing notifications already shown.

## Decisions

- **D1. Filter only in `qualifies`.** `qualifies` becomes `event.status != .canceled && isAccepted(event) && meetingLink(of: event) != nil`. Leaving `events(from:to:)` untouched keeps note data for in-person meetings. Alternative rejected: filtering at fetch, which would also drop event data from notes.
- **D2. Acceptance check.** `isAccepted` looks for the attendee with `isCurrentUser`; with none (own event without guests, or the organizer not listed) the event counts as accepted, otherwise it requires `participantStatus == .accepted`.
- **D3. Remove `attendees(of:)` if unused.** The attendee fallback was its only caller in the qualification path; keep it only if another caller remains.
- **D4. Late cancellation.** No new code: `.EKEventStoreChanged` already triggers `reload()`, which re-plans with the new filter.

## Risks / Trade-offs

- Some calendar providers may represent a cancelled meeting only with a "Canceled:" title prefix rather than `status == .canceled`; such events still have no accepted status in most cases, but this is not guaranteed. Mitigation: verify on the user's real calendars.
- An organizer listed as an attendee is normally `.accepted`; if a provider reports it otherwise, the user's own meeting would not notify.
- `event.url` still counts as a meeting link whatever its host (unchanged behavior).

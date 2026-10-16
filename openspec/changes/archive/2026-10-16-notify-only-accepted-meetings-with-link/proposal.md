## Why

Minutes suggests recording one minute before any followed-calendar event that has a meeting link or at least one attendee. It never checks whether the event was cancelled or whether the user accepted it, so the user gets notifications for cancelled meetings, for invitations they did not accept, and for meetings with attendees but no call link.

## What Changes

- The recording suggestion is shown only for events that are not cancelled, that the user accepted (or that have no invitation for the user, such as the user's own events), and that have a meeting link.
- Events with attendees but no meeting link no longer trigger a suggestion.
- Event data used in the note when a recording starts is unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `calendar`: the "Suggest recording when a meeting starts" requirement narrows which events qualify.

## Impact

- `Sources/Minutes/Calendar/CalendarService.swift` (`qualifies` and its helpers).
- `README.md` and `AGENTS.md` calendar sections.
- No data, settings or permission changes.

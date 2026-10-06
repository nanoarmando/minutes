## Why

The calendar suggestion arrives exactly at the start time, so the user is often already joining the call when it
appears. A heads-up one minute earlier lets them start recording before the meeting begins.

## What Changes

- The suggestion is shown one minute before a qualifying event starts, titled "<event> starts in 1 minute", with the
  same "Start recording" and "Dismiss" actions.
- If that moment has already passed when Minutes learns about the event (event created or moved late, Minutes
  launched, or the Mac woke up), the suggestion is shown right away as long as the event started less than five
  minutes earlier.
- Call detection is unchanged.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `calendar`: the suggestion timing and its title.

## Impact

- Code: `CalendarService` timer and window, the notification title in `MeetingNotifications`.
- No new setting, permission or dependency. Settings text "Suggest recording when a meeting starts" stays.

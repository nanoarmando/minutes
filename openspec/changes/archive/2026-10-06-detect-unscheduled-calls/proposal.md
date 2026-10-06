## Why

Minutes suggests recording only when a calendar event starts. Calls that are not on the calendar (a quick Zoom, a
Slack huddle, a Meet link someone sends) are easy to forget to record. Granola handles this by noticing that a
meeting app is using the microphone.

## What Changes

- Detect a call when a meeting app (Zoom, Teams, Slack, Webex, FaceTime, Discord, or a browser) uses the microphone
  for 10 seconds, and suggest recording with a notification ("Are you in a meeting?").
- While recording, when the call app releases the microphone for 10 seconds, ask "Did the meeting end?" with
  Stop & summarize.
- A switch in Settings › General, on by default.

## Capabilities

### New Capabilities
- `call-detection`: microphone-based call detection and the start and end suggestions.

### Modified Capabilities
- `app-shell`: Settings › General lists the new switch.

## Impact

- Code: a small Core Audio monitor, notifications (two new categories), Settings › General, preferences.
- No new permission, network request or dependency. Minutes never starts or stops a recording by itself.
- Calendar suggestions are unchanged; a scheduled call can trigger both suggestions (no deduplication, by user
  decision).

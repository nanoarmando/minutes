## Why

With back-to-back meetings the next meeting is never suggested: the calendar suggestion is skipped while a
recording is in progress, and even after stopping, a new recording cannot start until the previous meeting has
finished processing (transcript, speakers, summary), which takes minutes. The user loses the start of the next
meeting or forgets to record it.

## What Changes

- The calendar suggestion is also shown while a recording is in progress, one minute before the next qualifying
  event, with "Stop & record next" and "Dismiss". "Stop & record next" stops and saves the current meeting and
  immediately starts recording the next one with that event's data.
- A stopped meeting is processed in the background. A new recording can start while one or more earlier meetings
  are still processing. There is still at most one recording at a time.
- The menu shows one row per meeting being processed (its name and current step), with Retry and Discard when
  processing failed, below the recording or idle controls.
- Quit while a meeting is still processing (and nothing is recording) asks "Wait" or "Quit anyway"; the meeting is
  finished at the next launch, as today after a crash.
- Call detection suggests recording while earlier meetings are only processing; it stays silent only while
  recording.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `calendar`: the meeting-start suggestion is shown during a recording, with "Stop & record next".
- `meeting-recording`: a recording can start while earlier meetings process; background processing; Quit while
  processing.
- `app-shell`: menu rows for meetings being processed.
- `call-detection`: the start suggestion is suppressed only while recording.

## Impact

- Code: `AppEnvironment` (one current recording plus a set of processing meetings, per-session event routing,
  recovery skips every live session), `RecordingSession` (stop capture separately from processing),
  `MeetingNotifications` and the notification handler (new category and action), `CalendarService` (no recording
  guard), `MenuView`, the Quit handler, `CallDetector` re-arm per recording.
- No new setting, permission, dependency or data format. Notes, sidecars and `InProgress/<id>/` are unchanged.
- README and AGENTS.md (calendar suggestions, call detection, threading/state notes).

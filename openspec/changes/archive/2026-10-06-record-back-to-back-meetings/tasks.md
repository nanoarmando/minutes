## 1. Session lifecycle

- [x] 1.1 `RecordingSession`: expose `stopCapture()` (returns once capture is down) and `process()` (worker + finish); `stop()` runs both
- [x] 1.2 `AppEnvironment`: `status` for the current recording only, `stopped` entries with name and phase, per-session event routing in `consume`
- [x] 1.3 `stopRecording` moves the session to `stopped` after `stopCapture()` and processes in the background; `startRecording` guards on `isRecording` and clears saved entries
- [x] 1.4 `retryProcessing(id:)` and `discardStopped(id:)`; `isActive` checks every live session id; `isBusy` covers processing entries

## 2. Notifications and suggestions

- [x] 2.1 `MeetingNotifications`: category `event-starting-recording` with "Stop & record next" and "Dismiss"; `postEventStarting` picks the category from the recording state
- [x] 2.2 `CalendarService`: remove the recording guard
- [x] 2.3 Notification handler and `AppEnvironment.stopAndRecordNext(event:)` (start only when idle, no-op for the same occurrence)
- [x] 2.4 Call detection: suggest when not recording; re-arm `CallDetector` on every new recording

## 3. Menu and Quit

- [x] 3.1 `MenuView`: one row per stopped meeting (processing step, saved with Open, waiting for folder, failed with Retry/Discard)
- [x] 3.2 Quit while only processing: "Wait" / "Quit anyway"

## 4. Docs and checks

- [x] 4.1 README and AGENTS.md (suggestions during recording, background processing, state notes)
- [x] 4.2 `swift build -c release --arch arm64` with zero warnings

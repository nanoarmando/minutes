## Context

See proposal.md - Why. `AppEnvironment` holds one `session` and one `status`; `consume(events)` applies every
session event to that single state, so a stopped meeting's late events (levels, `.processing`, `.finished`) would
overwrite a new recording's state. `startRecording` refuses while `isBusy` (recording or processing).
`RecordingSession.stop()` tears capture down and then runs the whole finish (transcript, diarization, summary, save)
before returning. `finishInterruptedMeetings` skips only the current session's folder. Each `RecordingSession` is
otherwise independent: its own id, `InProgress/<id>/` folder, capture objects and event stream; ASR goes through the
shared `ParakeetEngine` actor and diarization creates its own manager per call, so a processing session and a
recording session can run together.

## Goals / Non-Goals

**Goals:** one current recording plus any number of processing meetings; event routing per session; the calendar
suggestion during a recording with "Stop & record next".

**Non-Goals:** two simultaneous recordings, a processing indicator in the menu bar label, changing the note,
sidecar or `InProgress` formats, limiting CPU use of background processing.

## Decisions

- **State shape.** `AppEnvironment` keeps `status` for the current recording only (`.idle`, `.recording`,
  `.startFailed`) and adds `stopped: [StoppedMeeting]` in stop order, each with the session, a display name (event
  title or start time) and a phase (`.processing(step)`, `.finished(FinishResult)`). `isRecording` reads `status`;
  `isBusy` (updates, quit) is recording or any stopped meeting still processing. Alternative: an array of generic
  sessions with roles; rejected because the recording has levels and elapsed time that processing meetings never
  need.
- **Routing.** `consume(session.events, id:)` applies `.levels` and `.elapsed` only while that id is the current
  recording; `.state` updates `status` for the current recording and the matching `stopped` entry otherwise.
- **Split stop.** `RecordingSession.stopCapture()` becomes callable from outside and returns once tap, mic and
  writers are down; `process()` then awaits the worker and runs `finish`. `stop()` stays as both in sequence (sleep,
  quit, shortcut). `AppEnvironment.stopRecording()` moves the session into `stopped` and clears `status` after
  `stopCapture()` returns, then processes in a detached task. "Stop & record next" awaits only `stopCapture()` and
  then calls `startRecording(event:)`, so the system tap of A is gone before B's starts.
- **Start guard.** `startRecording` guards `!isRecording` (and a start in progress), not `isBusy`. Starting removes
  `stopped` entries whose phase is `.finished(.saved)` or `.finished(.waitingForFolder)`.
- **Retry and discard by id.** `retryProcessing(id:)` and `discardStopped(id:)` act on one `stopped` entry; the
  current recording keeps `discardRecording()`. This also fixes today's orphaned failed session when a new
  recording starts after a failure.
- **Recovery.** `isActive` checks the current session id and every `stopped` id, so the `updatePreferences` re-run
  cannot pick up a live folder.
- **Notification.** A new category `event-starting-recording` with actions `stop-and-record-next` and `dismiss`;
  `CalendarService` drops its `isRecording` guard and `postEventStarting` picks the category from the recording
  state at post time (categories are static). The handler calls `stopAndRecordNext(event:)`, which only starts when
  nothing is recording, and does nothing when the current recording already uses that event occurrence.
- **Call detection.** `suggest(for:)` uses `!isRecording` instead of `!isBusy`. `AppEnvironment` calls a
  `CallDetector` re-arm on every new recording, because a fast A→B switch may not produce an observable
  `isRecording == false` transition.
- **Quit.** `applicationShouldTerminate`: while recording, today's dialog; else, when any stopped meeting is still
  processing, an alert with "Wait" (`.terminateCancel`) and "Quit anyway" (`.terminateNow`); recovery at launch
  already finishes it with `recovered: true`.
- **Menu.** `MenuView` renders the idle or recording block, then one row per `stopped` entry reusing today's
  `Message` views (saved, waiting for folder, failed) plus a compact processing row.

## Risks / Trade-offs

- [ASR and diarization of A compete with B's live transcription] → B's chunks wait on disk and are transcribed
  later; B's stop can take longer. Accepted.
- [Stop & Save on Quit while A also processes] → Quit waits for B only; A is recovered at launch. Accepted, same as a
  crash today.
- [A notification posted during a recording keeps "Stop & record next" after the user stops] → the action starts the
  recording when nothing is recording.

## Migration Plan

No data migration. Rollback is reverting the change; `InProgress` folders remain compatible.

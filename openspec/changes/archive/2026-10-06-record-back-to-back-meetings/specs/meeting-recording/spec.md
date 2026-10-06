## MODIFIED Requirements

### Requirement: Start a recording
Minutes SHALL start a recording when the user chooses "Start recording" in the menu bar or presses the global
recording shortcut (default ⌘⇧R). Only one recording SHALL exist at a time. A recording SHALL be able to start
while earlier meetings are still being processed.

#### Scenario: Start from the menu bar
- **WHEN** no recording is in progress and the user clicks "Start recording"
- **THEN** capture starts within 2 seconds, the menu bar item shows a red dot with the elapsed time, and the menu shows the recording controls

#### Scenario: Shortcut while recording
- **WHEN** a recording is in progress and the user presses the recording shortcut
- **THEN** Minutes stops the recording exactly as "Stop & summarize" does and does not start a second one

#### Scenario: Start while the previous meeting is processing
- **WHEN** the user stopped a meeting that is still being summarized and clicks "Start recording"
- **THEN** the new recording starts within 2 seconds and the previous meeting keeps processing and is saved

### Requirement: Stop and process a recording
When the user chooses "Stop & summarize", Minutes SHALL stop capture, finish the transcript, separate speakers,
generate the title and the summary, save the note and confirm it in the menu and with a system notification
that opens the meeting when clicked. Processing SHALL run in the background, independently of any later recording,
and a failure SHALL affect only that meeting. When the user chooses Quit while no recording is in progress but a
meeting is still being processed, Minutes SHALL ask "Wait" or "Quit anyway"; "Wait" keeps Minutes open, and "Quit
anyway" quits and the meeting is finished at the next launch as a recovered meeting.

#### Scenario: Normal stop
- **WHEN** the user stops a 30-minute recording
- **THEN** the menu shows the processing steps, and the note is saved and announced without further user action

#### Scenario: Processing while recording the next meeting
- **WHEN** a stopped meeting is being processed while a new recording is in progress
- **THEN** the new recording's elapsed time and levels are not affected, and the stopped meeting is saved and announced when it finishes

#### Scenario: Processing fails while recording
- **WHEN** the summary of a stopped meeting fails while a new recording is in progress
- **THEN** the new recording continues and the menu offers Retry and Discard for the failed meeting only

#### Scenario: Mac goes to sleep
- **WHEN** the Mac goes to sleep during a recording
- **THEN** Minutes stops the recording and processes it as a normal stop

#### Scenario: Quit while recording
- **WHEN** the user chooses Quit while a recording is in progress
- **THEN** Minutes asks whether to stop and save, discard, or cancel, and only quits after the chosen action completes

#### Scenario: Quit while processing
- **WHEN** the user chooses Quit while a stopped meeting is still being processed and nothing is recording
- **THEN** Minutes asks "Wait" or "Quit anyway"; "Wait" keeps it open, and after "Quit anyway" the meeting is saved as recovered at the next launch

### Requirement: Recover an interrupted recording
Minutes SHALL keep the transcript produced during a recording safe on disk as it progresses. If Minutes quits
unexpectedly during a recording or while processing, it SHALL, on the next launch, save a note from the
transcript recovered so far and mark the note as recovered. Recovery SHALL never process a meeting that is still
being recorded or processed by the running app.

#### Scenario: Crash during a meeting
- **WHEN** Minutes crashes 20 minutes into a recording and is opened again
- **THEN** a note containing the first 20 minutes of transcript is saved, marked as recovered, and summarized if summaries are enabled

#### Scenario: Recovery retried while meetings are live
- **WHEN** the user chooses a writable notes folder while one meeting is processing and another is recording
- **THEN** neither meeting is recovered or saved twice

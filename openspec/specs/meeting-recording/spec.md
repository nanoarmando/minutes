# meeting-recording Specification

## Purpose
Defines how the user starts, stops and discards a meeting recording, what audio Minutes captures, which
permissions it needs, and how an interrupted recording is recovered.
## Requirements
### Requirement: Start a recording
Minutes SHALL start a recording when the user chooses "Start recording" in the menu bar or presses the global
recording shortcut (default ⌘⇧R). Only one recording SHALL exist at a time.

#### Scenario: Start from the menu bar
- **WHEN** no recording is in progress and the user clicks "Start recording"
- **THEN** capture starts within 2 seconds, the menu bar item shows a red dot with the elapsed time, and the menu shows the recording controls

#### Scenario: Shortcut while recording
- **WHEN** a recording is in progress and the user presses the recording shortcut
- **THEN** Minutes stops the recording exactly as "Stop & summarize" does and does not start a second one

### Requirement: Capture microphone and system audio
While recording, Minutes SHALL capture the default microphone as the user's voice and the audio played by every
other app (Zoom, Meet, Teams, browsers…) as the other participants, without joining the call as a bot. Minutes'
own sounds SHALL NOT be captured. The menu SHALL show a live level for each source.

#### Scenario: Call in a browser tab
- **WHEN** the user records a Google Meet call running in a browser
- **THEN** the remote participants are captured from system audio and the user's voice from the microphone

#### Scenario: Headphones connected mid-meeting
- **WHEN** the user connects AirPods or another headset while recording
- **THEN** the recording continues without user action, using the new default devices

### Requirement: Stop and process a recording
When the user chooses "Stop & summarize", Minutes SHALL stop capture, finish the transcript, separate speakers,
generate the title and the summary, save the note and confirm it in the menu and with a system notification
that opens the meeting when clicked.

#### Scenario: Normal stop
- **WHEN** the user stops a 30-minute recording
- **THEN** the menu shows the processing steps, and the note is saved and announced without further user action

#### Scenario: Mac goes to sleep
- **WHEN** the Mac goes to sleep during a recording
- **THEN** Minutes stops the recording and processes it as a normal stop

#### Scenario: Quit while recording
- **WHEN** the user chooses Quit while a recording is in progress
- **THEN** Minutes asks whether to stop and save, discard, or cancel, and only quits after the chosen action completes

### Requirement: Discard a recording
The user SHALL be able to discard the current recording. Discarding SHALL ask for confirmation and then delete
all audio and partial transcript without creating a note.

#### Scenario: Discard confirmed
- **WHEN** the user discards a recording and confirms
- **THEN** no note is created, no audio remains on disk, and the menu returns to its idle state

### Requirement: Permissions
Minutes SHALL request the microphone and system audio permissions the first time a recording starts. If a
permission is missing, the recording SHALL NOT start and Minutes SHALL explain which permission is missing with a
button that opens the matching pane of System Settings. Settings SHALL show the current state of each permission.

#### Scenario: System audio denied
- **WHEN** the user starts a recording without the system audio permission
- **THEN** no recording starts and a message names the system audio permission and offers to open System Settings

#### Scenario: Silent system audio
- **WHEN** a finished recording contains no system audio signal at all
- **THEN** the note is still saved and Minutes warns that only the microphone was recorded

### Requirement: Recover an interrupted recording
Minutes SHALL keep the transcript produced during a recording safe on disk as it progresses. If Minutes quits
unexpectedly during a recording or while processing, it SHALL, on the next launch, save a note from the
transcript recovered so far and mark the note as recovered.

#### Scenario: Crash during a meeting
- **WHEN** Minutes crashes 20 minutes into a recording and is opened again
- **THEN** a note containing the first 20 minutes of transcript is saved, marked as recovered, and summarized if summaries are enabled


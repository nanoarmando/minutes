## MODIFIED Requirements

### Requirement: Menu bar app
Minutes SHALL run as a menu bar item. Its menu SHALL show, when idle: the active transcription engine, "Start
recording" with its shortcut, "Update available (<version>)" only when a newer release is known, "All meetings…",
"Open notes folder", "Settings…", "About Minutes" and "Quit"; it SHALL NOT list individual meetings; while recording: elapsed time, source levels, "Stop & summarize" and
"Discard". Below the idle or recording controls it SHALL show one row per stopped meeting since the last recording
started: while processing, its calendar event title (or its start time when it has no event) and the current step
of transcript, speakers or summary; when saved, the saved confirmation with "Open"; when processing failed, the
error with "Retry" and "Discard" for that meeting only. Saved rows SHALL be removed when the next recording starts;
failed rows SHALL stay until retried successfully or discarded.

#### Scenario: Idle menu
- **WHEN** the user clicks the menu bar item with no recording in progress and no meeting stopped since launch
- **THEN** the idle menu appears without any meeting titles, and "All meetings…" opens the Meetings window

#### Scenario: Recording while another meeting processes
- **WHEN** the user opens the menu while recording "Client kickoff" and "Weekly sync" is being summarized
- **THEN** the menu shows the recording controls and a row "Weekly sync — Summarizing"

#### Scenario: Failed meeting
- **WHEN** a stopped meeting failed to process
- **THEN** its row shows the error with "Retry" and "Discard", and those actions affect only that meeting

#### Scenario: Menu closes after an action
- **WHEN** the user chooses any action in the menu
- **THEN** the menu closes and the chosen window, if any, comes to the front

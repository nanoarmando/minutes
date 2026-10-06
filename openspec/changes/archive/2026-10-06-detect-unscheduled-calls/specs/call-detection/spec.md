## Purpose

Defines how Minutes notices a call that was not in the calendar, from a meeting app using the microphone, and
suggests starting and stopping a recording.

## ADDED Requirements

### Requirement: Detect a call from microphone use
Minutes SHALL consider a call detected when a meeting app uses the microphone for 10 continuous seconds. Meeting
apps SHALL be Zoom, Microsoft Teams, Slack, Webex, FaceTime, Discord, and the browsers Chrome, Arc, Safari, Edge,
Brave and Firefox (for calls in a browser tab). Minutes' own microphone use SHALL never count. Detection SHALL run
while the setting "Suggest recording when a call is detected" is on (default on), and SHALL NOT require any
additional permission.

#### Scenario: Unscheduled Zoom call
- **WHEN** Zoom uses the microphone for 10 seconds and nothing is being recorded
- **THEN** a call is detected for Zoom

#### Scenario: Short microphone use
- **WHEN** Slack uses the microphone for 4 seconds to send a voice clip
- **THEN** no call is detected

#### Scenario: Other apps
- **WHEN** a dictation app or Voice Memos uses the microphone
- **THEN** no call is detected

### Requirement: Suggest recording
When a call is detected and nothing is being recorded, Minutes SHALL show a system notification "Are you in a
meeting?" naming the app, with the actions "Start recording" and "Dismiss". "Start recording" SHALL start a
recording as the menu does, including the calendar event lookup. Minutes SHALL notify at most once per continuous
microphone use of that app; a new notification needs the app to release and use the microphone again.

#### Scenario: Start from the suggestion
- **WHEN** the user clicks "Start recording" on "Are you in a meeting? Google Chrome is using the microphone"
- **THEN** recording starts

#### Scenario: Already recording
- **WHEN** a call is detected while a recording is in progress
- **THEN** no notification is shown

#### Scenario: Dismissed
- **WHEN** the user dismisses the suggestion and the call continues
- **THEN** no further suggestion is shown until that app releases the microphone and uses it again

### Requirement: Suggest stopping when the call ends
While recording, when at least one meeting app used the microphone during the recording and then no meeting app has
used it for 10 continuous seconds, Minutes SHALL show a notification "Did the meeting end?" with "Stop & summarize"
and "Keep recording". "Stop & summarize" SHALL stop exactly as the menu does. Minutes SHALL ask at most once per
recording unless a meeting app uses the microphone again. It SHALL never stop a recording by itself.

#### Scenario: Call ends
- **WHEN** the user records a Meet call in Chrome and Chrome releases the microphone for 10 seconds
- **THEN** "Did the meeting end?" appears, and "Stop & summarize" stops and processes the recording

#### Scenario: Keep recording
- **WHEN** the user chooses "Keep recording"
- **THEN** the recording continues and the question is not repeated unless a meeting app uses the microphone again and releases it

### Requirement: Detection setting
Settings › General SHALL have the switch "Suggest recording when a call is detected", on by default; turning it off
SHALL stop both the start and the end suggestions.

#### Scenario: Turned off
- **WHEN** the user turns the switch off and joins a Zoom call
- **THEN** no call suggestion is shown

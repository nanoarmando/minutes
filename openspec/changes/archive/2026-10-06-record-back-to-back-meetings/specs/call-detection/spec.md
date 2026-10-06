## MODIFIED Requirements

### Requirement: Suggest recording
When a call is detected and nothing is being recorded, Minutes SHALL show a system notification "Are you in a
meeting?" naming the app, with the actions "Start recording" and "Dismiss", even while earlier meetings are still
being processed. "Start recording" SHALL start a recording as the menu does, including the calendar event lookup.
Minutes SHALL notify at most once per continuous microphone use of that app; a new notification needs the app to
release and use the microphone again.

#### Scenario: Start from the suggestion
- **WHEN** the user clicks "Start recording" on "Are you in a meeting? Google Chrome is using the microphone"
- **THEN** recording starts

#### Scenario: Already recording
- **WHEN** a call is detected while a recording is in progress
- **THEN** no notification is shown

#### Scenario: Previous meeting still processing
- **WHEN** a call is detected while a stopped meeting is being processed and nothing is recording
- **THEN** the "Are you in a meeting?" notification is shown

#### Scenario: Dismissed
- **WHEN** the user dismisses the suggestion and the call continues
- **THEN** no further suggestion is shown until that app releases the microphone and uses it again

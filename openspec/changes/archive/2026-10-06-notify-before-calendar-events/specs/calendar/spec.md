## MODIFIED Requirements

### Requirement: Suggest recording when a meeting starts
When calendar events are on, access is granted and "Suggest recording when a meeting starts" is on (default),
Minutes SHALL show a system notification one minute before the start time of each event of a followed calendar that
is not all-day and has a meeting link or at least one attendee. The notification SHALL be titled "<event> starts in
1 minute" and offer "Start recording" and "Dismiss". "Start recording" SHALL start a recording whose note uses that
event's data. When the moment one minute before the start has already passed when Minutes plans the suggestion
(the event was created or moved late, Minutes was launched, or the Mac woke up), Minutes SHALL show it immediately
if the event starts later or started less than five minutes earlier. Minutes SHALL notify at most once per event
occurrence and SHALL NOT notify while a recording is in progress.

#### Scenario: Scheduled call starts
- **WHEN** the followed-calendar event "Client kickoff" with a Google Meet link starts at 10:00 and nothing is being recorded
- **THEN** at 09:59 a notification "Client kickoff starts in 1 minute" appears with "Start recording" and "Dismiss"

#### Scenario: Start from the notification
- **WHEN** the user clicks "Start recording" on that notification
- **THEN** recording starts and the note is titled "Client kickoff" with the event's attendees and link

#### Scenario: Already recording
- **WHEN** the minute before a qualifying event arrives while a recording is in progress
- **THEN** no notification is shown

#### Scenario: Event added at the last moment
- **WHEN** a qualifying event starting in 30 seconds is added to a followed calendar
- **THEN** the notification appears right away, once

#### Scenario: Wake during the meeting
- **WHEN** the Mac wakes three minutes after a qualifying event started and it was not suggested yet
- **THEN** the notification appears right away

#### Scenario: Event without link or attendees
- **WHEN** an event with no meeting link and no other attendees is about to start
- **THEN** no notification is shown

#### Scenario: Suggestions turned off
- **WHEN** the user turns off "Suggest recording when a meeting starts"
- **THEN** no event notification is shown, and event titles and data are still used for recordings

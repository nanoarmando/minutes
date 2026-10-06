## Purpose

Defines how Minutes uses the Mac's calendars: the user grants access from Settings, chooses which calendars to
follow, Minutes suggests recording when a scheduled call starts, and the event in progress when a
recording starts provides the meeting's title, attendees, meeting link
and calendar name.

## ADDED Requirements

### Requirement: Calendar access from Settings
Settings SHALL have a Calendar section with a "Use calendar events" switch, off until the user turns it on.
Turning it on SHALL request full calendar access from macOS. Minutes SHALL NOT request calendar access at any
other moment. When access is denied, the section SHALL explain it and offer a button that opens the Calendars pane
of System Settings, and recordings SHALL work without calendar data.

#### Scenario: Grant access
- **WHEN** the user turns on "Use calendar events" and allows access in the macOS prompt
- **THEN** the section lists the Mac's calendars

#### Scenario: Access denied
- **WHEN** the user turns on "Use calendar events" and denies access
- **THEN** the section says calendar access is off and offers to open System Settings, and recordings keep the generated or default title

#### Scenario: First recording
- **WHEN** the user starts the first recording without ever opening the Calendar section
- **THEN** no calendar permission prompt appears

### Requirement: Followed calendars
With access granted, the Calendar section SHALL list every calendar grouped by account, each with a checkbox.
All calendars SHALL be followed by default, including calendars added to the Mac later; the user SHALL be able to
unfollow any of them. Changes SHALL apply immediately.

#### Scenario: Unfollow a personal calendar
- **WHEN** the user unchecks the calendar "Family" and starts a recording during a "Family" event
- **THEN** the event is ignored and the title comes from the summary provider or the default title

#### Scenario: New calendar
- **WHEN** the user adds a new calendar account to the Mac after configuring Minutes
- **THEN** its calendars appear in the list already checked

### Requirement: Event data in the note
When a recording starts during an event of a followed calendar (the event in progress with the most overlap,
ignoring all-day events), the note SHALL use the event title as the meeting title and SHALL store in its front
matter the calendar name, the attendees (display name, or email when there is no name, excluding the user) and the
meeting link (the event URL, or else the first Zoom, Google Meet, Microsoft Teams or Webex link found in the event
location or notes). Keys without a value SHALL be omitted.

#### Scenario: Client call with attendees
- **WHEN** the user records during "Client kickoff" in the followed calendar "Work" with two guests and a Google Meet link
- **THEN** the note is titled "Client kickoff" and its front matter has `calendar: Work`, both guests under `attendees` and the Meet link under `meeting_link`

#### Scenario: No event in progress
- **WHEN** no event of a followed calendar is in progress when the recording starts
- **THEN** the note has no calendar, attendees or meeting link keys

### Requirement: Suggest recording when a meeting starts
When calendar events are on, access is granted and "Suggest recording when a meeting starts" is on (default),
Minutes SHALL show a system notification at the start time of each event of a followed calendar that is not
all-day and has a meeting link or at least one attendee. The notification SHALL name the event and offer
"Start recording" and "Dismiss". "Start recording" SHALL start a recording whose note uses that event's data.
Minutes SHALL notify at most once per event occurrence, SHALL NOT notify while a recording is in progress, and,
after the Mac wakes, SHALL notify for qualifying events that started less than five minutes earlier.

#### Scenario: Scheduled call starts
- **WHEN** the followed-calendar event "Client kickoff" with a Google Meet link reaches its start time and nothing is being recorded
- **THEN** a notification "Client kickoff is starting" appears with "Start recording" and "Dismiss"

#### Scenario: Start from the notification
- **WHEN** the user clicks "Start recording" on that notification
- **THEN** recording starts and the note is titled "Client kickoff" with the event's attendees and link

#### Scenario: Already recording
- **WHEN** a qualifying event starts while a recording is in progress
- **THEN** no notification is shown

#### Scenario: Event without link or attendees
- **WHEN** a followed-calendar event with no meeting link and no attendees starts, such as "Focus time"
- **THEN** no notification is shown

#### Scenario: Suggestions turned off
- **WHEN** the user turns off "Suggest recording when a meeting starts"
- **THEN** no event notification is shown, and event titles and data are still used for recordings

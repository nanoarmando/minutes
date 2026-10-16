## MODIFIED Requirements

### Requirement: Event data in the note
When a recording starts during an event of a followed calendar (the event in progress with the most overlap,
ignoring all-day events), the note SHALL use the event title as the meeting title and SHALL store in its front
matter the calendar name, the attendees (display name, or email when there is no name, excluding the user) and the
meeting link (the first Zoom, Google Meet, Microsoft Teams or Webex link found in the event URL, location or notes,
in that order; links on other hosts or schemes SHALL be ignored). Keys without a value SHALL be omitted.

#### Scenario: Client call with attendees
- **WHEN** the user records during "Client kickoff" in the followed calendar "Work" with two guests and a Google Meet link
- **THEN** the note is titled "Client kickoff" and its front matter has `calendar: Work`, both guests under `attendees` and the Meet link under `meeting_link`

#### Scenario: No event in progress
- **WHEN** no event of a followed calendar is in progress when the recording starts
- **THEN** the note has no calendar, attendees or meeting link keys

#### Scenario: Event URL that is not a call
- **WHEN** the user records during a focus block whose event URL is `blockout://block/123` and whose location and notes have no call link
- **THEN** the note has no meeting link key, and no recording suggestion is shown for that event

#### Scenario: Call link in the notes with another event URL
- **WHEN** an event's URL points to a project page and its notes contain a Zoom link
- **THEN** the Zoom link is the meeting link

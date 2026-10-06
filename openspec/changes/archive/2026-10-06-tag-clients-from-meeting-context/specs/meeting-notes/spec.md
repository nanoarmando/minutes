## MODIFIED Requirements

### Requirement: Machine-readable sidecar
For each note Minutes SHALL write a JSON sidecar, inside a hidden ".minutes" subfolder of the notes folder and
named by the meeting id, holding the transcript segments with start and end times and speakers, the summary
history metadata, the tagging state (pending, and the last error), and, when the recording matched a calendar
event, the attendees' email addresses and the user's own email domain for that event. The Markdown file remains
readable and complete without it.

#### Scenario: Sidecar deleted
- **WHEN** the user deletes a sidecar
- **THEN** the note still appears in the Meetings window and can be summarized again from its Markdown transcript

#### Scenario: Re-tag after the sidecar was deleted
- **WHEN** the user re-tags a meeting whose sidecar was deleted
- **THEN** client detection uses the transcript, the title and the attendees listed in the front matter, with the domains of "Your email addresses" as the user's organization

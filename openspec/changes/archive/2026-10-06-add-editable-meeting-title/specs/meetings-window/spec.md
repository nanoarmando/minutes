## ADDED Requirements

### Requirement: Edit the title
Clicking the title in the meeting detail SHALL turn it into a text field holding the current title. Enter SHALL save
it, Escape or clicking elsewhere without changes SHALL cancel, and a title that is empty after trimming spaces SHALL
NOT be saved (the previous title stays). Editing SHALL be unavailable while the meeting is being summarized,
corrected or re-tagged. After saving, the meeting SHALL stay selected and show the new title in the detail and in
the list.

#### Scenario: Rename a meeting
- **WHEN** the user clicks the title "Meeting 2026-10-06 11:33", types "TVP tracking scope" and presses Enter
- **THEN** the detail and the list show "TVP tracking scope" and the meeting stays selected

#### Scenario: Cancel
- **WHEN** the user edits the title and presses Escape
- **THEN** the title and the note file are unchanged

#### Scenario: Empty title
- **WHEN** the user clears the title and presses Enter
- **THEN** the previous title stays and the note file is unchanged

#### Scenario: New title used as context
- **WHEN** the user renamed a meeting to "DrGreenlife - Followup" and then regenerates its summary
- **THEN** the request uses "DrGreenlife - Followup" as the meeting title

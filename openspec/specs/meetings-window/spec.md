# meetings-window Specification

## Purpose
Defines the Meetings window, where the user browses, reads, searches and re-summarizes the meetings saved in the
notes folder.
## Requirements
### Requirement: Meeting list
The Meetings window SHALL list the meetings in the notes folder, newest first, grouped as Today, Yesterday and
Earlier, each with title, date, time and duration. It SHALL update when notes are added, changed or deleted on
disk, and SHALL ignore Markdown files that were not created by Minutes. Opening the window SHALL take under one
second with 500 notes.

#### Scenario: Note deleted in Finder
- **WHEN** the user deletes a note file in Finder while the window is open
- **THEN** the meeting disappears from the list without restarting Minutes

#### Scenario: Open from a notification
- **WHEN** the user clicks the "saved" notification of a meeting
- **THEN** the Meetings window opens with that meeting selected

### Requirement: Read a meeting
Selecting a meeting SHALL show its title, date, duration and speakers, with a Summary view and a Transcript view.
The window SHALL offer "Open in editor" (the default app for Markdown), "Copy" (the summary as Markdown) and
"Show in Finder".

#### Scenario: Copy summary
- **WHEN** the user clicks Copy on a meeting
- **THEN** the clipboard contains the summary as Markdown

### Requirement: Meeting detail layout
The Meetings window SHALL be a reading layout, not a form: a sidebar with the search field and the meetings grouped
by day, each row showing title and time with duration; and a detail pane with the title as a large heading, a meta
line (date, time, duration, speakers), the tags as removable chips with "+ Add tag" and "Re-tag", the actions
(Open in editor, Copy, Show in Finder) as compact toolbar buttons, a Summary / Transcript switch, the summary types
as chips with a Language menu and Regenerate, and the summary rendered as formatted Markdown. In the Transcript view
each line SHALL show its time, its speaker in a color stable per speaker, and its text.

#### Scenario: Read a summary
- **WHEN** the user selects a summarized meeting
- **THEN** the summary headings, bullets and checkboxes render as formatted text under the meeting header

#### Scenario: Action buttons
- **WHEN** the user clicks Open in editor, Copy or Show in Finder
- **THEN** the action runs and the button returns to its normal state

### Requirement: Change the summary type
The Summary view SHALL show the available summary types with the current one selected, and a Language menu (Auto,
English, Español) showing the meeting's current choice. Choosing another type or "Regenerate" SHALL produce a new
summary with that type, show progress, and save it into the note. Choosing another language SHALL store it, produce
a new summary with the current type in that language, and then re-tag the meeting keeping its manual tags. On
failure the previous summary and tags SHALL stay and the error SHALL be shown.

#### Scenario: Switch to Client call
- **WHEN** the user selects "Client call" on a meeting summarized as General
- **THEN** the summary is regenerated with the Client call structure and the note file is updated

#### Scenario: Regenerate without provider
- **WHEN** no summary provider is configured and the user clicks Regenerate
- **THEN** Minutes explains that a provider is needed and offers to open the Summaries settings

#### Scenario: Fix a summary in the wrong language
- **WHEN** a Spanish meeting was summarized in English and the user chooses Español in the Language menu
- **THEN** the summary is regenerated in Spanish, the topic tags are regenerated in Spanish, and manual tags are kept

#### Scenario: Language change fails
- **WHEN** the user chooses a language and the provider cannot be reached
- **THEN** the previous summary stays, the error is shown, and the chosen language is still stored for the next attempt

### Requirement: Search
The search field SHALL filter meetings as the user types, matching the text against their tags, title, summary and transcript. The list SHALL NOT show tag
chips or other tag filters; tags are searched through this field. Each meeting's detail SHALL show its tags.

#### Scenario: Search a client name
- **WHEN** the user types a client name mentioned only in one transcript
- **THEN** only that meeting remains in the list

#### Scenario: Search by tag
- **WHEN** the user types "budget" and two meetings carry the tag "budget" without saying the word in their text
- **THEN** both meetings remain in the list

#### Scenario: Search by client tag
- **WHEN** the user types "hemisphere" and two meetings are tagged "client/hemisphere-brands"
- **THEN** both meetings remain in the list

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


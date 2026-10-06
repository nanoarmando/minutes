## MODIFIED Requirements

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

## Purpose

Defines where and how Minutes stores meetings: plain Markdown notes in a user-chosen folder, a JSON sidecar per
meeting, and optional audio, with the notes folder as the only source of truth.

## ADDED Requirements

### Requirement: Notes folder
Minutes SHALL store every meeting in a notes folder, by default ~/Documents/Minutes, which the user can change in
Settings. Changing the folder SHALL NOT move existing notes; the Meetings window SHALL show the notes of the
current folder. Finished meetings SHALL NOT be kept in any other store.

#### Scenario: Folder inside an Obsidian vault
- **WHEN** the user selects a folder inside their Obsidian vault
- **THEN** new notes are written there and open in Obsidian as normal Markdown files

#### Scenario: Folder unavailable
- **WHEN** the notes folder is missing or not writable when a meeting finishes
- **THEN** Minutes keeps the meeting, reports the problem, and saves it once the user picks a writable folder

### Requirement: Markdown note format
Each meeting SHALL be one Markdown file named from a pattern with {date}, {time} and {title} (default
"{date} {time} {title}", for example "2026-10-05 0930 Weekly sync.md"); a name collision SHALL append " 2",
" 3"…. The file SHALL contain YAML front matter (id, title, date, duration, speakers, tags, summary type,
transcription engine, summary model, recovered flag, and, when the recording matched a calendar event, the calendar
name, attendees and meeting link), a "Summary" section and a "Transcript" section whose lines have the form
"**[HH:MM:SS] Speaker:** text".

#### Scenario: Open in a text editor
- **WHEN** the user opens a saved note in any Markdown editor
- **THEN** it reads as a title, the summary and the full transcript, with metadata in front matter

### Requirement: Machine-readable sidecar
For each note Minutes SHALL write a JSON sidecar, inside a hidden ".minutes" subfolder of the notes folder and
named by the meeting id, holding the transcript segments with start and end times and speakers, and the summary
history metadata. The Markdown file remains readable and complete without it.

#### Scenario: Sidecar deleted
- **WHEN** the user deletes a sidecar
- **THEN** the note still appears in the Meetings window and can be summarized again from its Markdown transcript

### Requirement: Summary updates keep user edits
Regenerating a summary SHALL replace only the Summary section of the note and the summary metadata, leaving the
rest of the file, including user edits outside that section, unchanged. All writes SHALL be atomic.

#### Scenario: Edited transcript
- **WHEN** the user corrected a name in the transcript and then regenerates the summary
- **THEN** the correction is kept and the new summary uses the corrected transcript

### Requirement: Audio retention
By default Minutes SHALL delete all audio once the note is saved. When "Keep audio recording" is on, Minutes SHALL
save one compressed audio file per meeting next to its sidecar and link it from the front matter.

#### Scenario: Default retention
- **WHEN** a meeting finishes with the default settings
- **THEN** no audio file from that meeting remains on disk

# meeting-corrections Specification

## Purpose
Defines how the user corrects a meeting with plain-language instructions, and the glossary of name corrections that
Minutes remembers and applies to later meetings.
## Requirements
### Requirement: Instructions for a meeting
The meeting detail SHALL offer "Correct with instructions…", where the user writes instructions in their own words
(for example "Doctor Grim is DrGreenlife; Pablo Veliz works at VNS"). Applying them SHALL:
1. ask the summary model for the word replacements the instructions imply, and apply them to the transcript in
   the note and in the sidecar, without rewriting the rest of the transcript;
2. add those replacements to the glossary;
3. save the instructions with the meeting;
4. regenerate the summary with the current summary type and re-tag the meeting, with the instructions as context.
Applying SHALL run in one step without a confirmation of the replacements: the sheet SHALL show only progress, and
on failure nothing SHALL change and the error SHALL be shown.

#### Scenario: Fix a misheard client
- **WHEN** the user applies "Doctor Grim is DrGreenlife" to a meeting whose transcript says "Doctor Grim" and "doctor Greenman"
- **THEN** the transcript says "DrGreenlife" in both places, the summary is regenerated with DrGreenlife, and the meeting is tagged "client/drgreenlife"

#### Scenario: Instruction without name changes
- **WHEN** the user applies "Pablo Veliz works at VNS, he is not the client"
- **THEN** the transcript is unchanged, and the summary and tags are regenerated with that instruction as context

#### Scenario: Provider error
- **WHEN** the model call fails while applying instructions
- **THEN** the transcript, summary and tags stay as they were and the error is shown

### Requirement: Instructions are kept
The instructions applied to a meeting SHALL be stored with it and SHALL be sent as context in every later summary
regeneration and re-tag of that meeting. The meeting detail SHALL NOT display them; opening "Correct with
instructions…" again SHALL start from the saved instructions so the user can edit and re-apply them.

#### Scenario: Edit saved instructions
- **WHEN** the user opens "Correct with instructions…" on a meeting that already has instructions
- **THEN** the field contains the saved instructions, and the meeting detail shows no instructions text otherwise

#### Scenario: Regenerate later
- **WHEN** the user regenerates the summary of a meeting that has instructions
- **THEN** the request includes those instructions

### Requirement: Glossary
Settings › Summaries SHALL show the glossary: a list of corrections ("heard as" → "correct spelling") that the user
can add, edit and delete. When a meeting is saved, Minutes SHALL apply the glossary to its transcript (whole words,
case-insensitive) before summarizing and tagging, and SHALL send the glossary as context.

#### Scenario: Correction remembered
- **WHEN** the glossary maps "Doctor Grim" to "DrGreenlife" and a new meeting's transcript says "Doctor Grim"
- **THEN** the saved transcript says "DrGreenlife", and so do its summary and tags

#### Scenario: Edit the glossary
- **WHEN** the user deletes a glossary entry
- **THEN** later meetings no longer apply it, and past transcripts stay as they are


## MODIFIED Requirements

### Requirement: Summary types
Minutes SHALL provide the built-in summary types General, Client call, Standup and 1:1, each with editable
instructions and a "Reset to default" action. The user SHALL be able to add, edit and delete custom summary types
and choose the default type. Summaries SHALL be written in the meeting's chosen language when the user set one
(English or Spanish), and otherwise in the language most of the transcript is spoken in, as judged by the model
from the whole transcript, including the section headings. Minutes SHALL NOT detect the language itself.

#### Scenario: Custom type
- **WHEN** the user adds a summary type named "Sales call" with their own instructions
- **THEN** it appears in Settings and in the Meetings window and produces summaries following those instructions

#### Scenario: Default type deleted
- **WHEN** the user deletes the custom type that is set as default
- **THEN** the default returns to General

#### Scenario: Spanish meeting in Auto
- **WHEN** a meeting held in Spanish is summarized and no language was chosen for it
- **THEN** the summary and its section headings are in Spanish

#### Scenario: Chosen language wins
- **WHEN** the user chose English for a meeting whose transcript is mostly Spanish and regenerates its summary
- **THEN** the summary is written in English

## ADDED Requirements

### Requirement: Summary language per meeting
Each meeting SHALL have a summary language of Auto (default), English or Español. Auto SHALL ask the model to
write in the language most of the transcript is spoken in, even though the instructions are in English. A chosen
language SHALL be stored with the meeting and used by every later summary regeneration, correction and re-tag of
that meeting until the user sets it back to Auto. New meetings SHALL start as Auto.

#### Scenario: Choice is kept
- **WHEN** the user chose Español for a meeting and later regenerates it with another summary type
- **THEN** the new summary is in Spanish

#### Scenario: Back to Auto
- **WHEN** the user sets a meeting back to Auto
- **THEN** the stored choice is removed and the summary is regenerated in the language the model finds in the transcript

#### Scenario: Sidecar deleted
- **WHEN** the sidecar of a meeting with a chosen language is deleted
- **THEN** the meeting behaves as Auto

## Purpose

Defines how Minutes produces meeting titles and summaries through a user-configured OpenAI-compatible chat
endpoint, and how the user chooses and edits summary types.

## ADDED Requirements

### Requirement: Summary provider
Minutes SHALL generate titles and summaries through one OpenAI-compatible chat completions endpoint configured
by base URL, optional API key and model. Settings SHALL offer presets (Ollama, DeepSeek, OpenAI, Custom) that fill
the base URL and a suggested model, and a "Test connection" action. The API key SHALL be stored in the Keychain.
Only the transcript, the title and the summary-type instructions SHALL be sent; never audio.

#### Scenario: Ollama preset
- **WHEN** the user selects the Ollama preset with Ollama running locally
- **THEN** the base URL becomes http://localhost:11434/v1, no API key is required, and summaries work without internet

#### Scenario: Wrong key
- **WHEN** the user tests a DeepSeek configuration with an invalid key
- **THEN** Minutes shows the provider's authentication error

### Requirement: No provider configured
When no summary provider is configured, Minutes SHALL still save the note with the transcript, an empty summary
section that says it was not generated, and a title of the form "Meeting <date> <time>" unless a calendar title
applies.

#### Scenario: First meeting without settings
- **WHEN** the user records a meeting before configuring a provider
- **THEN** the note is saved with the transcript and can be summarized later from the Meetings window

### Requirement: Summary types
Minutes SHALL provide the built-in summary types General, Client call, Standup and 1:1, each with editable
instructions and a "Reset to default" action. The user SHALL be able to add, edit and delete custom summary types
and choose the default type. Summaries SHALL be written in the language of the meeting.

#### Scenario: Custom type
- **WHEN** the user adds a summary type named "Sales call" with their own instructions
- **THEN** it appears in Settings and in the Meetings window and produces summaries following those instructions

#### Scenario: Default type deleted
- **WHEN** the user deletes the custom type that is set as default
- **THEN** the default returns to General

### Requirement: Automatic summary
When "Summarize automatically" is on (default) and a provider is configured, Minutes SHALL summarize each meeting
right after it stops, with the default summary type. Failed requests SHALL be retried up to three times with
backoff; if they still fail, the note SHALL be saved with the transcript and the error, and can be summarized later.

#### Scenario: Provider offline
- **WHEN** the provider cannot be reached after a meeting
- **THEN** the note is saved with the transcript, the summary section shows the error, and the notification says the summary failed

### Requirement: Meeting title
The title SHALL be, in order of preference: the title of the event of a followed calendar in progress when the
recording started (when calendar events are on and access is granted), a title generated from the transcript by the summary provider, or
"Meeting <date> <time>".

#### Scenario: Calendar event in progress
- **WHEN** the user starts recording during the calendar event "Client kickoff"
- **THEN** the note is titled "Client kickoff"

#### Scenario: No event and no provider
- **WHEN** there is no calendar event and no provider is configured
- **THEN** the note is titled "Meeting 2026-10-05 09:30" with the recording's local date and time

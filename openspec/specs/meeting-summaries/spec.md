# meeting-summaries Specification

## Purpose
Defines how Minutes produces meeting titles and summaries through a user-configured OpenAI-compatible chat
endpoint, and how the user chooses and edits summary types.
## Requirements
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

### Requirement: Meeting context for the model
Every summary, title and tagging request SHALL include, besides the transcript, the meeting context Minutes knows:
the meeting title, the attendees with their email domains, the user's organization for the meeting, the known
client tags, the glossary, and the meeting's own instructions. The request SHALL state that the transcript is
automatic and can misspell names, and SHALL ask the model to write names as they appear in that context.

#### Scenario: Misheard client name in the summary
- **WHEN** the transcript says "Doctor Grim" and the meeting title is "DrGreenlife - Followup"
- **THEN** the summary writes "DrGreenlife"

#### Scenario: Attendee names
- **WHEN** an attendee is "Pablo Veliz" and the transcript writes "Pablo Belis"
- **THEN** the summary writes "Pablo Veliz"

### Requirement: Concrete summaries
Summaries SHALL report concrete content: figures, prices, estimates, dates and deadlines as stated, who said or
committed to what, decisions with their reasons, and action items with owner and due date when mentioned. They
SHALL NOT pad with generic statements. The built-in General type SHALL use the sections Context, Key points,
Decisions, Action items, and Risks and open questions; empty sections SHALL say there were none.

#### Scenario: Estimate discussed
- **WHEN** a participant gives an estimate of "about 100 hours for the revamp"
- **THEN** the summary states the estimate, who gave it and for what

#### Scenario: Action item with owner
- **WHEN** someone says "I'll send the proposal on Friday"
- **THEN** Action items lists that person, the proposal, and Friday

### Requirement: Reasoning for summaries
When the provider offers a reasoning mode, summaries SHALL use it at medium effort. Summary requests SHALL NOT set an
output token limit, so the provider's own maximum applies to the reasoning and the answer; titles, tags,
corrections and the connection test SHALL NOT use reasoning and SHALL keep their own limits.

#### Scenario: DeepSeek summary
- **WHEN** the summary provider is DeepSeek and a meeting is summarized
- **THEN** the request enables thinking at medium effort, while the title and tagging requests for the same meeting do not

#### Scenario: Long reasoning
- **WHEN** the model reasons for more than 16,000 tokens before writing the summary
- **THEN** the summary is still written, because the request sets no output token limit

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


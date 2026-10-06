## ADDED Requirements

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
When the provider offers a reasoning mode, summaries SHALL use it at medium effort, with a token budget large enough
for the reasoning and the answer; titles, tags, corrections and the connection test SHALL NOT use it.

#### Scenario: DeepSeek summary
- **WHEN** the summary provider is DeepSeek and a meeting is summarized
- **THEN** the request enables thinking at medium effort, while the title and tagging requests for the same meeting do not

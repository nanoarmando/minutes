## MODIFIED Requirements

### Requirement: Automatic topic tags
When "Add topic tags automatically" is on and a summary provider is configured, Minutes SHALL tag each meeting with
at most three topic tags chosen by the model from the transcript, lowercase and hyphenated, in the meeting's chosen
summary language when one is set and otherwise in the language most of the transcript is spoken in, as judged by the
model, reusing existing topic tags when they fit.

#### Scenario: Topic tags
- **WHEN** a meeting discusses the budget and the checkout redesign
- **THEN** the note has up to three topic tags such as "budget" and "checkout"

#### Scenario: Topic tags follow the chosen language
- **WHEN** the user chose English for a Spanish meeting and it is re-tagged
- **THEN** its topic tags are in English

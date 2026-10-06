## Purpose

Defines automatic and manual tags on meetings: client tags and topic tags that the summary model detects from the
transcript, and how tags are stored, edited and refreshed. There is no client list to maintain.

## ADDED Requirements

### Requirement: Tag settings
Settings SHALL have a Tags section with the switches "Detect clients automatically" and "Add topic tags
automatically", both on by default, and a "Re-tag all meetings" action. It SHALL NOT offer any client list or client
editor.

#### Scenario: Open Tags settings
- **WHEN** the user opens Settings › Tags
- **THEN** the two switches and "Re-tag all meetings" are shown, and there is no way to add clients by hand

### Requirement: Automatic client detection
When "Detect clients automatically" is on and a summary provider is configured, Minutes SHALL ask the summary model
which external companies or organizations the meeting is with or discusses as clients, and SHALL tag the meeting
with at most two client tags of the form "client/" followed by the lowercase, hyphenated client name. Internal
meetings SHALL get no client tag. The model SHALL receive the client tags already used in the notes folder and
SHALL reuse one of them when it refers to the same client.

#### Scenario: Client call
- **WHEN** a meeting is a call with Hemisphere Brands and no client tags exist yet
- **THEN** the note is tagged "client/hemisphere-brands"

#### Scenario: Same client, different wording
- **WHEN** "client/hemisphere-brands" already exists and a later transcript only says "Hemisphere" or "HB"
- **THEN** the later note is tagged "client/hemisphere-brands", not a new client tag

#### Scenario: Internal meeting
- **WHEN** a team standup mentions no external company as a client
- **THEN** the note has no client tag

### Requirement: Automatic topic tags
When "Add topic tags automatically" is on and a summary provider is configured, Minutes SHALL tag each meeting with
at most three topic tags chosen by the model from the transcript, lowercase and hyphenated, in the language of the
meeting, reusing existing topic tags when they fit.

#### Scenario: Topic tags
- **WHEN** a meeting discusses the budget and the checkout redesign
- **THEN** the note has up to three topic tags such as "budget" and "checkout"

### Requirement: Tagging runs after saving
Automatic tagging SHALL run with one model call after the note is saved, for every meeting when a provider is
configured, even when automatic summaries are off, and SHALL NOT delay saving the note. When tagging fails or no
provider is configured, the note keeps no automatic tags and can be re-tagged later.

#### Scenario: No provider
- **WHEN** no summary provider is configured
- **THEN** the note is saved without automatic tags

### Requirement: Tag storage
Tags SHALL be stored in the note's front matter as a "tags" list compatible with Obsidian. Tags added by the user
SHALL be marked as manual in the sidecar.

#### Scenario: Open in Obsidian
- **WHEN** the user opens a tagged note in Obsidian
- **THEN** Obsidian shows the note's tags

### Requirement: Edit tags
In the Meetings window the user SHALL be able to add and remove tags on a meeting; adding SHALL suggest existing
tags. Changes SHALL be written to the note immediately.

#### Scenario: Add a tag by hand
- **WHEN** the user adds the tag "client/acme" to a meeting
- **THEN** the note's front matter includes it and the tag is marked as manual

### Requirement: Re-tag
The user SHALL be able to re-tag one meeting from its detail view, or every meeting from Settings › Tags. Re-tagging
SHALL replace the automatic tags and keep manual tags. Re-tagging every meeting SHALL ask for confirmation stating
the number of meetings, show progress, and be stoppable.

#### Scenario: Re-tag after turning on client detection
- **WHEN** the user turns on "Detect clients automatically" and re-tags every meeting
- **THEN** past client meetings gain their client tags, and tags the user added by hand are kept

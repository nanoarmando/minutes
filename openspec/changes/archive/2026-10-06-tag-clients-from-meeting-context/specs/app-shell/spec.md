## MODIFIED Requirements

### Requirement: Settings window
Settings SHALL have six sections. General: launch at login, recording shortcut, notes folder, file name
pattern, keep audio, permission status. Calendar: use calendar events, suggest recording when a meeting starts, and
the followed calendars. Transcription: engine (on this Mac or API), local model status, API base URL, key and model,
speaker separation. Summaries: provider preset, base URL, key, model, test connection, summarize automatically,
default summary type, summary types. Tags: detect clients automatically, add topic tags automatically, your email
addresses, re-tag all meetings. Integrations: AI agents and their Minutes skill. Changes SHALL apply immediately
without a Save button.

#### Scenario: Shortcut conflict
- **WHEN** the user sets a recording shortcut already used by the system
- **THEN** Minutes rejects it and keeps the previous shortcut

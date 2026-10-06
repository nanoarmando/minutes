# app-shell Specification

## Purpose
Defines the app's surfaces outside the meeting pipeline: the menu bar item and menu, Settings, About, launch at
login and appearance.
## Requirements
### Requirement: Menu bar app
Minutes SHALL run as a menu bar item. Its menu SHALL show, when idle: the active transcription engine, "Start
recording" with its shortcut, "Update available (<version>)" only when a newer release is known, "All meetings…",
"Open notes folder", "Settings…", "About Minutes" and "Quit"; it SHALL NOT list individual meetings; while recording: elapsed time, source levels, "Stop & summarize" and
"Discard"; while processing: the progress of transcript, speakers and summary.

#### Scenario: Idle menu
- **WHEN** the user clicks the menu bar item with no recording in progress
- **THEN** the idle menu appears without any meeting titles, and "All meetings…" opens the Meetings window

#### Scenario: Menu closes after an action
- **WHEN** the user chooses any action in the menu
- **THEN** the menu closes and the chosen window, if any, comes to the front

### Requirement: Dock icon while a window is open
Minutes SHALL show its icon in the Dock and in the app switcher while the Meetings, Settings or About window is
open, and SHALL remove it when the last of them closes.

#### Scenario: Find the Meetings window
- **WHEN** the Meetings window is open behind other apps
- **THEN** Minutes appears in the Dock and in the app switcher, and clicking its Dock icon brings the window to the front

#### Scenario: Last window closed
- **WHEN** the user closes the last open Minutes window
- **THEN** the Dock icon disappears and Minutes keeps running in the menu bar

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

### Requirement: About window
The About window SHALL show the app icon, name, version and build, a one-line description, the copyright line
"© 2026 Jose Bianco", the license (AGPL-3.0), credits to FluidAudio, Parakeet (NVIDIA), and Muesli (MIT),
links to the source code and licenses, and the update status with its actions (see app-updates).

#### Scenario: Open About
- **WHEN** the user chooses "About Minutes"
- **THEN** the About window shows the version, the copyright, the credits and the update status

### Requirement: Launch at login
Minutes SHALL offer a launch-at-login setting, off by default, registered through the system login items.

#### Scenario: Enable launch at login
- **WHEN** the user turns on launch at login and restarts the Mac
- **THEN** Minutes is running in the menu bar after login

### Requirement: Light and dark appearance
Every window and the menu SHALL follow the system light or dark appearance and update when it changes, with all
text and controls legible in both.

#### Scenario: Switch to dark mode
- **WHEN** the user switches macOS to dark mode while the Meetings window is open
- **THEN** the window, Settings, About and the menu switch to dark colors without restarting


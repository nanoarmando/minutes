## Why

Granola-style meeting notes are useful, but the hosted tools keep transcripts in someone else's cloud, and the
open-source alternatives tried so far (Muesli, Anarlog, Meetily) bundle dictation, agents, sync and telemetry
around the meeting feature, which makes them heavy and, in Muesli's case, slow. Minutes keeps only the meeting
part: record from the menu bar, transcribe on the Mac, summarize with a model the user picks, and store the
result as plain Markdown files the user owns.

## What Changes

- New native macOS 14.2+ menu-bar app "Minutes" (Apple silicon), built from scratch in a new public repository.
- Records a meeting from the menu bar or a global shortcut, capturing the microphone ("You") and the system audio
  (everyone else on the call) without a bot joining the call.
- Transcribes while recording, in short chunks, with Parakeet v3 on the Mac by default, or with any
  OpenAI-compatible transcription API when the user opts in. Separates remote speakers as "Speaker 1",
  "Speaker 2"… after the meeting.
- Generates a title and a summary through any OpenAI-compatible chat endpoint (Ollama, DeepSeek, OpenAI…), using
  selectable summary types (General, Client call, Standup, 1:1 and user-defined ones).
- Saves every meeting as a Markdown note plus a JSON sidecar in a user-chosen folder; no database. Audio is
  deleted after transcription unless the user keeps it.
- A Meetings window lists the saved notes, shows summary and transcript, searches them, and regenerates a
  summary with another summary type.
- Tags: up to two client tags (external companies the meeting is with) and up to three topic tags, both detected by
  the summary model, which reuses existing tags; no client list to maintain;
  editable by hand, re-taggable and searchable from the Meetings search field.
- Integrations: a Settings section that detects AI coding agents installed on the Mac (Claude Code, Codex,
  GitHub Copilot, Gemini CLI and OpenCode) and installs, updates or removes a read-only "minutes" skill that tells
  the agent how to read the notes folder. Minutes keeps a dictionary file in the notes folder (note format,
  client tags, topic tags, summary types and a catalog of every meeting) that the skill points the agent to.
- Calendar: access requested from Settings, a list of calendars to follow (all by default), and the event in
  progress at the start of a recording provides the title, attendees, meeting link and calendar name of the note.
  When a scheduled call starts (an event with a link or attendees), a system notification offers "Start recording".
- Settings (General, Calendar, Transcription, Summaries, Tags, Integrations) and About windows; follows the system light or
  dark appearance.
- In-app updates from GitHub releases: checked at launch, daily and when About opens; the menu shows "Update
  available" and About installs it after verifying the signature.
- The menu does not list meetings; a Dock icon appears while a Minutes window is open.
- Local signed build; AGPL-3.0 license (© 2026 Jose Bianco) with credit to Muesli and FluidAudio.

## Capabilities

### New Capabilities
- `meeting-recording`: starting, stopping and discarding a recording; microphone and system-audio capture;
  permissions; global shortcut; recovery after a crash.
- `transcription`: on-device chunked transcription, optional hosted transcription, speaker labels, echo filter.
- `meeting-summaries`: AI provider configuration, summary types, automatic and manual summaries, titles.
- `meeting-notes`: the notes folder, Markdown and JSON file format, audio retention.
- `meetings-window`: browsing, reading, searching and re-summarizing saved meetings.
- `calendar`: calendar access, followed calendars, recording suggestions when a call starts, and event data in
  the note.
- `agent-integrations`: detecting AI coding agents, installing and maintaining the read-only skill, and the
  notes dictionary it relies on.
- `meeting-tags`: automatic client and topic detection, manual tags, re-tagging.
- `app-shell`: menu bar item, Settings, About, launch at login, appearance.
- `app-updates`: checking, offering and installing new versions from GitHub releases, and packaging releases.
- `local-build`: building, signing and licensing the app on the user's Mac.

### Modified Capabilities
- None (new project).

## Impact

- New repository `github.com/nanoarmando/minutes` (public, AGPL-3.0).
- Dependencies: FluidAudio (Apache-2.0) and KeyboardShortcuts (MIT), as Swift packages. No telemetry, third-party update framework or other ML runtimes.
- System integrations: Core Audio process tap (system audio), AVAudioEngine (microphone), EventKit (title, attendees, meeting link
  and calendar name of the event in progress, from the calendars the user follows), Keychain (API keys), SMAppService (launch at login), the user-level skill folders of the supported
  AI agents (`~/.claude/skills`, `~/.agents/skills`, `~/.copilot/skills`, `~/.gemini/skills`,
  `~/.config/opencode/skills`).
- Network: only the endpoints the user configures (transcription API, summary API), GitHub release checks and
  downloads, plus the one-time Parakeet
  and FluidAudio model downloads from Hugging Face.

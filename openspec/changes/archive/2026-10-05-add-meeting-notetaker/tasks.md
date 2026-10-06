## 1. Project setup

- [x] 1.1 Create `Package.swift` (Swift 6, macOS 14.2, arm64) with the `Minutes` executable target, the ObjC
      exception-shim target, and pinned FluidAudio 0.15.5 and KeyboardShortcuts dependencies
- [x] 1.2 Add `Scripts/build.sh` that builds, assembles `Minutes.app` (Info.plist keys, entitlements), signs with
      "Minutes Self-Signed", stops with setup instructions when the identity is missing, and installs to /Applications
- [x] 1.3 Add `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md` (FluidAudio, Muesli, KeyboardShortcuts), `.gitignore`
- [x] 1.4 Create the folder layout from design D2 and the `AppEnvironment` composition root

## 2. Audio capture

- [x] 2.1 Port `SystemAudioTap` from Muesli `CoreAudioSystemRecorder` (process tap excluding own process, private
      aggregate device with stable-UID cleanup, mono 16 kHz Int16 output, permission probe), with origin header
- [x] 2.2 Port `MicRecorder` from Muesli `StreamingMicRecorder` with the ObjC exception shim, following
      default-device changes without stopping
- [x] 2.3 Add `WavWriter` and `ChunkRecorder` (rotating 16 kHz WAV chunks, sample-count timing)
- [x] 2.4 Add `Permissions` (microphone, system audio probe, calendar) with System Settings deep links
- [x] 2.5 Expose per-source audio levels at 10 Hz and detect an all-silent system track

## 3. Transcription

- [x] 3.1 Verify FluidAudio 0.15.5 APIs for ASR, VAD and diarizer loading and model download; record findings in AGENTS.md
- [x] 3.2 Implement `VadChunker` (pause-based 3–5 s chunks, silence gate)
- [x] 3.3 Implement `ParakeetEngine` with download progress and a queue for chunks recorded before the model is ready
- [x] 3.4 Implement `OpenAICompatibleSTT` (multipart per chunk, 3 retries, on-device fallback, gap marker)
- [x] 3.5 Implement `Diarizer` (post-stop, full system WAV, failure → "Others")
- [x] 3.6 Implement `TranscriptAssembler` (You/Speaker N labels by overlap, 2 s merge, echo filter, ordering)

## 4. Recording session and recovery

- [x] 4.1 Implement the `RecordingSession` actor (start, stop, discard, state events to the main actor)
- [x] 4.2 Implement `InProgressStore` (session.json, segments.jsonl appended per chunk, audio, cleanup)
- [x] 4.3 Recover unfinished sessions on launch and save them with `recovered: true`
- [x] 4.4 Stop on system sleep; confirm stop/discard/cancel on Quit while recording

## 5. Notes

- [x] 5.1 Implement `NoteWriter` (file name pattern, collisions, front matter, summary markers, sidecar, atomic writes,
      optional m4a audio)
- [x] 5.2 Implement summary-section replacement that keeps edits elsewhere in the file
- [x] 5.3 Implement `NoteIndex` (front-matter-only scan, folder watching with debounce, lazy search text cache)
- [x] 5.4 Handle an unavailable notes folder by keeping the meeting in progress until a writable folder is chosen

## 6. Summaries

- [x] 6.1 Implement `ChatClient` (base URL normalization, chat completions, token parameter per host, timeout, retries)
- [x] 6.2 Implement `SummaryTypeStore` (built-ins General, Client call, Standup, 1:1; overrides, custom types,
      default type, reset)
- [x] 6.3 Implement `SummaryService` (title from calendar, model or date; summary in the meeting language;
      no-provider and failure paths)
- [x] 6.4 Implement calendar title lookup (event in progress with most overlap, ignore all-day events)

## 7. User interface

- [x] 7.1 Menu bar item and menu (idle, recording with levels and timer, processing steps, saved confirmation)
      in a native menu style (the user chose it over the earlier mock); the panel closes after any action
- [x] 7.2 Global shortcut with KeyboardShortcuts (default ⌘⇧R, conflict rejection)
- [x] 7.3 Completion notification that opens the meeting
- [x] 7.4 Meetings window: grouped list, summary/transcript views, Open in editor, Copy, Show in Finder, search
- [x] 7.5 Summary type chips and Regenerate with progress and error states
- [x] 7.6 Settings: General, Transcription (engine, model status/delete, API fields, test connection, speakers),
      Summaries (presets, fields, test connection, auto-summarize, default type, type editor)
- [x] 7.7 About window with version, credits and links
- [ ] 7.8 Launch at login via SMAppService; verify light and dark appearance on every screen

## 8. Tags

- [x] 8.1 Implement `ClientStore` (clients with aliases, tag slugs) and the Settings › Tags section (client editor,
      topic tags switch, re-tag all with confirmation, progress and Stop)
- [x] 8.2 Implement `TagService` (local name/alias matching, model tagging call with existing topics, merge into
      front matter, manual tags kept in the sidecar, failure keeps local tags)
- [x] 8.3 Meetings tab: search matches tags and client names/aliases (no tag chips), tags in the detail view, add/remove tags with suggestions, re-tag one meeting

- [x] 8.4 Remove the client list: `ClientStore`, `clients.json`, the client editor in Settings › Tags, local
      name/alias matching and alias search; add the "Detect clients automatically" switch (on by default)
- [x] 8.5 Change `TagService` to detect clients with the model (external companies only, at most two, reuse existing
      client and topic tags from the notes folder, slug and `client/` prefix), honoring both switches; update the
      dictionary's client section to client tags with meeting counts
## 9. Integrations

- [x] 9.1 Remove Ask: `AskService`, `AskRanking`, `AskView`, the Meetings/Ask tabs (the Meetings window becomes a
      single view) and every Ask-only helper or state in `NoteIndex`, `ChatClient` and `AppEnvironment`
- [x] 9.2 Implement `NotesDictionary` (note format, clients with tag and aliases, topic tags with counts, summary
      types, last update, meeting catalog newest first; atomic, debounced writes on index, client and summary type
      changes; `.minutes` ignored by `NoteIndex`)
- [x] 9.3 Implement `AgentIntegrations` (agent table, detection, skill template with notes folder and dictionary
      paths, ownership marker, install, remove, conflict, rewrite on notes folder change and at launch when content
      differs)
- [x] 9.4 Add Settings › Integrations (privacy notice, one row per agent with status, skills folder, Install,
      Remove with confirmation, Show in Finder; refresh when shown)

## 10. Calendar

- [x] 10.1 Replace `CalendarTitle` with `CalendarService` (access request only from Settings, unfollowed-calendar
      set, event in progress of followed calendars, `EventInfo` with title, calendar, attendees and meeting link)
- [x] 10.2 Store `EventInfo` in `session.json` and write `calendar`, `attendees` and `meeting_link` to front matter
      (omitted when empty); remove the calendar request from the first recording
- [x] 10.3 Add Settings › Calendar (switch, denied state with System Settings link, calendars grouped by account with
      checkboxes) and remove the calendar switch from General
- [x] 10.4 Add start suggestions: next-start timer with re-planning (store changes, settings, wake with five-minute
      catch-up), qualifying-event filter, once per occurrence, none while recording, notification category with
      Start recording (using the notified event) and Dismiss, and the Calendar switch (on by default)

## 11. Polish, Dock and updates

- [x] 11.1 Remove recent meetings from the menu; add the "Update available (<version>)" row that opens About
- [x] 11.2 Dock icon while the Meetings, Settings or About window is open (activation policy switch, reopen brings
      Meetings to the front)
- [x] 11.3 Redesign the Meetings window per D14 (sidebar with search and day groups, reading-layout detail, tag
      chips, borderless toolbar actions that never stay pressed, formatted Markdown summary, colored speakers)
- [x] 11.4 Add the updater per D12 (`Updates/`: check at launch, daily and on About,
      verify, stage, swap, eligibility, busy guard)
- [x] 11.5 About: icon, version and build, copyright "© 2026 Jose Bianco", AGPL-3.0, credits,
      links, update status with Check / Install / release notes / errors
- [x] 11.6 Add `Scripts/build-dmg.sh` and a single `VERSION` source shared with `build.sh`
- [x] 11.7 Relicense to AGPL-3.0: `LICENSE`, `THIRD_PARTY_NOTICES.md` (keep MIT/Apache notices), README

## 12. Verification and documentation

- [ ] 12.1 Manual check: Meet in a browser and Zoom, with built-in speakers and with AirPods; English, Spanish and mixed
- [ ] 12.2 Manual check: API engine against OpenAI, summaries and tags against Ollama and DeepSeek, provider offline path; record during a calendar event with guests and a Meet link, start one from the start notification; install the skill in Claude Code and Codex and ask a question about a past meeting
- [ ] 12.3 Manual check: crash recovery (kill during recording), 500-note folder opens in under one second
- [x] 12.4 Write README.md (install, signing setup, usage, privacy) and AGENTS.md (structure, conventions, contracts)
- [x] 12.5 Create the public GitHub repository `nanoarmando/minutes`, push, and publish release v0.1.0 with its DMG

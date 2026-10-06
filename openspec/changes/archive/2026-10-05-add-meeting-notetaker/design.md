## Context

New repository; nothing exists yet. See proposal.md for motivation and the specs for behavior. The meeting
pipeline is adapted from Muesli (MIT, FluidAudio 0.15.5). A code read of Muesli found that its slowness comes from
a 12,000-line main-actor controller that re-reads 200 full meetings from SQLite on every state change and pushes a
~100-property global state object; Minutes is shaped to avoid that.

Constraints: macOS 14.2+ (Core Audio process taps), Apple silicon (Parakeet on the Neural Engine), Swift 6
language mode, not sandboxed (hardened runtime), self-signed local builds.

## Goals / Non-Goals

**Goals:**
- A meeting-only core of roughly 4,000 lines, readable by one person.
- The UI never waits on disk, network or ML work.
- The notes folder is the only durable store for finished meetings.

**Non-Goals (this change):**
- Live transcript view, personal notes during the meeting, call detection from microphone or app activity,
  reminders before an event starts, automatic recording.
- Neural echo cancellation, PDF export, post-meeting hooks, iCloud sync, a CLI.
- Summarizing transcripts longer than the chosen model's context (the provider's error is shown).
- Intel Macs and macOS versions older than 14.2.

## Decisions

### D1. Swift package plus a bundling script, no Xcode project
`Package.swift` defines one executable target (`Minutes`) and a small ObjC target for the AVAudioEngine exception
shim. `Scripts/build.sh` runs `swift build -c release --arch arm64`, assembles `Minutes.app` (Info.plist with
`LSUIElement`, `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`,
`NSCalendarsFullAccessUsageDescription`, `LSMinimumSystemVersion` 14.2), signs it with "Minutes Self-Signed",
hardened runtime and `com.apple.security.device.audio-input`, and installs it in /Applications.
*Alternatives:* an Xcode project (opaque diffs, hard for agents to edit), XcodeGen (extra tool, not installed).
Muesli uses the same package-plus-script approach.

### D2. Module layout (folders inside the one target)
- `App/` – `@main` SwiftUI app: `MenuBarExtra(.window)`, `Window("Meetings")`, `Settings`, About window,
  `AppEnvironment` composition root.
- `Capture/` – `SystemAudioTap` (process tap + private aggregate device, adapted from Muesli
  `CoreAudioSystemRecorder`, keeping the stable-UID cleanup and permission probe), `MicRecorder` (AVAudioEngine tap
  following default-device changes, adapted from `StreamingMicRecorder`), `WavWriter`, `ChunkRecorder`.
- `Pipeline/` – `RecordingSession` (actor owning one meeting), `VadChunker` (Silero VAD, cut at pauses, 3–5 s
  chunks as in Muesli; silence-gated), `TranscriptionEngine` protocol with `ParakeetEngine` and
  `OpenAICompatibleSTT`, `Diarizer`, `TranscriptAssembler` (speaker labels, 2 s merge, echo filter).
- `Calendar/` – `CalendarService` (access, followed calendars, event lookup).
- `Summaries/` – `ChatClient` (OpenAI-compatible), `SummaryTypeStore`, `SummaryService` (title + summary, retries).
- `Notes/` – `NoteWriter` (Markdown + sidecar, atomic), `NoteIndex` (folder scan + file watching),
  `InProgressStore` (crash recovery).
- `Settings/` – `Preferences` (UserDefaults), `KeychainStore`, `Permissions`, `LaunchAtLogin` (SMAppService).
- `Integrations/` – `AgentIntegrations` (agent table, detection, skill install/update/remove), `NotesDictionary`.
- `Updates/` – `AppVersion`, `UpdateRelease`,
  `UpdateEligibility`, `UpdateClient`, `UpdateInstaller`, `UpdateCoordinator`.
- `UI/` – menu, Meetings, Settings and About views with one small `@Observable` model per screen.

### D3. Threading model
Audio callbacks only copy samples into a serial `DispatchQueue` owned by the capture objects; nothing on that
path touches the main actor. `RecordingSession` is an actor; transcription runs in detached tasks per chunk and
reports results to the session. The main actor receives coarse events only (state, elapsed time once per second,
levels at 10 Hz, processing step). There is no global "sync everything" function.
*Alternative:* Muesli's main-actor controller – rejected as the cause of its slowness.

### D4. Transcription
- On-device: FluidAudio `AsrManager` with Parakeet v3 (`AsrModels` v3), `VadManager` for chunk boundaries and the
  silence gate. Model download through FluidAudio's own helpers, cached in its default location; progress is
  surfaced in the menu and Settings. While the model is missing, finished chunk WAVs queue in the in-progress
  folder and are processed after the download.
- API: per chunk, `POST <base>/audio/transcriptions` as `multipart/form-data` with `file` (16 kHz mono WAV),
  `model` and `response_format=json`; text is placed at the chunk's start offset. Per-chunk requests keep every
  upload far below the 25 MB OpenAI limit. Three retries with backoff, then on-device fallback if the model is
  installed, else a gap marker `[HH:MM:SS–HH:MM:SS transcription unavailable]`.
- Diarization: FluidAudio `DiarizerManager.performCompleteDiarization` once, after stop, on the full system-audio
  WAV (kept in the in-progress folder until the note is saved). Speaker assignment by maximum time overlap,
  nearest speaker within 2 s, else "Others" (Muesli `TranscriptFormatter` logic).
- Echo filter: a microphone segment is dropped when ≥50 % of its duration overlaps system speech and its
  normalized word overlap with the overlapping system text is ≥0.6. *Alternative:* port Muesli's DTLN echo
  canceller (~900 lines + model) – deferred by user decision.

### D5. Summaries
One `ChatClient` for every provider: `POST <base>/chat/completions`, non-streaming, `[system, user]` messages,
`max_tokens` 2500 (`max_completion_tokens` when the host is api.openai.com), 300 s timeout, Bearer header only when
a key exists. Base URL normalization adapted from Muesli `resolveEndpointURL`. Ollama uses its OpenAI-compatible
`/v1` endpoint, so no Ollama-specific code. System prompt = a base instruction (adapted from Muesli
`baseSummaryInstructions`, plus "write in the language of the transcript") + the summary type's instructions; user
prompt = title + transcript. Titles use a short prompt over opening, middle and closing excerpts (Muesli
`titlePrompt`). Retries: 3 with exponential backoff.
Summary types live in `~/Library/Application Support/Minutes/summary-types.json`; built-ins ship in code and a
user edit is stored as an override, so "Reset to default" deletes the override.

### D6. Note format and index
```
---
minutes_id: 7F3C…            # UUID, how Minutes recognizes its notes
title: Client kickoff
date: 2026-10-04T15:00:00-04:00
duration: 2820               # seconds
speakers: [You, Speaker 1, Speaker 2]
summary_type: client-call
transcription: parakeet-v3
summary_model: deepseek-chat
recovered: false
audio: .minutes/7F3C….m4a     # only when kept
calendar: Work               # calendar keys only when an event matched
attendees: [Ana Pérez, john@acme.com]
meeting_link: https://meet.google.com/abc-defg-hij
---
# Client kickoff

## Summary
<!-- minutes:summary:start -->
…
<!-- minutes:summary:end -->

## Transcript
**[00:00:42] Speaker 1:** …
```
Regeneration replaces only the text between the markers (falls back to the "## Summary" heading if markers were
removed). Writes go to a temporary file and are moved into place. The sidecar `.minutes/<id>.json` holds segments
and summary metadata. `NoteIndex` reads only front matter for the list (first 2 KB of each file), watches the
folder with a `DispatchSource` file-system object plus a debounced rescan, and builds search text lazily on a
background task, cached by file modification date.

### D7. Crash recovery
`~/Library/Application Support/Minutes/InProgress/<id>/` holds `session.json` (start time, calendar event data,
settings snapshot), `segments.jsonl` (one line appended per transcribed chunk), the system-audio WAV and queued
chunks. It is deleted after the note is saved or the meeting discarded. On launch, any folder found is finished
with the segments it has (diarization runs if the system WAV is readable) and saved with `recovered: true`. The
same folder holds a finished meeting whose notes folder is unavailable until the user picks a writable one.

### D8. Settings, secrets, shortcut, appearance
Preferences in UserDefaults; API keys in the Keychain (service `com.minutes.app`, one item per endpoint kind).
Global shortcut with sindresorhus/KeyboardShortcuts (MIT): recorder UI and system-conflict detection for free.
*Alternative:* Carbon `RegisterEventHotKey` by hand – more code than a maintained package and no recorder UI. Colors use semantic system colors and materials only, so light and dark mode need no extra code.

### D9. Calendar
`Summaries/CalendarTitle.swift` becomes `Calendar/CalendarService.swift`. Settings › Calendar holds the "Use
calendar events" switch (preference `useCalendar`, off by default); turning it on is the only place that calls
`EKEventStore.requestFullAccessToEvents()`. Followed calendars are stored as the set of **unfollowed** calendar
identifiers, so every calendar, including ones added later, is followed by default. The list groups
`EKCalendar`s by `source.title`.
At recording start, when the switch is on and access is granted, the service looks up events of followed
calendars overlapping the start time, ignores all-day events and picks the one in progress with the most overlap.
It returns an `EventInfo` (title, calendar name, attendees, meeting link) that is stored in `session.json` (so a
recovered meeting keeps it) and written to front matter as `calendar`, `attendees` and `meeting_link`, omitting
empty values. Attendees come from `EKParticipant.name`, falling back to the email in `url`, skipping
`isCurrentUser`. The meeting link is `event.url`, else the first URL in `location` or `notes` whose host is
zoom.us, meet.google.com, teams.microsoft.com, teams.live.com or webex.com. The lookup stays asynchronous after
capture starts, so it never delays the start.
**Start suggestions** – while the switch "Suggest recording when a meeting starts" (preference `suggestRecording`,
on by default) and calendar access are on, `CalendarService` keeps one timer for the next qualifying start
(followed calendar, not all-day, a meeting link or at least one attendee). It re-plans on `EKEventStoreChanged`,
on calendar setting changes, after firing and on wake (`NSWorkspace.didWakeNotification`), when events that
started less than five minutes earlier are also notified. Notified occurrences are remembered in memory by
`eventIdentifier` plus start date. The notification uses a `UNNotificationCategory` with the actions "Start
recording" and "Dismiss" and carries the occurrence in `userInfo`; "Start recording" passes that event's
`EventInfo` to the session instead of running the lookup. Nothing is posted while a recording is in progress.
*Alternative:* microphone-in-use detection (as in Muesli) – rejected by user decision: it also fires for
dictation and voice notes.

### D10. Agent integrations (skill + notes dictionary, no in-app chat)
Questions across meetings are answered by the AI agents the user already runs, not inside Minutes. Minutes only
makes the notes easy for them to read.
- **Agent table** – one constant list in `Integrations/AgentIntegrations.swift`: name, detection folder and skills
  folder. Claude Code `~/.claude` → `~/.claude/skills`; Codex `~/.codex` → `~/.agents/skills` (the location Codex
  documents for user skills; `~/.codex/skills` is legacy); GitHub Copilot `~/.copilot` → `~/.copilot/skills`;
  Gemini CLI `~/.gemini` → `~/.gemini/skills`; OpenCode `~/.config/opencode` → `~/.config/opencode/skills`.
  Detection is a folder-exists check; no process launches or PATH lookups.
- **Skill** – `<skills folder>/minutes/SKILL.md`, rendered from one template with the notes folder's absolute path:
  front matter `name: minutes` and a description that triggers on questions about meetings, calls, clients or
  decisions; body with the read-only rule, the dictionary path, the search order (catalog in the dictionary, then
  text search in the `.md` notes, then read the note), the citation format (title, date, file) and a pointer to the
  note format section of the dictionary. A line `<!-- generated-by: minutes -->` is the ownership marker. Install,
  update and remove act only on folders whose SKILL.md contains it.
- **Updates** – installed skills are re-rendered when the notes folder changes and at launch; a file is written only
  when its content differs.
- **Dictionary** – `Integrations/NotesDictionary.swift` renders `.minutes/dictionary.md` from `NoteIndex` entries
  (front matter only, so no note body is read) and `SummaryTypeStore`. It is rewritten atomically,
  debounced 2 s, after any `NoteIndex` change (covers saves, summary and tag edits, and external file changes) and
  after summary type changes. It is always maintained, whether or not a skill is installed, so it is
  ready when the user installs one. `NoteIndex` ignores the `.minutes` folder.
- **UI** – Settings › Integrations: privacy notice, then one row per agent with status (Not detected, Detected,
  Installed, Conflict), skills folder, Install / Remove (with confirmation) and Show in Finder.
*Alternatives:* an in-app Ask chat with keyword ranking and batched reading (built first, then dropped by user
decision: the agents already search and reason over files better, and it removed a large surface from the app); a
local MCP server (`add-mcp-server`, discarded by user decision in favor of skills); one shared install in
`~/.agents/skills` for every agent (Claude Code does not read it); Claude Desktop chat
(skills there run in a cloud sandbox and cannot read local files – excluded by user decision).

### D11. Tags
There is no client list. After the note is saved, one model call (in `TagService`) returns JSON
`{ "clients": [...], "topics": [...] }` from the transcript (whole when it fits the 48,000-character budget,
otherwise evenly spaced excerpts covering the whole meeting) plus the client tags and topic tags already used in the
notes folder (from `NoteIndex`). The prompt defines a client as an external company or organization the meeting is
with or discusses as a client, asks for none in internal meetings, and requires reusing an existing tag when it is
the same client or topic ("Hemisphere" and "HB" → `client/hemisphere-brands`). Minutes slugs each name (lowercase,
accents removed, hyphenated), prefixes clients with `client/`, keeps at most two clients and three topics, and
merges the result into front matter `tags:` (Obsidian list form). The switches `detectClients` and `topicTags`
(both on by default) drop the matching part of the request; with both off, no call is made. The call runs
independently of the summary setting; a failure leaves the note without automatic tags. The sidecar records which
tags are manual. Re-tag recomputes automatic tags and keeps manual ones; re-tag all runs sequentially with progress
and Stop.
*Alternatives:* a user-maintained client list with aliases and local name matching (built first, then dropped by
user decision: detection should be automatic); asking for tags inside the summary call (rejected to keep the summary
text clean and parsing reliable); learned aliases stored in a file (not needed: reusing existing tags avoids
duplicates).

### D12. In-app updates
The updater is the authors' own code, reused from their earlier app under the same AGPL-3.0 license.
- **Check** – `GET https://api.github.com/repos/nanoarmando/minutes/releases/latest` on a private ephemeral
  session (`User-Agent: Minutes`, `Accept: application/vnd.github+json`, no cache, no other headers). Tag `v<x.y.z>`;
  the asset `Minutes-<x.y.z>.dmg`. Compared numerically with `CFBundleShortVersionString`. `UpdateCoordinator`
  (main actor, owned by `AppEnvironment`) checks at launch, every 24 h with one timer, and when About appears;
  results are in memory only. A 403/429 shows GitHub's message.
- **Verify** – download to `~/Library/Caches/Minutes/updates/`, `hdiutil attach -nobrowse -readonly -noautoopen
  -mountrandom`, then `SecStaticCodeCheckValidity` with `kSecCSStrictValidate | kSecCSCheckNestedCode` against the
  running app's designated requirement (`SecCodeCopySelf` + `SecCodeCopyDesignatedRequirement`; for "Minutes
  Self-Signed" it pins the certificate leaf hash) and the release version. The verified app is copied with
  `ditto --noextattr --noqtn` to a staging folder, the DMG is detached and deleted, and the staged copy is verified
  again.
- **Swap** – a fixed `/bin/sh` script with quoted paths waits for the PID to exit, renames the installed app to a
  sibling `.Minutes-previous.app`, moves the staged app in, restores the previous one on failure, clears
  quarantine, opens the result and deletes the previous copy. Minutes then terminates normally. Installing is
  disabled while `AppEnvironment.isBusy`.
- **Eligibility** – bundle id `com.minutes.app`, not under `/Volumes/` or `/AppTranslocation/`, writable parent.
- **Release** – `Scripts/build-dmg.sh <version>` reuses `build.sh` (build and sign, without installing) and makes
  `Minutes-<version>.dmg` with `hdiutil create` (app + `/Applications` link). Publishing is
  `gh release create v<version> Minutes-<version>.dmg --notes …`. `VERSION` lives in one place used by both
  scripts.
*Alternative:* Sparkle – an extra framework, its own signing keys and appcast; overkill for one maintainer.

### D13. Dock icon while a window is open
The app stays `LSUIElement`. `AppEnvironment` switches `NSApp.setActivationPolicy(.regular)` when the Meetings,
Settings or About window opens and back to `.accessory` when the last of them closes, observed through
`NSWindow.willCloseNotification` / `didBecomeKeyNotification` filtered by those window identifiers. With the
regular policy the bundle icon shows in the Dock and the app switcher; `applicationShouldHandleReopen` brings the
Meetings window to the front.

### D14. Meetings window layout
`NavigationSplitView` with the search field in the sidebar (`.searchable(placement: .sidebar)`), rows with title
and "09:30 · 11 min", grouped by Today / Yesterday / weekday-or-date. The detail is a `ScrollView`, not a `Form`:
title (`.largeTitle`, semibold), meta line, tag chips (capsules; `client/` tags tinted with the accent color), a
toolbar with icon buttons (Open in editor, Copy, Show in Finder) using `.borderless` buttons so no pressed state
sticks, a segmented Summary / Transcript picker, summary type chips with Regenerate, and Markdown rendered with
`AttributedString(markdown:)` per block (headings, bullets, `- [ ]` as checkboxes) inside a readable max width
(about 720 pt). Transcript lines: monospaced time, speaker name in a color picked from a fixed palette by speaker
order, then the text. Colors are semantic or system palette only.

## Risks / Trade-offs

- [The process tap returns silence when permission is denied, with no API to read the state] → Muesli's
  create-a-tap probe at start, plus the "only the microphone was recorded" warning when the system track is silent.
- [A crash can leave a private aggregate device behind] → stable device UID with cleanup on start (from Muesli).
- [FluidAudio API names come from Muesli call sites, not FluidAudio's source] → pin FluidAudio 0.15.5 first and
  verify the download/load helpers before porting; adjust the wrapper only.
- [Self-signed builds: TCC grants are tied to the signing identity] → one stable identity, documented setup; the
  updater refuses releases signed with another identity, so a lost certificate means one manual install.
- [Simple echo filter misses paraphrased echo] → recommend headphones in Settings help text; neural echo
  cancellation can be added later behind the same `TranscriptAssembler` step.
- [Long meetings vs small local models' context] → error is surfaced and the transcript is kept; chunked
  summarization deferred.
- [Copilot and OpenCode also scan `~/.agents/skills` and `~/.claude/skills`, so with several agents installed they
  may see the "minutes" skill twice] → every copy has identical content and name, so duplicates are harmless.
- [Agent skill folders and formats keep changing] → the agent table is one constant list; adjusting a path is a
  one-line change.
- [The model may tag a client that was not discussed, or miss one] → at most two client tags, removable by hand;
  manual tags survive re-tagging, and re-tag recomputes with the latest model.
- [Free client and topic tags drift ("hemisphere" vs "hemisphere-brands", "budget" vs "budgets")] → the tagging
  prompt receives the existing client and topic tags and is asked to reuse them; a wrong tag can be fixed by hand.
- [Agents send note content to their own AI providers] → stated in Settings › Integrations; the skill is
  read-only.
- [The dictionary catalog grows with the number of meetings (about 50 KB for 500)] → one line per meeting, and
  the skill tells the agent to search it rather than read the whole file when it is large.
- [Diarization on long meetings takes time after stop] → shown as its own processing step; the note can be saved
  with "Others" if it fails.

## Migration Plan

None (new app). Rollback = delete /Applications/Minutes.app; notes stay in the notes folder.

## Open Questions

- Exact FluidAudio 0.15.5 helper names for model download and diarizer initialization (verified in task 3.1).

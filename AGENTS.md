# AGENTS.md

Guide for AI agents working on Minutes, a native macOS 14.2+ (Apple silicon) menu bar meeting notetaker. Human
documentation is in [README.md](README.md). Behavior is specified in `openspec/` (see "OpenSpec" below).

## Stack and build

- Swift 6 language mode, SwiftUI + AppKit, macOS 14.2 minimum, arm64 only. Not sandboxed, hardened runtime.
- Swift Package only (`Package.swift`); there is no Xcode project. Targets: `Minutes` (executable) and
  `AudioGraphShim` (ObjC, catches AVAudioEngine `NSException`s).
- Dependencies: FluidAudio **pinned exactly at 0.15.5** (Apache-2.0) and KeyboardShortcuts (MIT, 3.1.0 or later; 2.x breaks the shortcut recorder on macOS 26+). Do not add others.
- Compile check: `swift build -c release --arch arm64` (no signing needed). Must stay at zero errors and zero
  warnings in our sources.
- Full app: `./Scripts/build.sh` assembles `Minutes.app` (Info.plist, entitlements), signs it with the
  `Minutes Self-Signed` identity and installs it in `/Applications`. It refuses to build without the identity.
- Under the hardened runtime a usage string is not enough: every protected resource also needs its entitlement in
  `build.sh` (`audio-input`, `personal-information.calendars`). Adding one without the other fails silently.
- App icon: `Resources/AppIcon.icns`, rendered by `swift Scripts/make-icon.swift` (waveform on a dark tile) and
  copied into the bundle by `build.sh`. Edit the script, never the `.icns` by hand.
- UserNotifications only works inside the `.app` bundle; a bare `swift build` binary skips notifications.
- `build.sh` sets `NSUserNotificationAlertStyle = alert` (persistent alerts). macOS uses it only as the default on the
  first registration; the user's choice in System Settings › Notifications wins. The display time of banners cannot
  be configured by an app.

## Source layout (`Sources/Minutes/`)

| Folder | Contents |
|---|---|
| `App/` | `MinutesApp` (`@main`, scenes, `AppDelegate` for Quit and notification clicks), `AppEnvironment` (composition root and cross-window state), `MeetingNotifications` |
| `Capture/` | `SystemAudioTap` (Core Audio process tap + private aggregate device), `MicRecorder` (AVAudioEngine), `WavWriter`, `ChunkRecorder` (per-source chunks, levels, clock alignment) |
| `Pipeline/` | `RecordingSession` (actor, one meeting), `VadChunker`, `TranscriptionEngine` + `ParakeetEngine` + `OpenAICompatibleSTT`, `Diarizer`, `TranscriptAssembler`, `MeetingProcessor` (transcribe → finish → save; shared by stop, retry and recovery) |
| `Summaries/` | `ChatClient` (the only HTTP chat client), `SummaryService`, `SummaryTypeStore`, `TagService` |
| `Calendar/` | `CalendarService` (access, followed calendars, event lookup, start suggestions), `EventInfo` |
| `Integrations/` | `AgentIntegrations` (agent table, detection, skill template, install/update/remove), `NotesDictionary` (`.minutes/dictionary.md`) |
| `Notes/` | `Meeting` (model + sidecar), `NoteFile` (front matter, markers), `NoteWriter` (atomic writes), `NoteIndex` (scan, watch, search cache), `InProgressStore` |
| `Settings/` | `Preferences` (UserDefaults, `AppPaths`), `KeychainStore`, `Permissions` |
| `UI/` | `MenuView`, `MeetingsWindow` (single view, no tabs), `MeetingDetailView`, `SettingsView`, `CalendarSettings`, `IntegrationsSettings`, `AboutView` |

## Architecture rules

- **Threading:** audio callbacks only copy samples into serial queues owned by the capture objects and never touch
  the main actor. `RecordingSession` is an actor; one serial worker transcribes chunks in order. The main actor
  receives coarse events only (state, elapsed time once per second, levels at 10 Hz, processing step). Never add a
  global "sync everything" refresh: it is what made Muesli slow.
- **Sessions:** at most one recording; `AppEnvironment.status` describes only that recording. Stopped meetings move
  to `stopped` (stop order, name, processing step or `FinishResult`) and process in the background while a new
  recording runs. Session events are routed by session id (levels and elapsed only from the current recording).
  `RecordingSession.stopCapture()` must return before the next recording starts (one system audio tap at a time);
  `process()` runs the finish. Retry and discard of stopped meetings take an id; recovery skips every live session
  id. `isBusy` = recording or any stopped meeting still processing (updates, Quit).
- `@unchecked Sendable` is allowed only where state is confined to a named queue, with a comment saying which
  (currently `SystemAudioTap`, `SampleMixer`, `MicRecorder`, `Int16Converter`). Do not use `nonisolated(unsafe)`.
- **Storage:** the notes folder is the only durable store for finished meetings. No database. `NoteIndex` reads
  only the first 2 KB (front matter) of each note for the list and builds search text lazily, cached by
  modification date.
- **One provider client:** summaries, titles and tags all go through `ChatClient`
  (`POST <base>/chat/completions`, non-streaming). Do not add provider-specific code; Ollama uses its `/v1` endpoint.
- **Cross-window state** (selected meeting, Settings tab, re-tag progress) lives in `AppEnvironment`, because the
  menu, notifications and Settings all reach it. Screen-local state stays in that screen's `@Observable` model.
- **No in-app Q&A:** questions about meetings are answered by external AI agents through the skill. Do not add a
  chat, retrieval ranking or an MCP server back without an approved OpenSpec change.
- **Calendar access** is requested only by `CalendarService` when the user turns on "Use calendar events" in
  Settings › Calendar. `Permission.request()` never prompts for the calendar.
- **Colors:** semantic system colors and materials only, so light and dark mode need no extra code.
- Keep the app small (about 4,500 lines today). Prefer extending an existing type over adding a layer.

## Updates, Dock and releases

- `Updates/`: `UpdateClient` (GitHub `releases/latest` of `nanoarmando/minutes`, ephemeral session; 404 means no
  release yet), `UpdateRelease` (`AppVersion`, eligibility, tag `v<x.y.z>`, asset `Minutes-<x.y.z>.dmg`),
  `UpdateInstaller` (mount, verify against the running app's designated requirement and the version, stage in
  `~/Library/Caches/Minutes/updates`, swap script that restores `.Minutes-previous.app` on failure),
  `UpdateCoordinator` (owned by `AppEnvironment`; checks at launch, every 24 h and when About appears; in memory
  only; install refused while `isBusy`).
- The menu never lists meetings; it shows "Update available (<version>)" only when a newer release is known.
- Dock: the app is `LSUIElement`; `AppEnvironment` switches the activation policy to `.regular` while a Meetings,
  Settings or About window is visible and back to `.accessory` afterwards. Window matching relies on the SwiftUI
  window identifiers "meetings", "about" and "Settings".
- Version: the `VERSION` file is the single source (read by `build.sh`). `Scripts/build-dmg.sh <version>` runs
  `build.sh --no-install` and creates `.build/Minutes-<version>.dmg`.

## Data contracts

- **Note file:** YAML front matter keys `minutes_id`, `title`, `date`, `duration` (seconds), `speakers`, `tags`
  (block list), `summary_type`, `transcription`, `summary_model`, `recovered`, `audio` (only when audio is kept),
  and `calendar`, `attendees` (flow list), `meeting_link` (only when the recording matched an event; empty values
  omitted).
  Body: `# Title`, `## Summary` with the text between `<!-- minutes:summary:start -->` and
  `<!-- minutes:summary:end -->`, `## Transcript` with lines `**[HH:MM:SS] Speaker:** text`. Files without
  `minutes_id` are ignored.
- **Summary updates** replace only the text between the markers (falling back to the `## Summary` heading when the
  markers were removed). All writes go to a temporary file and are moved into place.
- **Sidecar:** `<notes folder>/.minutes/<id>.json` with segments (start, end, speaker), summary metadata,
  `manualTags` and `language` (`"en"`/`"es"`, absent for Auto). Kept audio: `.minutes/<id>.m4a`. A note must stay usable without its sidecar.
- **Application Support** (`~/Library/Application Support/Minutes/`): `summary-types.json` (user overrides and
  custom types; built-ins live in code and "Reset to default" deletes the override) and
  `InProgress/<id>/` (`session.json` with start time, settings snapshot and the calendar `EventInfo`,
  `segments.jsonl` appended per chunk, system-audio WAV, queued chunks).
  `InProgress/<id>/` is deleted after the note is saved or discarded; on launch any leftover is finished and saved
  with `recovered: true`.
- **Keychain:** service `com.minutes.app`, one generic-password item per endpoint kind.
- **Speakers:** microphone = `You`; remote = `Speaker N` numbered by first appearance in the transcript, or
  `Others` when separation is off or fails. Same-speaker lines less than 2 s apart are merged.
- **Tags:** there is no client list. Client domains are decided in Swift (`ClientDomains`): the user's address
  is the attendee matching the `userEmails` preference, else the `isCurrentUser` participant, else the calendar
  account email; its domain is the user's organization (unknown → all `userEmails` domains). Every other attendee
  domain that is not personal (fixed list) is a client, matched by its last two labels, ordered by attendee count,
  at most 2. `TagService` makes one model call with a header (title, client domains, user's organization) before
  the transcript; the model only names client domains (reusing existing tags) or, with no client domains, finds
  clients in the title and transcript. Swift drops the user's organization, keeps at most 2 clients and 3 topics,
  and falls back to domain-derived tags (`drgreenlife.com` → `client/drgreenlife`) when the model fails.
  Re-tagging replaces automatic tags and keeps the sidecar's `manualTags`.
- **Tagging reliability:** the sidecar's `tagging { pending, lastError }` is set to pending at save time; one path
  serves after-save, Re-tag and Re-tag all; success clears it, failure keeps it and stores the error (never
  swallowed). Pending notes are retried once at launch after the first index scan. The meeting detail shows
  "Tagging failed" with Re-tag when `lastError` is set. The sidecar also stores `event` (`EventInfo` with
  `attendeeEmails` and `ownDomain`) for later re-tags.
- **Meeting context:** `MeetingContext` builds one block (title, attendees with domains, user's organization, known
  client tags, glossary, the meeting's `instructions`, and a "the transcript can misspell names" note) that summary,
  title and tag requests put before the transcript. Client naming: title and attendee domains win over the
  transcript; a Swift guard replaces a model tag that shares no token with the domain label or title words with the
  domain-derived tag.
- **Reasoning:** `ChatClient.complete(…, reasoning:)`; on api.deepseek.com `thinking` is enabled with `reasoning_effort: "medium"`
  only for summaries (no `max_tokens`: `maxTokens: nil` omits it, 300 s); titles, tags and the connection test keep it
  disabled and keep their limits.
- **Corrections:** `Glossary` (`~/Library/Application Support/Minutes/glossary.json`, `[{from, to}]`) is applied
  whole-word and case-insensitively to new transcripts before the first write, and listed in the notes dictionary.
  `CorrectionService` asks the model for `{"replacements": [...]}` from the user's instructions and the transcript's
  candidate names (only `from` values present in the transcript are kept); `NoteWriter.applyCorrections` edits only
  the transcript section and sidecar segments. The sheet applies in one step (no preview). Instructions are stored
  in the sidecar `instructions`, are not displayed in the detail, pre-fill the sheet, and are sent on every
  regenerate and re-tag.
- **Language:** Minutes never detects the language (an on-device `NLLanguageRecognizer` guess read a Spanish
  transcript as Polish). `MeetingContext.language` is the sidecar `language` (`MeetingLanguage`, English or Spanish)
  or nil for Auto, where summaries, titles and topic tags ask the model for "the language most of the transcript is
  spoken in, even though these instructions are in English". The instruction is placed before and after the
  transcript (models drift to English otherwise). The detail's Language menu (Auto, English, Español) stores the
  choice first, then regenerates with the current type and, only if that succeeds, re-tags.
- **Title edits:** `NoteWriter.updateTitle` replaces the `title` front matter value and the first `# ` heading (never
  adds one), writes atomically, then renames the file with `fileNamePattern` (the note itself is not a collision;
  unchanged name skips the move). A failed move keeps the new title and shows the error. Sidecar and audio are keyed
  by id, so they are not renamed.
- **Call detection:** `Capture/CallDetector` polls Core Audio process objects every 2 s (only while
  `suggestOnCallDetected` is on): `kAudioHardwarePropertyProcessObjectList`, then each process's input-running flag,
  PID and bundle ID; Minutes' own PID and processes without a bundle ID are skipped; meeting apps are one constant
  bundle-ID list matched by case-insensitive prefix. `callStarted` after 10 s of continuous input (once per use),
  suggested whenever nothing records (background processing does not suppress it);
  `callEnded` during a recording after a meeting app used input and none has for 10 s (once per recording, re-armed
  explicitly on every new recording).
  `AppEnvironment` posts the "call-start" / "call-end" notifications; nothing starts or stops automatically.
  Calendar suggestions are not deduplicated against call suggestions. Safari captures in a WebKit process
  (`com.apple.WebKit.*`), which is not in the list.
- **Dock policy:** decided only by whether a Meetings, Settings or About window is open (visible or minimized),
  never by focus; only a closing window can demote to `.accessory`, and the policy is set only when it changes.
- **Calendar preferences:** `useCalendar` (off by default), `suggestRecording` (on by default) and
  `unfollowedCalendars` (calendar identifiers; storing the unfollowed set keeps new calendars followed). The event
  is the one in progress at start in a followed calendar, ignoring all-day events, with the most overlap.
  Suggestions fire one minute (`leadTime`) before the start of events with a meeting link or at least one attendee, once per occurrence (in
  memory), also while recording; every re-plan (launch, calendar or preference change, wake) first posts events whose
  suggestion moment passed and that started less than five minutes ago. The category is chosen at post time:
  "event-starting" ("Start recording") when idle, "event-starting-recording" ("Stop & record next") while recording.
  Both pass the notified `EventInfo`; "Stop & record next" stops capture of the current recording, then starts the
  next (only starts when nothing records; no-op when the current recording is that occurrence). The notification
  body does nothing.
- **Agent skill:** `<skills folder>/minutes/SKILL.md` for Claude Code `~/.claude/skills`, Codex `~/.agents/skills`,
  GitHub Copilot `~/.copilot/skills`, Gemini CLI `~/.gemini/skills`, OpenCode `~/.config/opencode/skills`; an agent
  is detected when its configuration folder exists. Ownership marker: `<!-- generated-by: minutes -->`. Never
  write or delete a `minutes` folder without it (shown as Conflict). Installed skills are re-rendered at launch and
  when the notes folder changes, only when the content differs. The skill is read-only by contract.
- **Notes dictionary:** `<notes folder>/.minutes/dictionary.md` (note format, client tags and topic
  tags with counts, summary types, catalog of every meeting newest first). Built from front matter only, written
  atomically 2 s after any `NoteIndex`, client or summary type change, and maintained even with no skill
  installed. `NoteIndex` ignores `.minutes`. When the note format changes, update the dictionary's format section
  and the skill template in the same change.

## FluidAudio 0.15.5 API (verified against the package source)

- **ASR:** `AsrModels.downloadAndLoad(version: .v3, progressHandler:)` (handler `@Sendable (DownloadProgress) -> Void`,
  `.fractionCompleted`); install check `AsrModels.modelsExist(at:version:)` with
  `AsrModels.defaultCacheDirectory(for: .v3)` (`~/Library/Application Support/FluidAudio/Models/<repo>`).
  `AsrManager` is an actor: `AsrManager()` → `loadModels(_:)` →
  `transcribe(_ samples: [Float], decoderState: inout TdtDecoderState, language: Language? = nil)` with a fresh
  `TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)` per chunk; `language: nil` auto-detects.
  Text is `ASRResult.text`.
- **VAD:** `VadManager` is an actor; `try await VadManager()` downloads Silero itself. `VadManager.chunkSize == 4096`
  samples at 16 kHz, default threshold 0.85. Streaming: `processStreamingChunk(_:state:)` → `VadStreamResult`
  (`state.triggered`, `event.isStart`/`isEnd`, `probability`), starting from `VadStreamState.initial()`.
- **Diarizer:** `DiarizerModels.downloadIfNeeded()`; `DiarizerManager` is a non-Sendable `final class`:
  `DiarizerManager()` → `initialize(models:)` → `performCompleteDiarization(samples, sampleRate: 16000)`
  (synchronous, throws). `segments` are `[TimedSpeakerSegment]` with `speakerId` and `Float` start/end seconds.
- Upgrading FluidAudio means re-verifying these names; adjust only the wrappers in `Pipeline/`.

## Conventions

- Files adapted from Muesli keep a header naming Muesli, the original file and the MIT license. Keep
  `THIRD_PARTY_NOTICES.md` in sync when adapting more code.
- No telemetry, analytics or crash reporting. The only network hosts are GitHub (update checks and release
  downloads), the model downloads
  (Hugging Face) and the endpoints the user configures.
- No credentials in code. API keys go only to the Keychain.
- No tests unless the user asks for them.
- Comments only where the reason is not obvious.

## Do not

- Add an Xcode project, a database, a global state object or a second HTTP client.
- Touch the main actor from audio callbacks.
- Send audio to the summary provider, or audio anywhere when the on-device engine is selected.
- Rewrite a whole note to update one part: summaries use the markers and tags use the front matter.
- Implement behavior that is not in an approved OpenSpec change.

## OpenSpec

- Changes live in `openspec/changes/`, and accepted specs in `openspec/specs/` once a change is archived.
- The app as built is described by the specs in `openspec/specs/` (archived change
  `openspec/changes/archive/2026-10-05-add-meeting-notetaker`). New work starts as a new change.
- Commands: `openspec list` and `openspec validate <change> --type change --strict`.

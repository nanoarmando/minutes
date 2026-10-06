# Minutes

Minutes is a small macOS menu bar app that records your meetings, transcribes them on your Mac and saves them as
plain Markdown notes you own. It captures your microphone and the audio of the call (Zoom, Meet, Teams, a browser
tab…) without a bot joining the meeting, separates the remote speakers, and writes a summary with the AI model you
choose.

- **On-device transcription** with Parakeet v3 (English, Spanish and the other languages it supports). Optional
  OpenAI-compatible transcription API.
- **Summaries** through any OpenAI-compatible chat endpoint: Ollama (fully local), DeepSeek, OpenAI or a custom one.
  Summary types: General, Client call, Standup, 1:1 and your own.
- **Plain files:** one Markdown note per meeting in a folder you pick (it works inside an Obsidian vault). No
  database, no account, no telemetry.
- **Tags** for clients and topics, detected automatically by the summary model. There is no client list to
  maintain.
- **Calendar:** the event in progress names the note and adds its attendees and call link; when a scheduled call
  starts, a notification offers to start recording.
- **AI agent integrations:** a read-only skill lets Claude Code, Codex, GitHub Copilot, Gemini CLI and OpenCode
  answer questions about your meetings.

## Requirements

- A Mac with Apple silicon running macOS 14.2 or later.
- Xcode (for the Swift 6 toolchain).
- Disk space for the on-device models (several hundred MB), downloaded on first use.

## Install

### Download

Download `Minutes-<version>.dmg` from the [latest release](https://github.com/nanoarmando/minutes/releases/latest),
drag Minutes to Applications, and clear the quarantine flag once (the app is self-signed, not notarized):

```sh
xattr -dr com.apple.quarantine /Applications/Minutes.app
```

Later versions install from About › Install update.

### Build from source


Minutes is built and signed on your own Mac. There is no notarized download.

#### Signing setup

Minutes is signed with a stable self-signed identity called `Minutes Self-Signed`. Using the same identity on
every build makes macOS remember the microphone, system audio and calendar permissions across rebuilds. Create it
once per Mac:

```sh
# Generate a self-signed code-signing certificate (10 years, code signing only).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/minutes-key.pem -out /tmp/minutes-cert.pem \
  -subj "/CN=Minutes Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/minutes-key.pem -in /tmp/minutes-cert.pem \
  -name "Minutes Self-Signed" -out /tmp/minutes.p12 -passout pass:minutes

# Import it into the login keychain so codesign can use it without prompting.
security import /tmp/minutes.p12 -k ~/Library/Keychains/login.keychain-db \
  -P minutes -A -T /usr/bin/codesign

rm -f /tmp/minutes-key.pem /tmp/minutes-cert.pem /tmp/minutes.p12
```

If `security import` rejects the `.p12` with a MAC verification error, add `-legacy` to the `openssl pkcs12` line
and run it again. Check that the identity exists:

```sh
security find-identity -p codesigning | grep "Minutes Self-Signed"
```

If the identity is lost and created again, macOS treats the next build as a new app: grant the permissions once
more.

#### Build

```sh
./Scripts/build.sh
```

The script builds a release `Minutes.app`, signs it with hardened runtime and installs it in `/Applications`. It
stops before building when the signing identity is missing.

## Usage

1. Open Minutes. A menu bar icon appears. The Dock icon shows only while a Minutes window (Meetings, Settings or
   About) is open, so you can switch back to it.
2. Choose **Start recording**, press **⌘⇧R**, or click **Start recording** on the notification Minutes shows when a
   scheduled call starts. The first time, macOS asks for the microphone and system audio permissions.
3. During the meeting the menu shows the elapsed time and a level for each source.
4. Choose **Stop & summarize** (or press the shortcut again). Minutes finishes the transcript, separates speakers,
   writes the title and summary, saves the note and shows a notification. **Discard** deletes everything instead.
   Processing runs in the background: you can start the next recording right away, and the menu shows one row per
   meeting still being processed (with **Retry** and **Discard** if it failed). Quitting while a meeting is still
   processing asks **Wait** or **Quit anyway**; with **Quit anyway** the meeting is finished the next time Minutes opens.
5. Open **All meetings…** to browse, search, read, re-summarize with another summary type and edit tags.
6. To ask questions about your meetings, install the Minutes skill in your AI agent (Settings › Integrations) and
   ask the agent, for example "what did we agree with Hemisphere about the delivery date?".

Use headphones when you can: with laptop speakers the microphone picks up the call, and the echo filter only
removes lines that repeat the remote speech closely.

### Settings

- **General:** launch at login, recording shortcut, notes folder (default `~/Documents/Minutes`), file name
  pattern, keep audio, permission status.
- **Calendar:** "Use calendar events" (off until you turn it on; this is the only place Minutes asks for calendar
  access), "Suggest recording when a meeting starts" (on by default) and the calendars to follow (all by default,
  including calendars added later).
- **Transcription:** on this Mac (Parakeet v3) or an OpenAI-compatible API; model status; speaker separation.
- **Summaries:** provider preset (Ollama, DeepSeek, OpenAI, Custom), base URL, API key, model, test connection,
  summarize automatically, default summary type, the summary type editor, and the **glossary** of name corrections
  ("Doctor Grim" → "DrGreenlife") applied to every new transcript. Tagging uses this provider too. With DeepSeek,
  summaries use its reasoning mode at medium effort (better summaries, a bit slower) with no output limit; titles and tags do not.
- **Tags:** detect clients automatically, add up to three topic tags automatically, **Your email addresses**, and
  re-tag all meetings. Enter the addresses you join meetings with (for example your work addresses for each
  company you work for). In each meeting, the address you joined with tells Minutes which organization you
  represent; every other business email domain among the attendees becomes a client (`drgreenlife.com` →
  `client/drgreenlife`, up to two per meeting). Personal domains such as Gmail never do. Without a calendar event,
  the model finds clients in the title and the conversation. Existing client tags are reused, and tags you add by
  hand are kept when re-tagging. If tagging fails or Minutes quits before it finishes, it is retried the next time
  Minutes opens, and the meeting shows the error with a Re-tag button.
- **Integrations:** install, update or remove the Minutes skill for each detected AI agent.

### Calendar

With calendar events on, the event of a followed calendar that is in progress when you start recording (all-day
events are ignored) gives the note its title, and the note stores the calendar name, the attendees and the call
link. One minute before an event with a call link or attendees starts, Minutes shows a notification
("… starts in 1 minute") with **Start recording** and **Dismiss**; if it learns about the event later (the event was
added late, Minutes was opened or the Mac woke up), it notifies right away, up to five minutes after the start. It never records on its own.
If you are still recording another meeting, the notification offers **Stop & record next** instead: it stops and
saves the current meeting (processed in the background) and starts recording the next one at once.
Minutes asks macOS for the persistent notification style, so suggestions stay on screen until you close them. macOS
applies it only on the first install; if Minutes notifications disappear after a few seconds, choose **Persistent**
(**Alerts** before macOS 15) in System Settings › Notifications › Minutes.

### AI agent integrations

Settings › Integrations detects Claude Code, Codex, GitHub Copilot, Gemini CLI and OpenCode (by their configuration
folders) and installs a `minutes` skill in each agent's user skills folder:

| Agent | Skill location |
|---|---|
| Claude Code | `~/.claude/skills/minutes/` |
| Codex | `~/.agents/skills/minutes/` |
| GitHub Copilot | `~/.copilot/skills/minutes/` |
| Gemini CLI | `~/.gemini/skills/minutes/` |
| OpenCode | `~/.config/opencode/skills/minutes/` |

The skill tells the agent where your notes are, that it may only read them, and to cite the meeting and file in its
answers. It points the agent to `.minutes/dictionary.md`, a file Minutes keeps up to date in the notes folder with
the note format, the client and topic tags in use, the summary types and a catalog of every meeting.
Minutes rewrites installed skills when you change the notes folder, and never touches a `minutes` skill it did not
create.

For a fully local setup, keep transcription on this Mac and use the Ollama preset (`http://localhost:11434/v1`).

### Unscheduled calls

When Zoom, Teams, Slack, Webex, FaceTime, Discord or a browser uses the microphone for 10 seconds and you are not
recording (an earlier meeting may still be processing), Minutes asks **Are you in a meeting?** with **Start recording**. While recording, when the call releases
the microphone for 10 seconds, it asks **Did the meeting end?** with **Stop & summarize**. Minutes never starts or
stops a recording by itself. Turn it off in Settings › General › "Suggest recording when a call is detected".

### Correcting a meeting

Automatic transcription can mishear names. Every summary, title and tag request includes what Minutes knows about
the meeting (title, attendees and their companies, your organization, known clients and the glossary) so the model
writes names correctly. When something is still wrong, open the meeting and choose **Correct with instructions…**,
then write what is wrong in your own words ("Doctor Grim is DrGreenlife; Pablo Veliz works at VNS") and choose
Apply. Minutes fixes those names in the transcript, adds them to the glossary so they do not happen again, keeps
your instructions with the meeting (they open pre-filled next time), and regenerates the summary and tags.

Summaries and topic tags are written in the language most of the meeting is spoken in, as judged by the model. If a summary comes out in the
wrong language, choose **Language** › English or Español next to Regenerate: Minutes keeps that choice for the
meeting and regenerates the summary and tags in it. **Auto** returns to detection.

To rename a meeting, click its title, type the new one and press Enter (Escape cancels). Minutes updates the title
in the note and renames the file with the file name pattern.

### Updates

When a new version is published, the menu shows **Update available**. About shows the release notes and an
**Install update** button: Minutes downloads the release, checks that it is signed with the same identity as the
installed app, replaces it and reopens. Your permissions are kept. Installing is disabled while a recording is in
progress.

## Notes format

Each meeting is one Markdown file named from the pattern (default `{date} {time} {title}`, for example
`2026-10-05 0930 Weekly sync.md`):

```markdown
---
minutes_id: 7F3C…
title: Weekly sync
date: 2026-10-05T09:30:00-04:00
duration: 2820
speakers: [You, Speaker 1, Speaker 2]
tags:
  - client/hemisphere-brands
  - budget
summary_type: general
transcription: parakeet-v3
summary_model: deepseek-flash
recovered: false
calendar: "Work"
attendees: [Ana Pérez, john@acme.com]
meeting_link: https://meet.google.com/abc-defg-hij
---
# Weekly sync

## Summary
<!-- minutes:summary:start -->
…
<!-- minutes:summary:end -->

## Transcript
**[00:00:42] Speaker 1:** …
```

You can edit the notes freely. Regenerating a summary only replaces the text between the summary markers. A hidden
`.minutes/` folder holds one JSON sidecar per meeting (transcript segments, summary metadata, manual tags, chosen summary language), the
audio when "Keep audio recording" is on, and `dictionary.md` for AI agents. The note stays complete without them.
The `calendar`, `attendees` and `meeting_link` keys appear only when the recording matched a calendar event.

## Privacy

- With the on-device engine, no audio leaves your Mac. With the API engine, each audio chunk is sent to the
  transcription provider you configure.
- Summaries and tags send transcript text (never audio) to the summary provider you configure. Ollama keeps it on
  your Mac.
- Calendar data is read only when you turn it on, and only from the calendars you follow.
- An AI agent with the Minutes skill reads your notes and may send their content to that agent's own AI provider.
  The skill only allows reading.
- API keys are stored in the macOS Keychain.
- The only other network requests are the one-time model downloads from Hugging Face. There is no analytics, crash
  reporting. Minutes checks GitHub for new releases at launch, once a day and when About opens; the request
  carries no data about you.
- Audio is deleted once the note is saved, unless you turn on "Keep audio recording".

## Releases (maintainers)

The version lives in the `VERSION` file. To publish a release:

```sh
./Scripts/build-dmg.sh 0.2.0          # must match VERSION; creates .build/Minutes-0.2.0.dmg
gh release create v0.2.0 .build/Minutes-0.2.0.dmg --notes "…"
```

Releases must be signed with the same `Minutes Self-Signed` identity, or installed copies refuse the update.

## Recovery

If Minutes quits unexpectedly while recording or processing, it saves a note from the transcript produced so far
on the next launch and marks it `recovered: true`. If the notes folder is unavailable when a meeting finishes, the
meeting is kept until you choose a writable folder.

## Uninstall

Remove the skills in Settings › Integrations, then delete `/Applications/Minutes.app`. Your notes stay in the notes folder. Settings data lives in
`~/Library/Application Support/Minutes` and the models in `~/Library/Application Support/FluidAudio`.

## Credits and license

Licensed under the [GNU Affero General Public License v3.0](LICENSE), © 2026 Jose Bianco. You may fork and modify
Minutes; versions you distribute must stay open under the same license. Parts of the meeting pipeline are adapted from [Muesli](https://github.com/Muesli-HQ/muesli) (MIT).
Transcription, voice activity detection and speaker separation use [FluidAudio](https://github.com/FluidInference/FluidAudio)
(Apache-2.0) with NVIDIA's Parakeet v3 model. The global shortcut uses
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT, 3.1.0 or later: older versions break the shortcut recorder on macOS 26 and later). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Roadmap

Not built yet: live transcript view, notes during the meeting, call detection from microphone activity, neural
echo cancellation, and summaries of transcripts longer than the model's context.

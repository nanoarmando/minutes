# transcription Specification

## Purpose
Defines how Minutes turns recorded audio into a speaker-labelled transcript, either on the Mac or through a
user-configured OpenAI-compatible transcription API.
## Requirements
### Requirement: On-device transcription by default
Minutes SHALL transcribe on the Mac with the Parakeet v3 model unless the user selects the API engine. In this
mode no audio SHALL leave the Mac. The language SHALL be detected automatically among the languages Parakeet v3
supports, including English and Spanish.

#### Scenario: Spanish meeting
- **WHEN** the user records a meeting held in Spanish with the on-device engine
- **THEN** the transcript is in Spanish and no network request carries audio

#### Scenario: Mixed languages
- **WHEN** participants switch between English and Spanish during the meeting
- **THEN** each part is transcribed in the language spoken

### Requirement: Model download
The on-device model SHALL be downloaded on first need, with visible progress in Settings and in the menu. A
missing model SHALL NOT block a recording: audio recorded before the download finishes SHALL be transcribed once
it completes. Settings SHALL allow deleting the model.

#### Scenario: First recording without the model
- **WHEN** the user starts the first recording before the model is downloaded
- **THEN** recording starts immediately, the download runs, and the full meeting is transcribed after it finishes

#### Scenario: Download fails
- **WHEN** the model download fails
- **THEN** Minutes shows the error with a retry action, and keeps the recorded audio until transcription succeeds or the user discards the meeting

### Requirement: Transcription during the meeting
Minutes SHALL transcribe the recording in short chunks while the meeting is in progress, cutting at natural
pauses, so that the transcript is ready within one minute after stopping a one-hour meeting on the user's Mac.
Chunks without speech SHALL be skipped and SHALL NOT produce text.

#### Scenario: Long silence
- **WHEN** nobody speaks for five minutes during a recording
- **THEN** the transcript contains no invented text for that period

### Requirement: Optional API transcription
When the user selects "OpenAI-compatible API" as the engine, Minutes SHALL send each audio chunk to the
configured base URL, API key and model using the OpenAI audio transcription contract, and SHALL state in Settings
that meeting audio is sent to that provider. If a chunk request fails after retries, Minutes SHALL transcribe that
chunk on the Mac when the on-device model is installed; otherwise the note SHALL mark the missing time range.

#### Scenario: Provider unavailable
- **WHEN** the API returns errors for a chunk and the on-device model is installed
- **THEN** that chunk is transcribed on the Mac and the transcript has no gap

#### Scenario: Test connection
- **WHEN** the user clicks "Test connection" in the transcription settings
- **THEN** Minutes reports success or the provider's error message

### Requirement: Speaker labels
Every transcript line SHALL carry a speaker and a timestamp relative to the start of the meeting. Microphone
speech SHALL be labelled "You". When speaker separation is on, other participants SHALL be labelled "Speaker 1",
"Speaker 2"… in order of first appearance; when it is off or fails, they SHALL be labelled "Others". Consecutive
lines from the same speaker less than two seconds apart SHALL be merged.

#### Scenario: Three remote participants
- **WHEN** a call has the user and three remote participants and speaker separation is on
- **THEN** the transcript labels lines as You, Speaker 1, Speaker 2 and Speaker 3

#### Scenario: Separation fails
- **WHEN** speaker separation cannot run
- **THEN** the note is saved with remote lines labelled "Others" and no error blocks the note

### Requirement: Echo filter
When the user listens through speakers, Minutes SHALL drop microphone lines that repeat remote speech captured at
the same time, so remote speech is not attributed to "You".

#### Scenario: Meeting on laptop speakers
- **WHEN** a remote participant speaks and the microphone picks up the same words from the speakers
- **THEN** the transcript shows those words once, attributed to the remote participant


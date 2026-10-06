## Purpose

Defines how Minutes is built, signed and licensed on the user's Mac, and the guarantees about network and
telemetry that the public source must keep.

## ADDED Requirements

### Requirement: Local signed build
The repository SHALL provide one command that builds a release "Minutes.app" for Apple silicon, minimum macOS
14.2, signed with the local self-signed identity "Minutes Self-Signed", and installs it in /Applications. The
command SHALL stop with a clear message pointing to the setup instructions when the identity is missing.

#### Scenario: Rebuild keeps permissions
- **WHEN** the user installs a rebuilt app signed with the same identity
- **THEN** the microphone and system audio permissions granted to the previous build still apply

#### Scenario: Identity missing
- **WHEN** the build command runs on a Mac without "Minutes Self-Signed"
- **THEN** it stops before building and points to the signing setup instructions

### Requirement: Licensing and credits
The repository SHALL be licensed under the GNU Affero General Public License v3.0 and SHALL include a third-party
notices file with the licenses of FluidAudio, Muesli and KeyboardShortcuts. Every source file adapted from Muesli
SHALL keep a header naming its origin and license.

#### Scenario: Adapted capture code
- **WHEN** a reader opens a source file adapted from Muesli
- **THEN** its header names Muesli, the original file and the MIT license

### Requirement: No telemetry
Minutes SHALL NOT include analytics, crash reporting or telemetry. Its only network requests SHALL be the model
downloads, the transcription and summary endpoints the user configures, and the update checks and downloads from
the project's GitHub releases.

#### Scenario: Default configuration
- **WHEN** Minutes runs with the on-device engine and Ollama for summaries
- **THEN** it makes no request to any host other than the model download host, GitHub (update checks) and localhost

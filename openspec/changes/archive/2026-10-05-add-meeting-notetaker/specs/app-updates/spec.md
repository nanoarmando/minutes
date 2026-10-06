## Purpose

Defines how Minutes finds, offers and installs new versions published as GitHub releases of the public repository,
without breaking the installed app or the macOS permissions granted to it.

## ADDED Requirements

### Requirement: Check for updates
Minutes SHALL check the latest release of `github.com/nanoarmando/minutes` at launch, once every 24 hours while
running, and each time the About window opens. A release SHALL count as newer when its version
(`major.minor.patch`) is greater than the running version. Checks SHALL send no data about the user or the Mac
beyond the request itself.

#### Scenario: Newer release published
- **WHEN** the running version is 0.1.0 and the latest release is 0.2.0
- **THEN** Minutes reports that version 0.2.0 is available

#### Scenario: Up to date
- **WHEN** the latest release is the running version
- **THEN** About shows "Minutes is up to date" and the menu shows no update row

#### Scenario: Offline
- **WHEN** GitHub cannot be reached during a check
- **THEN** About shows the error with a Retry button, and the menu shows no update row

### Requirement: Update available in the menu
When a newer release is known, the idle menu SHALL show an "Update available (<version>)" row that opens the About
window.

#### Scenario: Update row
- **WHEN** version 0.2.0 is available and the user opens the menu with no recording in progress
- **THEN** the menu shows "Update available (0.2.0)", and choosing it opens About

### Requirement: Install an update
About SHALL show, for a newer release, its version, its release notes and an "Install update" button. Installing
SHALL download the release's DMG, verify that the app inside is signed with the same identity as the running app and
has the release's version, quit Minutes, replace the installed app, and open the new version. When verification
fails, nothing SHALL be replaced and the reason SHALL be shown. A failed replacement SHALL restore the previous app.
Installing SHALL NOT be offered while a recording is in progress or being processed.

#### Scenario: Install
- **WHEN** the user clicks "Install update" for 0.2.0
- **THEN** Minutes downloads it, verifies it, quits, and reopens as 0.2.0 with its permissions still granted

#### Scenario: Different signing identity
- **WHEN** the release's app is signed with a different identity
- **THEN** Minutes refuses to install it, explains why, and keeps the current version

#### Scenario: Recording in progress
- **WHEN** an update is available while a recording is in progress
- **THEN** the Install button is disabled with the reason "Finish the recording first"

### Requirement: Install eligibility
Minutes SHALL NOT offer to install when it runs from a disk image, from an App Translocation path, or from a folder
it cannot write to; About SHALL show the reason and a link to the release page instead.

#### Scenario: Running from the DMG
- **WHEN** Minutes runs from a mounted disk image
- **THEN** About says to move Minutes to the Applications folder first and offers the release page link

### Requirement: Release packaging
The repository SHALL provide a command that builds the signed app and packages it as `Minutes-<version>.dmg`
containing `Minutes.app` and an Applications link, ready to attach to a GitHub release tagged `v<version>`.

#### Scenario: Package a release
- **WHEN** the maintainer runs the release packaging command for version 0.2.0
- **THEN** `Minutes-0.2.0.dmg` is produced with the signed app and an Applications link

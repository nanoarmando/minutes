## MODIFIED Requirements

### Requirement: Release packaging
The repository SHALL provide a command that builds the signed app and packages it as `Minutes-<version>.dmg`
containing `Minutes.app` and an Applications link, ready to attach to a GitHub release tagged `v<version>`. The
command SHALL verify the produced image with the same disk image tooling installed copies use to open updates, and
when verification fails it SHALL delete the image, explain the failure and exit with an error, so a corrupt image is
never produced.

#### Scenario: Package a release
- **WHEN** the maintainer runs the release packaging command for version 0.2.0
- **THEN** `Minutes-0.2.0.dmg` is produced with the signed app and an Applications link, and it passes verification

#### Scenario: Corrupt image
- **WHEN** the disk image tool produces an image that fails verification
- **THEN** the command deletes it, reports that the image failed verification and exits with an error

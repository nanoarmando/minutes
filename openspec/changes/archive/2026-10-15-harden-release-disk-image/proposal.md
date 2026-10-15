## Why

On macOS 27, `hdiutil create` with UDZO compression at the default zlib level can produce, for some exact app contents, a disk image that `hdiutil` itself rejects as corrupt (`hdiutil verify`/`attach`: "corrupt image"). Adding one byte or changing the compression level avoids it, so it is a data-dependent bug in a deprecated tool. A sibling app shipped a corrupt release this way and its in-app update failed. Minutes builds its release DMG with the same command and installed copies mount updates with `hdiutil attach`, so any future Minutes release can break updates without warning.

## What Changes

- The release packaging command creates the DMG with `diskutil image create` (UDZO) when available, falling back to `hdiutil create` on systems without it.
- The packaging command verifies the image with `hdiutil verify` and refuses to finish (deleting the image) when verification fails, so a corrupt image is never published.
- The updater mounts the downloaded DMG with `diskutil image attach` when available, falling back to `hdiutil attach`, and ejects it with `diskutil eject`, so updates keep working as `hdiutil` deprecation progresses.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `app-updates`: the "Release packaging" requirement adds that the produced image must pass verification or the command fails without producing it.

## Impact

- `Scripts/build-dmg.sh` (already drafted in the working tree: `diskutil image create` plus verification) and `AGENTS.md`.
- `Sources/Minutes/Updates/UpdateInstaller.swift` (attach and detach).
- README release steps if they mention the packaging behavior.
- No data, settings or permission changes; existing installs keep updating because released images stay valid for `hdiutil attach`.

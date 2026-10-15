## Context

See proposal.md. Packaging lives in `Scripts/build-dmg.sh` (bash); installing an update lives in `Sources/Minutes/Updates/UpdateInstaller.swift`, which mounts the DMG with `hdiutil attach -nobrowse -readonly -noautoopen -mountrandom <dir> -plist` and parses `system-entities` › `mount-point` from the plist, then detaches with `hdiutil detach -force`.

## Goals / Non-Goals

**Goals:** never publish an image installed copies cannot open; keep updates working as `hdiutil` deprecation progresses; no behavior change for users.

**Non-Goals:** switching releases to ZIP, notarization, changing the release asset name or format (UDZO DMG stays).

## Decisions

### D1. Create with `diskutil image create`, fall back to `hdiutil create`
`diskutil image create from --format UDZO --volumeName "Minutes <version>" <staging> <dmg>` when `diskutil image create from --help` succeeds; otherwise the current `hdiutil create` command. Tested on macOS 27: `diskutil`'s UDZO output verifies where `hdiutil`'s does not.

### D2. Verify before finishing
`hdiutil verify <dmg>` after creation; on failure delete the image, print "The disk image failed verification; run the script again." to stderr and exit 1. `hdiutil verify` is used because installed copies (current and older) open updates with `hdiutil attach`.

### D3. Updater mounts with `diskutil image attach`, falls back to `hdiutil attach`
`diskutil image attach --plist --readOnly --nobrowse <dmg>` returns the same `system-entities`/`mount-point` plist, so parsing is unchanged. If it fails (for example `diskutil image` missing on macOS 14.2), run the current `hdiutil attach` command. Eject with `diskutil eject <mount point>`, available on every supported macOS.

## Risks / Trade-offs

- [`diskutil image` absent on older macOS] → fallbacks in both packaging and updater.
- [`diskutil image attach` mounts under /Volumes instead of a random private folder] → the image is read-only and ejected right after copying, as today.

## Migration Plan

None: next release uses the new packaging; installed copies keep using their current updater until they update.

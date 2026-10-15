## 1. Packaging

- [x] 1.1 Create the DMG with `diskutil image create` (UDZO) when available, falling back to `hdiutil create` (D1; app-updates)
- [x] 1.2 Verify the image with `hdiutil verify`, deleting it and exiting with an error on failure (D2; app-updates)

## 2. Updater

- [x] 2.1 Mount updates with `diskutil image attach`, falling back to `hdiutil attach`, and eject with `diskutil eject` (D3)

## 3. Docs and verification

- [x] 3.1 Update AGENTS.md and README release steps
- [x] 3.2 Run the packaging command for the current version and confirm the image passes `hdiutil verify` and mounts with both `diskutil image attach` and `hdiutil attach`

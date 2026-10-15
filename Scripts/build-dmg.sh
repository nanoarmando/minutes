#!/usr/bin/env bash
# Packages a release: builds and signs Minutes.app with build.sh (without installing) and creates
# Minutes-<version>.dmg with the app and an Applications link, ready for `gh release create v<version>`.
# Usage: Scripts/build-dmg.sh <version>   (must match the VERSION file)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ $# -ne 1 || "$1" != "$VERSION" ]]; then
  echo "usage: Scripts/build-dmg.sh <version>; the version must match the VERSION file ($VERSION)." >&2
  exit 1
fi

"$ROOT/Scripts/build.sh" --no-install

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$ROOT/.build/Minutes.app" "$STAGING/Minutes.app"
ln -s /Applications "$STAGING/Applications"

DMG="$ROOT/.build/Minutes-$VERSION.dmg"
rm -f "$DMG"
# hdiutil create is deprecated and on newer macOS its UDZO compression can produce, depending on the content,
# images hdiutil itself rejects as corrupt; prefer diskutil image when available
if diskutil image create from --help > /dev/null 2>&1; then
  diskutil image create from --format UDZO --volumeName "Minutes $VERSION" "$STAGING" "$DMG" > /dev/null
else
  hdiutil create -volname "Minutes $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
fi
# Installed copies mount updates with hdiutil attach: never ship an image it cannot open
if ! hdiutil verify "$DMG" > /dev/null 2>&1; then
  rm -f "$DMG"
  echo "The disk image failed verification; run the script again." >&2
  exit 1
fi
echo "Created $DMG"

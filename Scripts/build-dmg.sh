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
hdiutil create -volname "Minutes $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
echo "Created $DMG"

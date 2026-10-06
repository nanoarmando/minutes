#!/usr/bin/env bash
# Builds a release Minutes.app for Apple silicon, signs it with the local "Minutes Self-Signed" identity
# (hardened runtime) and installs it in /Applications. See "Signing setup" in README.md.
# Usage: Scripts/build.sh [--no-install]   (--no-install stops after signing; used by build-dmg.sh)
set -euo pipefail

INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

IDENTITY="Minutes Self-Signed"
BUNDLE_ID="com.minutes.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/.build/Minutes.app"
ENTITLEMENTS="$ROOT/.build/Minutes.entitlements"
INSTALL_PATH="/Applications/Minutes.app"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "error: the code-signing identity \"$IDENTITY\" was not found in your keychain." >&2
  echo "Create it once by following the \"Signing setup\" section of README.md, then run this script again." >&2
  exit 1
fi

cd "$ROOT"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/Minutes" "$APP/Contents/MacOS/Minutes"
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -e "$bundle" ]] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Minutes</string>
  <key>CFBundleDisplayName</key><string>Minutes</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Minutes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Minutes records your voice during the meetings you choose to record.</string>
  <key>NSAudioCaptureUsageDescription</key><string>Minutes records the other participants of the meetings you choose to record from the audio played by your Mac.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Minutes uses the calendar event in progress when you start recording for the meeting title, attendees and call link, and suggests recording when a scheduled call starts.</string>
</dict>
</plist>
PLIST

# Calendar access needs its own entitlement under the hardened runtime.
cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.personal-information.calendars</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built and signed $APP ($VERSION)"
[[ "$INSTALL" == 1 ]] || exit 0

if pgrep -xq Minutes; then
  osascript -e 'tell application "Minutes" to quit' || true
  sleep 1
fi
rm -rf "$INSTALL_PATH"
ditto "$APP" "$INSTALL_PATH"
echo "Installed $INSTALL_PATH"

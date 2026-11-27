#!/usr/bin/env bash
# Creates unsigned/ad-hoc local distribution artifacts. It never signs with a
# Developer ID, never notarizes and never publishes.
# Usage: scripts/package-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build.sh" Release

APP="$ROOT/build/DerivedData/Build/Products/Release/BlueLink.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DIST="$ROOT/dist"
mkdir -p "$DIST"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/bluelink-dmg.XXXXXX")"
cp -R "$APP" "$STAGE/BlueLink.app"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/BlueLink-$VERSION-$BUILD.dmg"
ZIP="$DIST/BlueLink-$VERSION-$BUILD.zip"

rm -f "$DMG" "$ZIP" "$DMG.sha256" "$ZIP.sha256"
hdiutil create \
  -volname "BlueLink" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

ditto -c -k --keepParent "$APP" "$ZIP"

shasum -a 256 "$DMG" > "$DMG.sha256"
shasum -a 256 "$ZIP" > "$ZIP.sha256"

echo "Created:"
echo "  $DMG"
echo "  $ZIP"
echo "  $DMG.sha256"
echo "  $ZIP.sha256"
echo "Note: ad-hoc/local build only. Not Developer ID signed or notarized."

#!/usr/bin/env bash
# Creates unsigned/ad-hoc local distribution artifacts. It never signs with a
# Developer ID, never notarizes and never publishes.
# Usage: scripts/package-dmg.sh [--no-build]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "--no-build" ]]; then
  shift
else
  "$ROOT/scripts/build.sh" Release
fi

APP="$ROOT/build/DerivedData/Build/Products/Release/BlueLink.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DIST="$ROOT/dist"
mkdir -p "$DIST"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/bluelink-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Copy without source/File Provider metadata, then re-sign the clean bundle.
# This keeps the ad-hoc distribution signature valid even when the checkout
# lives on a File Provider-backed volume.
ditto --norsrc --noextattr "$APP" "$STAGE/BlueLink.app"
xattr -cr "$STAGE/BlueLink.app"
codesign --force --deep --sign - --timestamp=none "$STAGE/BlueLink.app"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/BlueLink-$VERSION-$BUILD.dmg"
ZIP="$DIST/BlueLink-$VERSION-$BUILD.zip"

rm -f "$DMG" "$ZIP" "$DMG.sha256" "$ZIP.sha256"
hdiutil create \
  -volname "BlueLink" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

ditto -c -k --keepParent "$STAGE/BlueLink.app" "$ZIP"

(
  cd "$DIST"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
  shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256"
)

echo "Created:"
echo "  $DMG"
echo "  $ZIP"
echo "  $DMG.sha256"
echo "  $ZIP.sha256"
echo "Note: ad-hoc/local build only. Not Developer ID signed or notarized."

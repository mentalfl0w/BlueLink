#!/usr/bin/env bash
# Builds the app without publishing or notarizing it.
# Usage: scripts/build.sh [Debug|Release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
cd "$ROOT"

"$ROOT/scripts/generate-project.sh"

BUILD_SETTINGS=()
if [[ -n "${BLUELINK_VERSION:-}" ]]; then
  BUILD_SETTINGS+=("MARKETING_VERSION=$BLUELINK_VERSION")
fi
if [[ -n "${BLUELINK_BUILD_NUMBER:-}" ]]; then
  BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$BLUELINK_BUILD_NUMBER")
fi

if [[ ${#BUILD_SETTINGS[@]} -gt 0 ]]; then
  xcodebuild \
    -project BlueLink.xcodeproj \
    -scheme BlueLink \
    -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData \
    -destination 'platform=macOS' \
    "${BUILD_SETTINGS[@]}" \
    build
else
  xcodebuild \
    -project BlueLink.xcodeproj \
    -scheme BlueLink \
    -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData \
    -destination 'platform=macOS' \
    build
fi

echo "Built $(find build/DerivedData/Build/Products/"$CONFIGURATION" -maxdepth 1 -name BlueLink.app -print -quit)"

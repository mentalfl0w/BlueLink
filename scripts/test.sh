#!/usr/bin/env bash
# Full local gate: package tests, hosted app tests, boundary and docs checks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/generate-project.sh"

swift test --package-path Packages/BlueLinkCore
swift test --package-path Platform/MacIntegration

xcodebuild \
  -project BlueLink.xcodeproj \
  -scheme BlueLink \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test

"$ROOT/scripts/boundary-check.sh"
"$ROOT/scripts/check-docs.sh"

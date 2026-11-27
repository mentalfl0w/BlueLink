#!/usr/bin/env bash
# Regenerates BlueLink.xcodeproj from the single XcodeGen spec.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

xcodegen generate -s Apps/MacApp/project.yml -r . -p .
xcodegen_version="$(xcodegen version 2>/dev/null || true)"
echo "Generated BlueLink.xcodeproj with ${xcodegen_version:-xcodegen}"

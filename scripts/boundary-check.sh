#!/usr/bin/env bash
# Enforces the import, API and privacy boundaries from AGENTS.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failed=0

report() {
  echo "boundary violation: $1" >&2
  shift
  printf '  %s\n' "$@" >&2
  failed=1
}

check_absent() {
  local description="$1"
  local pattern="$2"
  shift 2
  local hits
  hits="$(grep -RInE --exclude-dir=.git --exclude-dir=build --exclude-dir=dist \
    --exclude-dir=DerivedData "$pattern" "$@" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    report "$description" "$hits"
  fi
}

# BlueLinkCore stays Foundation-only.
check_absent \
  "BlueLinkCore must not import UI, Bluetooth or audio frameworks" \
  '^import (AppKit|SwiftUI|IOBluetooth|CoreAudio|CoreGraphics|ServiceManagement)' \
  Packages/BlueLinkCore/Sources

# No private APIs, selector poking or external automation in product code.
check_absent \
  "private or automation API found" \
  'NSClassFromString|perform\(Selector|dlopen|AXUIElement|CGEventCreate|/usr/bin/blueutil|Hammerspoon|osascript' \
  Apps Packages Platform

check_absent \
  "private Bluetooth framework reference found" \
  'IOBluetoothPrivate|BluetoothPrivate|PrivateFramework' \
  Apps Packages Platform

check_absent \
  "unchecked Sendable is not allowed as a concurrency escape hatch" \
  'unchecked Sendable' \
  Apps Packages Platform

# Real Bluetooth addresses must never be committed. The fixtures below are
# synthetic values used by tests and documentation examples.
address_hits="$(grep -RInE --exclude-dir=.git --exclude-dir=build --exclude-dir=dist \
  --exclude-dir=DerivedData --exclude='*.png' --exclude='*.icns' \
  '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' . 2>/dev/null \
  | grep -vE 'AA-BB-CC-DD-EE-FF|11-22-33-44-55-66|aa:bb:cc:dd:ee:ff|11:22:33:44:55:66' || true)"
if [[ -n "$address_hits" ]]; then
  report "possible real Bluetooth address found" "$address_hits"
fi

# Deployment floor and package platform must stay aligned.
if ! grep -q 'macOS: "26.0"' Apps/MacApp/project.yml; then
  report "app deployment target is not macOS 26.0" "Apps/MacApp/project.yml"
fi
for package in Packages/BlueLinkCore/Package.swift Platform/MacIntegration/Package.swift; do
  if ! grep -q '\.macOS("26.0")' "$package"; then
    report "package deployment target is not macOS 26.0" "$package"
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Boundary checks passed."

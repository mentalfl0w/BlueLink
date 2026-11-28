# Contributing to BlueLink

BlueLink is a focused macOS menu-bar app. Keep changes within the product boundary, preserve the event-driven connection policy, and state exactly what you verified. Small, evidence-backed changes are easier to review than broad rewrites.

[简体中文](CONTRIBUTING.zh-CN.md) · [Project overview](README.md) · [Documentation](docs/README.md)

## Environment

- macOS 26 or later. The current environment is macOS 27.3, Xcode 27.2, Swift 6.4.2, Apple M4.
- XcodeGen 2.46: `brew install xcodegen`.
- A Developer ID certificate is not required for local builds. Local artifacts use an ad-hoc signature.
- Runtime code must not depend on XcodeGen, Xcode, `blueutil`, Hammerspoon, or any external process.

## One project spec

`Apps/MacApp/project.yml` is the only project source. `BlueLink.xcodeproj` is generated; never edit `project.pbxproj` by hand.

```sh
./scripts/generate-project.sh
```

Regenerate and confirm `xcodebuild -list -project BlueLink.xcodeproj` after any project-setting change.

## Build and test

```sh
./scripts/build.sh                 # Debug
./scripts/build.sh Release         # Release
./scripts/test.sh                  # all package tests + app tests + boundary checks
./scripts/boundary-check.sh        # boundary checks only
./scripts/package-dmg.sh           # DMG/ZIP + SHA256; no signing, notarization, or publishing
```

You can also run the individual gates:

```sh
swift test --package-path Packages/BlueLinkCore
swift test --package-path Platform/MacIntegration
xcodebuild -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS' test
```

## Repository layout and boundaries

- `Packages/BlueLinkCore`: Foundation-only domain state, policy, coordinator, ports, and pure tests. It must not import AppKit, SwiftUI, IOBluetooth, CoreAudio, or other platform frameworks.
- `Platform/MacIntegration`: IOBluetooth, AppKit/NSWorkspace, CoreGraphics, CoreAudio, ServiceManagement, configuration, and diagnostics adapters. It depends on Core.
- `Apps/MacApp`: composition root, menu bar and Settings views, localization, and app-level tests. Views call `AppModel`; they never hold a Bluetooth handle.
- `scripts/`: project generation, build, test, boundary checks, packaging, and docs checks.
- `.github/workflows/ci.yml`: build and package on macOS; version tags and manual dispatch create unsigned GitHub Releases.
- `branding/`: icon layers and brand source assets. `docs/`: product and engineering guides, evidence, and screenshots.

`scripts/boundary-check.sh` blocks UI/Bluetooth imports in Core, private APIs, `unchecked Sendable`, real Bluetooth addresses, and deployment-target drift. Never commit a real Bluetooth address. Tests use synthetic values such as `AA-BB-CC-DD-EE-FF`.

## Testing strategy

- **Core:** inject fake transports and a virtual clock. Cover policy order, pause, manual overrides, late callbacks, retry exhaustion, configuration corruption, and unknown schema versions.
- **Platform:** mapping, notification lifecycles, sanitization, and configuration storage. Do not trigger real hardware side effects by default.
- **App:** presentation mapping, localization keys including interpolation, Info.plist copy, and real SwiftUI views rendered offscreen through AppKit. Offscreen rendering is test-only; never add a debug window or test entry point to the app.
- **Hardware:** `RealDeviceTests` requires explicit environment variables. The address comes from the environment and is never written to the repository. Record the connection state on entry and restore it on exit. Do not run it against an input device without authorization.

```sh
BLUELINK_REAL_DEVICE=1 \
BLUELINK_TEST_DEVICE_ID=AA-BB-CC-DD-EE-FF \
BLUELINK_TEST_DEVICE_NAME="Test Device" \
swift test --package-path Platform/MacIntegration --filter RealDeviceTests
```

## Localization and documentation

- UI strings live in `Apps/MacApp/Localization/Localizable.xcstrings` and `InfoPlist.xcstrings`. English is the source language; every key must also have a zh-Hans value.
- Use format specifiers for interpolation, for example `Reconnecting · attempt %lld`. `LocalizationTests` checks representative keys and formats.
- `Text(String)` does not localize automatically. Use `LocalizedStringKey`, `LocalizedStringResource`, or `String(localized:)` for visible copy.
- User data such as device names and addresses is never translated.
- Human-facing Markdown has an English primary file and a Simplified Chinese pair: `NAME.md` and `NAME.zh-CN.md`. Both files link to each other. This applies to the README, contributing guide, documentation index, every guide under `docs/`, and the icon guide. `AGENTS.md` is agent-facing and English-only.
- English screenshots use `-en` names; Chinese screenshots use `-zh`. Keep both sets aligned when the UI changes.
- Behavior changes update the canonical policy, tests, decisions, and changelog together. Record the command and observed result in `docs/CHANGELOG.md`.

## Screenshots

- Generate screenshots through `UISnapshotTests`; do not hand-edit UI images.
- The test renders real SwiftUI views with `NSHostingView` and writes English and Chinese variants to `/tmp/bluelink-shots`.
- Copy only the reviewed images into `docs/screenshots`. Label them as offscreen renders, not live window captures.
- Never inject mock devices, fake status, or a special screenshot mode into the app.

## Packaging, signing, and releases

- `scripts/package-dmg.sh` creates an ad-hoc local artifact for testing. It is not a Developer ID build, is not notarized, and must not claim Gatekeeper approval.
- `BlueLinkUpdateRepository` is `mentalfl0w/BlueLink`. Sparkle uses the stable feed `https://github.com/mentalfl0w/BlueLink/releases/latest/download/appcast.xml`; automatic checks and downloads are off until the user enables them in Settings. Builds without a valid Sparkle key fall back to the manual GitHub Releases checker.
- Pushing a stable version tag runs the release job after the build and boundary/docs checks. For stable releases, CI generates and validates `appcast.xml` from the ZIP and publishes the DMG, ZIP, SHA256 files, and appcast. The EdDSA private key must be in the `SPARKLE_EDDSA_PRIVATE_KEY_BASE64` repository secret; never commit it. Rotate the embedded public key and the release script's expected key together. Release notes are GitHub's generated notes from merged pull requests; land changes through PRs so they appear there. A manual `workflow_dispatch` does the same with an explicit version.
- Pre-release tags skip appcast generation so `releases/latest/download/appcast.xml` always points to a stable release.
- Do not use a Developer ID certificate, notarize, upload assets, create a release, push a tag, or operate a remote host without explicit user authorization.
- Release notes must distinguish signing/notarization state from the scope of real-hardware testing.

## Pull request checklist

- [ ] The change stays within the documented product and safety boundaries.
- [ ] `./scripts/test.sh` passes, including boundary and docs checks.
- [ ] New behavior has a test that would catch a plausible regression.
- [ ] No real Bluetooth address, credential, token, or signing identity is committed.
- [ ] English and Chinese docs are updated together when behavior or commands change.
- [ ] Screenshots are regenerated and labeled as offscreen renders when the UI changes.
- [ ] The final report states what passed, what was not tested, and the next safe step.

## Documentation and evidence

Behavior is defined by [Connection policy](docs/CONNECTION_POLICY.md); verification evidence lives in [Verification](docs/VERIFICATION.md). Every delivery records the date, change, actual commands, and results in [Changelog](docs/CHANGELOG.md). Write **Not tested** for scenarios that were not exercised. A successful build or offscreen render is not hardware evidence.

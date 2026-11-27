# Changelog / evidence

[简体中文](CHANGELOG.zh-CN.md) · [Documentation](README.md)

## 2026-11-27 — 1.0.0 delivery

### Delivered

- `Packages/BlueLinkCore`: device/state models, policy table, retry, configuration, ports, and `ConnectionEngine`.
- `Platform/MacIntegration`: IOBluetooth transport, Bluetooth/display/system event monitors, audio routing, login item, configuration store, sanitized diagnostics, and update check (off by default).
- `Apps/MacApp`: menu bar panel, device picker, Settings (General/Devices/Diagnostics/About), `AppModel` composition, English/Chinese UI, real Icon Composer icon, and menu bar template.
- New scripts: `generate-project.sh`, `build.sh`, `test.sh`, `boundary-check.sh`, `package-dmg.sh`, and `.github/workflows/ci.yml`.
- New `README.md`, `README.zh-CN.md`, `CONTRIBUTING.md`, `LICENSE`, and `docs/screenshots/`.

### Commands and results

| Command | Result |
|---|---|
| `swift test --package-path Packages/BlueLinkCore` | 44 passed |
| `swift test --package-path Platform/MacIntegration` | 24 ran, 23 passed, 1 hardware test skipped |
| `xcodebuild test -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS'` | 19 passed |
| `./scripts/test.sh` | All passed; boundary and docs checks passed |
| `BLUELINK_REAL_DEVICE=1 … --filter RealDeviceTests` | Passed in 5.976 s; connect on start, manual disconnect, and manual reconnect matched the system; entry state restored |
| `./scripts/package-dmg.sh` | `dist/BlueLink-1.0.0-1.dmg` 3.6 MB, `.zip` 3.2 MB, SHA256 generated |
| DMG mount check | Version 1.0.0 (1), deployment target 26.0, `LSUIElement=true`, ad-hoc signature; detached |

Environment: macOS 27.3 (26C5047e), Xcode 27.2 (27B52), macOS 27.2 SDK, Swift 6.4.2, XcodeGen 2.46.0, Mac mini M4 16 GB.

### Icon and localization

- `Apps/MacApp/AppIcon.icon` is compiled from a real Icon Composer document. The rear ribbon uses `opacity: 0.72`; `ictool` verified Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark.
- The legacy `AppIcon.appiconset` is renamed `AppIconLegacy.appiconset` to avoid a duplicate rendition. A `MenuBarIcon.imageset` template was added.
- `Localizable.xcstrings` and `InfoPlist.xcstrings` have complete zh-Hans values. Fixes cover conditional `Text`, `.help`, diagnostics on/off, failure summaries, About entries, and log copy. App tests check representative keys and interpolation.

### Review fixes

- Bluetooth unknown→available now rebuilds budgets and reconciles through `.systemChanged`; the event with no producer was removed.
- If the display sleeps while a connect completes, disconnect follows immediately. If the display wakes while a disconnect completes, restore the `.connected` intent and connect.
- Added a flapping limit: three automatic reconnects in 60 seconds; the fourth unexpected drop stops automation with `.reconnectRateLimited` until the next wake or manual retry.
- The IOBluetooth disconnect registration is replaced after each connect/disconnect callback; the old registration is released only after the new one succeeds. Two consecutive real drops are still required to verify it.
- The Settings window activates the app and raises itself; a window accessor tags it so a second click also raises an existing window. Added a window-lifecycle test.
- About now has an author card (GitHub avatar, email, GitHub link). The avatar uses the same public GitHub URL as Daybreak with a bundled offline fallback. Copyright in the footer, Info.plist, and LICENSE is © 2026 Dylan Liu.
- Removed specific device-category wording from product copy and icons; the UI now says "Bluetooth device" and uses the generic radio icon.
- Settings and the Add Device sheet use a native frosted background (`NSVisualEffectView`; opaque fallback with Reduce Transparency). The Form scroll background is hidden so it does not cover the material.
- The menu bar device list uses a 72–322 pt height based on device count, fixing a zero-height `ScrollView` in `MenuBarExtra` that produced a blank middle. A loading placeholder appears while the engine state is not ready.
- Added five Core recovery/race tests (39→44). Added three app frosting/window assertions (15→18). Removed all app-target Swift compiler warnings and unused menu bar set PNGs.

### Not verified / limitations

- Display sleep/wake, system sleep, dark wake, and long-idle recovery were not tested on hardware (M02–M07, M10).
- Login-item registration/restart in a signed bundle (M11), other input/audio devices (M12), actual audio output (M13), Finder/Dock 16/32 pt icons (M14), and idle resources (M15) remain open.
- The artifact is ad-hoc signed, not Developer ID signed, and not notarized. The first public release was published on 2026-11-28; see below.
- macOS may hide the menu bar icon when the bar is crowded.

## 2026-11-28 — documentation and repository polish

- Reorganized human-facing documentation into English primary files and Simplified Chinese `.zh-CN.md` pairs: README, contributing guide, documentation index, all guides, and the icon guide. Every pair has a language switch.
- Rewrote both READMEs with GitHub-supported HTML: centered hero, status badges, screenshot tables, feature and safety sections, build commands, verification summary, and limitations.
- Added English UI snapshots for the menu bar and all Settings tabs; the Chinese set is regenerated from the same test.
- Consolidated agent-facing kickoff content into `AGENTS.md`, expanded it with the documentation, screenshot, and verification rules, and removed the temporary `specs/` workspace.
- Removed regenerable `build/`, `dist/`, and `.DS_Store` artifacts from the working tree.
- Added `scripts/check-docs.sh` to verify bilingual pairs, screenshot assets, and local Markdown links; CI and `test.sh` run it.
- Localized every Diagnostics device-detail component and retry, pause, and manual-override suffixes; previously only the surrounding labels were translated while Core enum raw values and suffixes stayed English. Added a locale regression test.
- Re-rendered the Diagnostics screenshots through SwiftUI's environment locale so the English image no longer contains Chinese system values.
- Updated verification and changelog counts for 19 App tests.
- Configured the update channel to the public `mentalfl0w/BlueLink` repository; the checker reads GitHub Releases and never downloads or installs automatically.
- Added a tag/manual-dispatch release path to CI: version resolution, unsigned DMG/ZIP/SHA256 packaging, and GitHub Release publication after build, boundary, and documentation checks. Branch and pull-request runs remain read-only.
- Created the public GitHub repository with the project description and topics for macOS, Swift, SwiftUI, Bluetooth, menu-bar apps, IOBluetooth, and desktop apps.
- Published the first public release, `v1.0.0`.

## 2026-11-28 — 1.0.1 fixes

- Split the CI build and packaging steps. CI now builds the Release app once, then packages the existing product; `package-dmg.sh --no-build` avoids a second compile.
- Fixed `build.sh` to build without `BLUELINK_VERSION`/`BLUELINK_BUILD_NUMBER`, and made SHA256 sidecars contain portable filenames instead of runner-specific absolute paths.
- The update checker now falls back to the GitHub release page redirect when the unauthenticated Releases API is unavailable, so a 403 from the API does not block the update check.
- Release notes are now generated from Conventional Commit subjects by `scripts/generate-release-notes.sh`; CI checks out full tag history and passes the grouped notes to `gh release create`.
- Bumped the app version to 1.0.1.

## 2026-11-28 — 1.0.2

- Published 1.0.2 with the new Conventional Commit release-note pipeline; no user-facing behavior changed from 1.0.1.

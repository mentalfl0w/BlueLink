# Verification matrix

[简体中文](VERIFICATION.zh-CN.md) · [Documentation](README.md) · [Connection policy](CONNECTION_POLICY.md)

Status reflects actual execution. **Not tested** is not a pass. Compilation, an offscreen render, or a unit test cannot replace hardware evidence.

## Environment (2026-11-27)

| Item | Value |
|---|---|
| Machine | Mac mini (Apple M4, 16 GB) |
| OS | macOS 27.3, build 26C5047e |
| Xcode / SDK | Xcode 27.2 (27B52), macOS 27.2 SDK |
| Swift | 6.4.2 (swiftlang-6.4.2.1.9) |
| XcodeGen | 2.46.0 |
| Deployment target | macOS 26.0 |
| Signing | ad-hoc (`CODE_SIGN_IDENTITY=-`); no Developer ID, not notarized |

## Automated results

Run all commands from the repository root.

| Command | Result |
|---|---|
| `swift test --package-path Packages/BlueLinkCore` | 44 passed, 0 failed |
| `swift test --package-path Platform/MacIntegration` | 24 ran: 23 passed, 1 hardware test skipped by design |
| `xcodebuild test -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS' -derivedDataPath /tmp/bluelink-dd` | 21 passed (8 presentation, 4 localization, 2 Sparkle configuration, 7 UI/window) |
| `./scripts/test.sh` | All above plus boundary and docs checks passed |
| `./scripts/boundary-check.sh` | Passed: no forbidden imports, private APIs, `unchecked Sendable`, real Bluetooth addresses, or deployment drift |
| `./scripts/check-docs.sh` | Passed: 11 bilingual pairs, 14 screenshots, 23 Markdown files, no broken local links |
| `./scripts/package-dmg.sh` | Release build succeeded; DMG 3.6 MB, ZIP 3.2 MB, SHA256 generated |
| DMG mount check | `BlueLink.app` 1.0.0 (1), `LSMinimumSystemVersion=26.0`, `LSUIElement=true`, ad-hoc signature, detached cleanly |
| `scripts/prepare-sparkle-release.sh` (local 1.0.1 build) | Sparkle 2.10.1 resolved; signed appcast generated; EdDSA signature and appcast metadata validated |

### Update delivery (2026-11-28)

- Sparkle 2.10.1 is embedded in the Release app; `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, and `SUVerifyUpdateBeforeExtraction` are present in the built Info.plist. The XcodeGen project was regenerated.
- The appcast generator produced exactly one update item for `BlueLink-1.0.1-2.zip` with the expected enclosure URL, build number, and full release-notes URL. `verify-sparkle-appcast.swift` accepted the EdDSA signature against the embedded public key.
- Not tested: installation from the published `releases/latest/download/appcast.xml`, Sparkle's live download/quit prompt, and update behavior for a signed/notarized distribution build. No release was published for this change.
- The published 1.0.0/1.0.1 builds predate Sparkle; the first Sparkle-enabled release must be installed manually before automatic updates can work.

Coverage:

| Area | Coverage |
|---|---|
| Initialization | No managed devices means no operation; wake connect, sleep disconnect, unknown state holds (policy-table tests) |
| Recovery | Bluetooth unknown→available reconnects; Bluetooth recovery rebuilds budgets; display unknown→awake is not a new wake cycle |
| Policy | Independent toggles, pause persistence, manual-disconnect suppression for the wake cycle, repeated wake does not refresh the manual override |
| Power/session | Dark wake does not connect; system sleep disconnects; inactive session or unavailable Bluetooth stops automation |
| Concurrency | One operation per device, rapid events, late callbacks, timeout, cancellation, no new operation after pause/removal; sleep during connect disconnects; wake during disconnect reconnects |
| Retry | Virtual clock, first attempt plus bounded backoff, exhaustion, no duplicate budget refresh; the fourth unexpected drop within 60 s stops automation and the next wake recovers |
| Audio | Connection separate from audio readiness, UID match, timeout does not reconnect Bluetooth, system route respected |
| Configuration | `schemaVersion`, corrupt/unknown version does not overwrite, atomic save, pause survives relaunch |
| Localization | zh-Hans representative copy, interpolation keys, Info.plist Bluetooth usage description; `zh-Hans.lproj` is compiled into the app |
| UI | Empty state, status mapping, real SwiftUI offscreen renders in English and Chinese, window and sheet frosting, accessor lifecycle; no keyboard/VoiceOver hardware walkthrough |

## Hardware results

| ID | Operation | Result |
|---|---|---|
| M01 | Select a paired device and manually connect/disconnect | **Passed (platform + coordinator)**: `BLUELINK_REAL_DEVICE=1 … --filter RealDeviceTests` passed in 5.976 s. Connect on start, manual disconnect, and manual reconnect matched IOBluetooth; the test restored the entry state. The authorized address is not in the repository |
| M02 | Display sleep | Not tested: no display-sleep operation was performed on this machine |
| M03 | Wake recovery | Not tested: depends on M02 |
| M04 | Long idle until the device sleeps | Not tested |
| M05 | System sleep/wake and dark wake | Not tested: no authorization to sleep the machine. Dark-wake policy is covered by unit tests |
| M06 | Rapid display sleep/wake | Not tested: policy/concurrency covered by unit tests, not hardware |
| M07 | Device power loss, offline, return | Not tested: bounded retry and flapping limits covered by unit tests; no physical power-cycle test |
| M08 | Phone takeover, manual disconnect, pause/resume | Partial: manual disconnect and pause have automated coverage; no phone-takeover hardware test |
| M09 | Bluetooth off/on, permission denied | Partial: policy and transport error mapping have automated coverage; no real Bluetooth toggle |
| M10 | Multiple displays, unplug, mirroring | Not tested: display aggregation has unit tests; no hardware plug/unplug |
| M11 | Login item registration, logout, restart | Not tested: `SMAppService` requires approval in System Settings; no login/restart round trip on the ad-hoc build |
| M12 | Other input and audio devices | Partial: input classification and picker filtering are tested; no other-device hardware management |
| M13 | Preferred audio output, user switching | Partial: CoreAudio enumeration/routing is tested; no real audio playback verification |
| M14 | Distribution artifact and Icon Composer | **Partial**: `.icon` compiled as `IconImageStack`; `ictool` rendered Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark; `NSWorkspace` returns the 512 pt icon; menu bar template loads; DMG mounts. No Finder/Dock screenshot for every size; 16/32 px not inspected |
| M15 | Idle residency and repeated events | Not tested: no Activity Monitor/Instruments sampling. The design has no idle polling or timer |

## UI and screenshots

- `docs/screenshots/menu-bar-panel-{en,zh}.png`: offscreen renders of the real `MenuBarPanel` (empty state) in English and zh-Hans.
- `docs/screenshots/settings-*.png`: real SwiftUI views rendered offscreen through AppKit by the test target; not live window captures.
- `docs/screenshots/icon-*.png`: `ictool` exports of the real `.icon` appearances.
- Settings and the Add Device sheet use a native `NSVisualEffectView` behind-window material. The window is non-opaque with a clear background, and the Form scroll background is hidden. Reduce Transparency falls back to an opaque window. Tests assert `isOpaque == false`, a clear background, and the `.underWindowBackground` / `.behindWindow` material, including a real presented sheet. No before/after visual comparison over different desktop backgrounds was captured.
- The Settings window activates the app and raises itself when opened; the accessor test checks the stable identifier and visibility. Cross-application activation is not automated.
- The menu bar device list uses a 72–322 pt height based on device count to avoid a zero-height `ScrollView` in `MenuBarExtra`; all device counts were not rechecked in the live menu bar.
- macOS may hide the menu bar icon when the bar is crowded. This is system overflow behavior; no replacement entry point is implemented.

## Open assumptions

- `SMAppService.mainApp` registration and approval in a signed app bundle.
- Bluetooth TCC authorization persistence after the ad-hoc signature changes.
- Event order and latency for real display sleep/wake, dark wake, and system sleep.
- End-to-end audio playback and preferred-output switching.
- IOBluetooth disconnect-notification re-registration after two consecutive real drops.
- Long-idle CPU/memory and the practical limit for many managed devices.

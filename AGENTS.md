# AGENTS.md — BlueLink repository agent guide

> Applies to the whole repository. BlueLink is an independent macOS menu-bar product. Use the current Daybreak checkout as a reference for engineering organization and verification rules; do not copy its wallpaper, mobile, or application code. `AGENTS.md` is agent-facing and English-only. Human-facing documentation is English primary with a Simplified Chinese counterpart.

## Mission & non-negotiable scope

- Manage classic Bluetooth devices the user explicitly selects with a native macOS menu-bar app: connect when the display wakes, disconnect when the display sleeps or the Mac sleeps, and recover unexpected disconnects while the display is awake. The user has completed the device test M01 and UI acceptance; system-sleep, display-wake, and similar scenarios not yet measured stay recorded as Not tested.
- Use documented Apple public APIs only. Do not call private selectors or frameworks, private Bluetooth databases, parse system logs, or automate the UI. Do not turn global Bluetooth off, require sudo, Accessibility, Screen Recording, or Full Disk Access. Do not bundle blueutil or Hammerspoon as a runtime dependency.
- Do not pair, unpair, or control unselected devices. Do not enable global Bluetooth automatically. Input devices are unmanaged by default. Pausing management does not change the current connection. No account, cloud sync, backend, telemetry, ads, or paywall.
- Do not prevent system sleep, poll at idle, or retry forever. Document system API limitations explicitly. Treat the underlying Bluetooth connection and audio readiness as separate states.
- Do not add dedicated test entry points, debug UI, or separate user-visible test tools; use normal product interaction and automated tests. Mark scenarios that cannot be measured as Not tested. They do not block a completed phase, but must not be recorded as passing. Do not sleep, wake, or disconnect input devices on a remotely operated Mac without authorization.
- macOS only. Minimum macOS 26; verify against the current macOS 26/27 SDK. Swift 6 strict concurrency. Product copy uses "Bluetooth device" consistently and does not emphasize a specific device category.

## Authoritative documents

1. `docs/CONNECTION_POLICY.md` — single source of truth for behavior. Chinese counterpart: `docs/CONNECTION_POLICY.zh-CN.md`.
2. `docs/PLATFORM_INTEGRATION.md` — Apple APIs, capability boundaries, permissions, and audio.
3. `docs/PRODUCT_DESIGN.md` — interaction, visuals, frosted glass, localization, and icons.
4. `docs/IMPLEMENTATION.md` — repository layout, phases, and delivery state.
5. `docs/VERIFICATION.md` — automated tests, device matrix, and screenshot provenance.
6. `docs/DECISIONS.md`, `docs/CHANGELOG.md` — decisions and traceable evidence.
7. `docs/README.md` — human documentation index; `CONTRIBUTING.md` — build, test, documentation, and release policy.

Every human-facing specification has an English primary file and a `*.zh-CN.md` Chinese counterpart. When they conflict, the user's latest explicit instruction and the hard constraints in this file take precedence; behavior semantics still come from the connection policy. When behavior changes, update the specification, tests, decisions, and changelog together. Do not maintain the same contract in several places.

## Documentation policy (human-facing)

- All human-facing Markdown must have an English primary file and a Simplified Chinese counterpart: `NAME.md` and `NAME.zh-CN.md`. This covers the root README, contributing guide, every guide under `docs/`, and the icon guide. `AGENTS.md` is agent-facing and English-only.
- Each pair has a language-switch link at the top; cross-links must point to the matching language. When behavior, commands, screenshots, or test results change, update both versions in the same change.
- The README must include: project positioning, key screenshots, features, safety boundaries, requirements, build and test commands, verification summary, documentation entry points, limitations, and the license. Use GitHub-supported HTML (`<p align="center">`, `<table>`, `<sub>`, `<details>`, badges) for light layout; no scripts or inline CSS.
- `docs/README.md` is the index and lists each guide's responsibility. Update both the English and Chinese indexes when adding or renaming a document.
- Screenshots are real SwiftUI views rendered by `UISnapshotTests`, with English and Chinese sets (`-en` / `-zh`). Do not inject mock devices, fake state, or a dedicated screenshot mode. Label them as offscreen renders; never present them as live window captures.
- Run `./scripts/check-docs.sh` to verify paired files, required screenshots, and local links. Do not commit broken links.

## Expected repository structure

- `Apps/MacApp/BlueLinkMacApp.swift` — SwiftUI app entry; `Core/` holds AppModel and the composition root; `UI/` holds the menu bar, settings, device picker, about view, and frosted windows; `Localization/` holds String Catalogs; `Tests/` holds app-level tests.
- `Apps/MacApp/project.yml` — the only XcodeGen project configuration; `BlueLink.xcodeproj` is generated from it. Do not edit the pbxproj by hand instead of changing the specification.
- `Apps/MacApp/Assets.xcassets` — traditional AppIcon, menu-bar template, and author avatar; `AppIcon.icon` is generated from the real Icon Composer document and integrated.
- `Packages/BlueLinkCore/` — Foundation-only domain state, policy, coordinator, ports, and pure logic tests. Swift Package.
- `Platform/MacIntegration/` — Swift Package depending on BlueLinkCore; IOBluetooth, AppKit, CoreGraphics, CoreAudio, ServiceManagement, and configuration/logging adapters.
- `scripts/`, `.github/workflows/ci.yml` — generation, build, test, boundary and documentation checks, DMG packaging, and release.
- `branding/` — original brand graphics and icon layer sources; `docs/` — specifications, evidence, and bilingual screenshots.

Do not create MobileApp, Extensions, a cloud-sync package, or empty abstractions. Keep Core free of AppKit/SwiftUI/IOBluetooth/CoreAudio imports; Platform must not depend on the App; the App composes the layers. Add directories only for actual needs, not to imitate a layered shape. Reference the current Daybreak `Apps/MacApp/project.yml`, `CONTRIBUTING.md`, and `docs/DECISIONS.md`; do not modify Daybreak.

## Engineering rules

- Use value types for identity, events, and snapshots; protocols only at real platform boundaries; actors or provably serial mechanisms for shared mutable state. Prefer composition over inheritance and meaningless delegates.
- Allow at most one underlying operation in flight per device. A stale callback must not overwrite the latest intent; a late completion must observe actual state and reconcile, not merely be ignored. Pausing or removing a device must not start new automatic operations.
- Retries are bounded with backoff, debounce, and task generations. Canceling a Swift Task is not canceling a system operation. The UI never accesses Bluetooth directly.
- Base public API signatures on the local SDK and actual compilation. Account for ObjC callbacks, RunLoop, Sendable, and isolation boundaries. Do not hide unsafe sharing behind `unchecked Sendable`.
- No idle high-frequency timers, scanning, or silent playback. Every observer/task has a manageable lifetime. Configuration updates are atomic with a schemaVersion; never silently overwrite an unknown version.
- Use system controls and native materials, with content first. Support zh-Hans and en (adding ja is acceptable only if complete; no mixed-language UI). Frosted glass uses `NSVisualEffectView` and handles Reduce Transparency. Do not pre-bake glass into icons; prefer the real `.icon` and make any fallback visibly distinct.
- Logs are redacted by default. Never store user secrets, certificates, tokens, or real Bluetooth addresses. Collect real evidence through the normal diagnostics page and logs.

## Working procedure

1. At session start, read this file, `docs/README.md`, `docs/IMPLEMENTATION.md`, and the relevant specifications; check `git status` and the latest verification results.
2. Inspect the repository, SDK, and specifications, then perform the smallest API validation. State the plan, tests, and documentation scope before changing behavior.
3. Deliver complete vertical slices following the implementation document. Use an OMP Task Group for independent research, review, and tests; avoid multiple tasks editing the same core file at once.
4. Run commands the environment actually supports; record the SDK, command, result, and unverified hardware scenarios. Do not download unrelated simulators. Regenerate both English and Chinese screenshots when the UI changes.
5. Check failure paths, product interaction, accessibility, resource usage, and the distribution package. Update both language versions of the documentation.
6. Never commit, tag, push, release, upload assets, sign, or notarize a formal artifact without approval. After approval, follow the release procedure. Local unsigned builds are allowed; signing a test copy follows the contributing guide and requires authorization.

## Build & quality gates

See `CONTRIBUTING.md`. Target commands: `./scripts/generate-project.sh`, `./scripts/test.sh`, `./scripts/check-docs.sh`, `./scripts/package-dmg.sh`, and `xcodebuild -list -project BlueLink.xcodeproj`. Confirm the actual directories, scheme, and SDK before generating; never report an expected command as already run. There must be no new Swift 6 concurrency warnings. Tests cover races, cancellation, permissions, unknown state, failures, and retry exhaustion; report device results separately from automated results. Test counts change; do not hard-code them in `AGENTS.md`; use the latest record in `docs/VERIFICATION.md`.

## Handoff

Summary / Files changed / Tests run + results / Limitations + unverified assumptions / Next safe step. Reply to the user in Chinese by default. Record completed work in both `docs/CHANGELOG.md` and `docs/CHANGELOG.zh-CN.md`.

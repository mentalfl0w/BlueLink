# Documentation

[简体中文](README.zh-CN.md) · [Project overview](../README.md) · [Contributing](../CONTRIBUTING.md)

BlueLink 1.0.0 is implemented and tested as a local build. Automated tests and hardware M01 pass; all other hardware scenarios are marked **Not tested** until observed.

Every maintained guide has an English primary file and a Simplified Chinese pair. The pairs describe the same contract. If they disagree, the English file is authoritative for implementation review, and [Connection policy](CONNECTION_POLICY.md) remains the single source of truth for behavior.

## Maintained guides

| Guide | Responsibility |
|---|---|
| [Connection policy](CONNECTION_POLICY.md) · [中文](CONNECTION_POLICY.zh-CN.md) | Device state, events, priorities, coordinator contract, retry limits. Canonical behavior source. |
| [Platform integration](PLATFORM_INTEGRATION.md) · [中文](PLATFORM_INTEGRATION.zh-CN.md) | Public Apple APIs, permissions, display/Bluetooth/audio boundaries, platform limitations. |
| [Product design](PRODUCT_DESIGN.md) · [中文](PRODUCT_DESIGN.zh-CN.md) | Menu bar, Settings information architecture, localization, copy, and icon rules. |
| [Implementation](IMPLEMENTATION.md) · [中文](IMPLEMENTATION.zh-CN.md) | Repository layout, phases, and delivery status. |
| [Verification](VERIFICATION.md) · [中文](VERIFICATION.zh-CN.md) | Automated results, hardware matrix, screenshots, and open checks. |
| [Decisions](DECISIONS.md) · [中文](DECISIONS.zh-CN.md) | Accepted ADRs, reference snapshot, and open questions. |
| [Changelog](CHANGELOG.md) · [中文](CHANGELOG.zh-CN.md) | Dated changes, commands actually run, and observed results. |
| [Icon guide](../branding/IconComposer/README.md) · [中文](../branding/IconComposer/README.zh-CN.md) | Icon Composer layers, native appearance variants, and legacy resources. |
| [Contributing](../CONTRIBUTING.md) · [中文](../CONTRIBUTING.zh-CN.md) | Build, test, localization, documentation, packaging, and signing policy. |

`AGENTS.md` is agent-facing and English-only; it is not part of the human documentation set.

## Quick verification

```sh
./scripts/test.sh
./scripts/package-dmg.sh
```

Current result: 44 Core tests pass; 24 Platform tests run with 23 passing and one hardware test skipped by design; 21 App tests pass; boundary and documentation checks pass. Hardware M01 passes separately. See [Verification](VERIFICATION.md) for the environment and evidence.

## Screenshots

The test target renders the real SwiftUI views offscreen in English and Simplified Chinese:

- [Menu bar panel (English)](screenshots/menu-bar-panel-en.png) · [中文](screenshots/menu-bar-panel-zh.png)
- [Settings · General (English)](screenshots/settings-general-en.png) · [中文](screenshots/settings-general-zh.png)
- [Settings · Devices (English)](screenshots/settings-devices-en.png) · [中文](screenshots/settings-devices-zh.png)
- [Settings · Diagnostics (English)](screenshots/settings-diagnostics-en.png) · [中文](screenshots/settings-diagnostics-zh.png)
- [Settings · About (English)](screenshots/settings-about-en.png) · [中文](screenshots/settings-about-zh.png)
- Icons: [Default](screenshots/icon-default-256.png) · [Dark](screenshots/icon-dark-256.png) · [Tinted light](screenshots/icon-tinted-light-200.png) · [Clear light](screenshots/icon-clear-light-200.png)

These are offscreen renders, not live window captures. The app contains no screenshot mode or mock data.

## Maintenance rules

- Behavior changes update the policy, tests, decisions, and changelog together.
- Every delivery records the date, change, actual command, and observed result in the changelog.
- Write **Not tested** for scenarios that were not exercised. A build or offscreen render is not hardware evidence.
- Keep English and Chinese pairs structurally aligned. Update both language switches and cross-links in the same change.
- Label offscreen renders and live screenshots explicitly; never present one as the other.

# Product design

[简体中文](PRODUCT_DESIGN.zh-CN.md) · [Documentation](README.md)

## Visual principles

Follow the current native macOS content-first approach: clear semantics, restrained materials, and system controls. Do not copy Daybreak's wallpaper UI. Target the macOS 26/27 SDK and use `MenuBarExtra(.window)` or a verified native `NSStatusItem` approach.

Prefer system materials and controls. Do not fill the screen with glass cards, build a web dashboard, or use a flat gray background to imitate the system. Support light and dark appearance, Reduce Transparency, Reduce Motion, VoiceOver, and keyboard navigation. Never communicate status with color alone.

## Information architecture

**Menu bar panel:** BlueLink title and global automation toggle; a compact managed-device list with name, icon, observed state, connect/disconnect, and pause/resume; Add Device, Settings, and Quit at the bottom. Show a device-level failure message and retry action. Show a clear empty state when no device is managed. Do not add layers for a single device; make the list scroll for multiple devices.

**Settings:** use the system Settings scene.
- Devices: paired-device list, independent policy toggles, preferred output, remove management.
- General: launch at login, global management, and updates. Updates use the signed Sparkle feed; automatic checks and background downloads are opt-in toggles, and installation is confirmed before quitting.
- About: icon, version, project/license, author.
- Diagnostics: actual vs desired state, display/system state, recent errors, sanitized export.

The daily panel needs no long explanation. Give prompt feedback and never show a fake success. Settings and the Add Device sheet use a native `NSVisualEffectView` behind-window material. When Reduce Transparency is on, they fall back to an opaque window background. Hide the Form's scroll background so the material remains visible.

**First run:** do not take over a device. Add → request the necessary permission → show paired devices → user selects → confirm policy → reconcile. Hide input devices by default or show a strong warning; never manage the user's primary input device without confirmation. Support cancel. Removing management does not unpair the device. Global pause does not change the current connection. A manual disconnect says "won't reconnect automatically during this wake cycle"; pause persists.

**Copy:** Connect on display wake / Disconnect on display sleep / Reconnect automatically / Disconnect on system sleep / Pause automation / Connecting… / Connected / Waiting for device / Retry / Launch at login / Check for Updates… / Check for updates automatically / Automatically download updates. Automatic downloads are off by default; Sparkle may download in the background and asks before installing when the app quits. Do not expose internal class names, error codes, or the term "state convergence" in the UI; keep those in diagnostics if necessary. Use `Localizable.xcstrings` and `InfoPlist.xcstrings` with complete zh-Hans/en values. If Japanese is added, it must be complete. Use generic "Bluetooth device" wording, not a specific device category.

The menu bar list sizes itself from the managed device count (72–322 pt) and scrolls beyond that. If the engine state is not ready, show a loading placeholder instead of collapsing to an empty middle.

## Icon — macOS 26/27

Apple HIG: use a 1024×1024 layered canvas; the system applies the mask and dynamic effects. Prefer a real Icon Composer document over a baked glass PNG. See [the icon guide](../branding/IconComposer/README.md). Keep separate front and rear ribbon layers, a native background reference, and legacy icon resources. Preserve the brand silhouette and blue gradient; do not use a rounded PNG as the Icon Composer foreground. Do not shrink the colored app icon for the menu bar; use a monochrome template and check 1×/2×. Before release, check Default/Dark/Clear/Tinted appearances and Dock, Finder, and menu bar rendering.

Implemented: `AppIcon.icon` is the only compiled app icon; the legacy appiconset is renamed `AppIconLegacy` and kept as a source/fallback. The rear ribbon uses `opacity: 0.72` so front and rear layers remain distinct in Dark/Tinted appearances. `ictool` rendered Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark; exports are in `docs/screenshots/`. The menu bar panel uses `MenuBarExtra(.window)`; macOS may hide the item when the menu bar is crowded, and BlueLink does not add a replacement entry point.

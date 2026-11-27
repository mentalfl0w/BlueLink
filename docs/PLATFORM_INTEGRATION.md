# Platform integration

[简体中文](PLATFORM_INTEGRATION.zh-CN.md) · [Documentation](README.md) · [Connection policy](CONNECTION_POLICY.md)

## Evidence and references

The user previously verified that `blueutil` can connect and disconnect an authorized test device. That result does not prove BlueLink, long deep-idle recovery, system sleep, or audio restoration. The following sources were read for API behavior and licensing; record the revision when citing one.

- https://github.com/toy/blueutil — device enumeration, `openConnection`, `closeConnection`, notifications, and confirmation. Do not copy private Bluetooth power APIs.
- https://github.com/six6liu/macos-bluetooth-disconnect-on-display-sleep — requirement comparison only; do not inherit its logging scripts.
- https://github.com/odlp/bluesnooze and https://github.com/root913/bluenap — sleep-management and selective-operation references; do not reuse private interfaces.
- https://github.com/lapfelix/BluetoothConnector and https://github.com/Hammerspoon/hammerspoon — native event and classic-device control references.
- https://c-command.com/toothfairy/ — interaction and audio-state reference.

Apple documentation: [IOBluetooth](https://developer.apple.com/documentation/iobluetooth), [IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), [CoreGraphics display services](https://developer.apple.com/documentation/coregraphics/quartz_display_services), [CoreAudio](https://developer.apple.com/documentation/coreaudio), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra). Use the local SDK for exact Swift signatures.

## Display and system events

Observe `screensDidSleep` / `screensDidWake`, `willSleep` / `didWake`, and `sessionDidBecomeActive` / `sessionDidResignActive` in `NSWorkspace.shared.notificationCenter`. Initialize and confirm changes with `CGGetOnlineDisplayList`, `CGDisplayIsAsleep`, and the public display-reconfiguration callback.

At least one usable online display awake means `awake`. All displays asleep means `asleep`. A headless Mac, an ambiguous virtual display, or any unobservable state means `unknown`. Model lock screen, screen saver, session switch, dark wake, and physical monitor power separately. Do not claim support for a physically powered-off display if the system exposes no observable change. No Screen Recording or Accessibility permission is required. `pmset displaysleepnow` is allowed only for an authorized local test.

## Bluetooth adapter

Prefer `IOBluetoothDevice.pairedDevices()`, public address construction, `openConnection` (async public callbacks and page timeout where possible), `closeConnection`, `isConnected`, `registerForConnectNotifications`, and `registerForDisconnectNotification`. Manage the `IOBluetoothUserNotification` lifetime.

A disconnect notification is tied to the current link. After each connect or disconnect callback, unregister the old registration and register again so the next drop remains observable. If the system treats registration as persistent, replacing it instead of stacking also avoids duplicate callbacks. Verify this lifecycle on hardware with two consecutive drops.

ObjC callbacks and RunLoop/thread requirements must be proven with a small compile check, the normal product path, and a hardware test. Never block the UI on a synchronous API; verify the required background thread or RunLoop. Separate a failed query from no devices. If native enumeration is unreliable, evaluate the structured output of the system `system_profiler` as a low-frequency, one-shot compatibility path, and record the reason and latency; never use it for real-time control. BLE/GATT devices are not guaranteed to support classic connection APIs.

Observe permission and Bluetooth power only through public interfaces verified with the SDK, such as a public host-controller status query when available. If the state cannot be determined, report `unknown`; do not pretend Bluetooth is available. On first launch, do not operate a device before the user grants permission and selects it explicitly. Set `NSBluetoothAlwaysUsageDescription` and localize it through the String Catalog/InfoPlist. If sandboxing restricts IOBluetooth, verify it on hardware before deciding; do not claim App Store compatibility. A direct-distribution build can be non-sandboxed with minimal permissions. Do not request microphone permission to manage output. After a denial, stop retrying and explain how to use System Settings.

## Audio, login, and diagnostics

CoreAudio HAL: enumerate output devices, observe device-list and default-output changes, read `AudioDeviceUID`, transport type, and output capability, and verify the match. If a reliable Bluetooth-address mapping is unavailable, let the user choose the UID; never guess by name. Set the default output through public properties such as `kAudioHardwarePropertyDefaultOutputDevice`; show failures independently. Use `SMAppService.mainApp` for login-item registration, unregistration, status, and `requiresApproval`; do not hand-write a LaunchDaemon.

Use OSLog categories `system`, `bluetooth`, `coordinator`, `audio`, and `update`, with privacy annotations or shortened identifiers. Diagnostics show and export sanitized state and a bounded recent log from the normal UI only. Never upload logs or read a private database.

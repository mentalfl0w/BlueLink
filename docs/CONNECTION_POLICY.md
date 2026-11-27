# Connection policy — canonical contract

[简体中文](CONNECTION_POLICY.zh-CN.md) · [Documentation](README.md)

This document defines behavior. UI copy, tests, and platform adapters follow it. If another document conflicts with this contract, this file wins.

## State

Use a stable, normalized classic Bluetooth address as the `DeviceID`. The name is display-only.

Persisted `ManagedDevice`: `id`, `cachedName`, policy, `paused`, optional preferred audio UID. Persisted global state: `enabled`, `schemaVersion`. Configuration is the source of truth for intent. Connection state comes from the system and is never persisted as fact.

`SystemSnapshot`: `power` = awake / goingToSleep / asleep / unknown; `display` = awake / asleep / unknown; `session` = active / inactive / unknown; `bluetooth` = available / unavailable / unauthorized / unknown. Use `unknown` when a headless Mac, hardware power loss, or another limitation prevents reliable observation.

`DeviceSnapshot`: `observed` = unknown / connected / disconnected / unavailable; `operation` = idle / connecting / disconnecting / settling. Errors and audio readiness are separate. `desired` = connected / disconnected / unmanaged. Keep the trigger event, the observed fact, and the desired intent distinct. Never overwrite a real connection state with an error flag.

Per-device defaults: `connectOnDisplayWake=true`, `disconnectOnDisplaySleep=true`, `reconnectOnUnexpectedDisconnect=true`, `disconnectOnSystemSleep=true`, `preferredAudio=false`, `paused=false`. Global `enabled` defaults to true, but an empty managed list performs no operations. Each toggle affects only its policy.

## Policy evaluation

Rules are evaluated top to bottom. The first match wins.

| Condition | Automatic target |
|---|---|
| Not managed, paused, or global automation off | `unmanaged`; cancel pending retries, keep the current connection |
| Session inactive, Bluetooth unavailable/unknown | `unmanaged`; do not fight the system or power Bluetooth on |
| `goingToSleep` / `asleep` | `disconnected` when disconnect-on-system-sleep is on; best effort on willSleep. Otherwise `unmanaged` |
| Power unknown | `unmanaged` |
| Display unknown | `unmanaged` |
| Display asleep | `disconnected` when disconnect-on-display-sleep is on; otherwise `unmanaged`. Never reconnect |
| Display awake, with a manual-disconnect override for this wake cycle | `unmanaged` |
| Real wake event, app start, management resume, or explicit configuration change | `connected` when connect-on-display-wake is on; otherwise `unmanaged` |
| Display awake, confirmed unexpected drop | `connected` when reconnect-on-unexpected-drop is on; otherwise `unmanaged`. Do not treat connect-on-wake as a permanent connect force |
| Anything else | Preserve a valid current intent or stay `unmanaged`; never issue an unnecessary operation |

Use event context, not a single boolean mapping. Otherwise, turning automatic reconnect off could still be overridden repeatedly by the wake rule. Define a wake event as a confirmed `asleep → awake` transition. Reading `awake` at launch may trigger one initialization reconcile, but repeated wake notifications must not reset a manual override or the retry budget. A system wake with the display still off does not create a connect intent.

Manual connect and disconnect are allowed in an active session when Bluetooth is available; they do not depend on the automatic toggles. A manual disconnect overrides the current wake cycle. Clear it on the next real wake cycle or an explicit management resume. Pause persists across launches. A manual connect overrides an older intent. Entering a new display-sleep or system-sleep state still follows policy. The system may not let BlueLink distinguish a user disconnect in System Settings from a device drop; say so honestly and offer an easy pause. Removing management or quitting the app does not intentionally change the current connection. If a non-cancellable operation was already issued, record its late result; do not issue new automatic operations after pause.

## Reconciliation

The loop is: event → refresh the affected snapshot → pure policy evaluation → serialize by `DeviceID` → platform call → observe and confirm → continue from the latest intent.

Avoid registration gaps: register notifications, then query the snapshot, and deduplicate. Duplicate, out-of-order, or missing connect/disconnect notifications may be confirmed with a bounded state query; do not poll continuously when no event occurs. Never issue concurrent open/close calls for one device. A platform timeout does not mean the operation ended; keep it in flight or quarantined until termination or reliable confirmation, then compensate toward the latest target. Each operation has an `operationID`; each intent has a generation. Cancel delayed tasks and handle stale completions.

The initial retry budget is one attempt plus four retries with 1/2/4/8-second backoff; use actual SDK timeouts and measured behavior. Bound each timeout and jitter. Unexpected drops also have a flapping limit: allow three automatic reconnects in 60 seconds; the fourth unexpected drop stops automatic reconnect and shows a failure that can be retried manually. Reset both budgets only on a new real wake, Bluetooth service recovery, an effective configuration change, or an explicit retry. A successful connection alone does not reset them; this avoids an unbounded connect/drop loop. Duplicate notifications do not reset the budget. Stop when the budget is exhausted; no permanent timer. Cancel pending retries promptly on display sleep, pause, or removal. If a connect completes late, reconcile: disconnect if the display went to sleep in the meantime. Disconnect before sleep is best effort; never use a power assertion to extend sleep.

## Audio

The presence of an IOBluetooth ACL connection does not prove that A2DP/HFP or another audio profile is ready. Respect the system audio route by default. The optional preferred output is a stable, user-chosen `AudioDeviceUID`; apply it once after a suitable connection event and only when the output device is ready. Wait with a bound, use device-list notifications, never switch back repeatedly, never change input or volume, and never reconnect Bluetooth because audio is missing. Only one global preferred-output automation is allowed; it is off by default.

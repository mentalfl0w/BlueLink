import Foundation
import AppKit
import CoreGraphics
import BlueLinkCore

public enum DisplayAggregation {
    /// Any genuinely awake online display keeps the host "awake"; all asleep is
    /// "asleep"; no online display is "unknown" rather than guessed.
    public static func state(onlineDisplayCount: Int, asleepDisplayCount: Int) -> DisplayState {
        guard onlineDisplayCount > 0 else { return .unknown }
        if asleepDisplayCount >= onlineDisplayCount { return .asleep }
        return .awake
    }
}

extension Notification.Name {
    static let blueLinkDisplayReconfiguration = Notification.Name("dev.bluelink.displayReconfiguration")
}

private func blueLinkDisplayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    NotificationCenter.default.post(name: .blueLinkDisplayReconfiguration, object: nil)
}

/// Observes public system state without polling: NSWorkspace notifications for
/// sleep/wake/session changes, the CoreGraphics reconfiguration callback for
/// display changes, and an injected reader for controller power state.
@MainActor
public final class SystemStateMonitor {
    public var onSnapshot: ((SystemSnapshot) -> Void)?

    private let bluetoothReader: @Sendable () async -> BluetoothAvailability
    private var snapshot: SystemSnapshot
    private var observers: [NSObjectProtocol] = []
    private var displayRefreshTask: Task<Void, Never>?
    private var bluetoothRefreshInFlight = false
    private var isStarted = false

    public init(bluetoothReader: @escaping @Sendable () async -> BluetoothAvailability) {
        self.bluetoothReader = bluetoothReader
        snapshot = SystemSnapshot(power: .awake, display: .unknown, session: .active, bluetooth: .unknown)
    }

    public var current: SystemSnapshot { snapshot }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        snapshot.display = Self.readDisplayState()
        publish()

        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.screensDidSleepNotification) { monitor in
            monitor.snapshot.display = .asleep
            monitor.publish()
        }
        observe(center, NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.refreshDisplay(after: .milliseconds(250))
        }
        observe(center, NSWorkspace.willSleepNotification) { monitor in
            monitor.snapshot.power = .goingToSleep
            monitor.publish()
        }
        observe(center, NSWorkspace.didWakeNotification) { monitor in
            monitor.snapshot.power = .awake
            monitor.publish()
            monitor.refreshDisplay(after: .milliseconds(250))
        }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { monitor in
            monitor.snapshot.session = .inactive
            monitor.publish()
        }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { monitor in
            monitor.snapshot.session = .active
            monitor.publish()
        }

        let displayObserver = NotificationCenter.default.addObserver(
            forName: .blueLinkDisplayReconfiguration,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplay(after: .milliseconds(150)) }
        }
        observers.append(displayObserver)

        CGDisplayRegisterReconfigurationCallback(blueLinkDisplayReconfigurationCallback, nil)
        refreshBluetooth()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        displayRefreshTask?.cancel()
        displayRefreshTask = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        CGDisplayRemoveReconfigurationCallback(blueLinkDisplayReconfigurationCallback, nil)
    }

    /// A cheap refresh used when the menu bar panel opens: display state plus a
    /// one-shot controller query, never a recurring timer.
    public func refresh() {
        snapshot.display = Self.readDisplayState()
        publish()
        refreshBluetooth()
    }

    public func refreshBluetooth() {
        guard !bluetoothRefreshInFlight else { return }
        bluetoothRefreshInFlight = true
        let reader = bluetoothReader
        Task { @MainActor in
            let availability = await reader()
            bluetoothRefreshInFlight = false
            guard isStarted else { return }
            if snapshot.bluetooth != availability {
                snapshot.bluetooth = availability
                publish()
            }
        }
    }

    private func refreshDisplay(after delay: Duration) {
        displayRefreshTask?.cancel()
        displayRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let newState = Self.readDisplayState()
            if snapshot.display != newState {
                snapshot.display = newState
                publish()
            }
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        apply: @escaping @MainActor (SystemStateMonitor) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                apply(self)
            }
        }
        observers.append(observer)
    }

    private func publish() {
        onSnapshot?(snapshot)
    }

    private static func readDisplayState() -> DisplayState {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return .unknown
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return .unknown
        }
        let asleep = displays.prefix(Int(count)).reduce(into: 0) { partial, display in
            if CGDisplayIsAsleep(display) != 0 { partial += 1 }
        }
        return DisplayAggregation.state(onlineDisplayCount: Int(count), asleepDisplayCount: asleep)
    }
}

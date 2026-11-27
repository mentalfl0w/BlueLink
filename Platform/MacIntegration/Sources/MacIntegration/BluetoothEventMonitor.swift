import Foundation
import IOBluetooth
import BlueLinkCore

/// Keeps `IOBluetoothUserNotification` registrations alive and forwards device
/// activity to the engine. Notifications are hints only: the receiver must
/// re-read the real connection state.
@MainActor
public final class BluetoothEventMonitor: NSObject {
    /// Called on the main actor with the address that changed.
    public var onDeviceActivity: ((DeviceID) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [DeviceID: IOBluetoothUserNotification] = [:]
    private var managedDevices: [DeviceID] = []
    public private(set) var isRunning = false

    public override init() {
        super.init()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(connectionNotification(_:device:))
        )
        refreshDisconnectRegistrations()
    }

    public func setManagedDevices(_ ids: [DeviceID]) {
        managedDevices = ids
        guard isRunning else { return }
        refreshDisconnectRegistrations()
    }

    public func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
        isRunning = false
    }

    private func refreshDisconnectRegistrations() {
        let wanted = Set(managedDevices)
        let stale = disconnectNotifications.keys.filter { !wanted.contains($0) }
        for id in stale {
            disconnectNotifications.removeValue(forKey: id)?.unregister()
        }
        for id in wanted where disconnectNotifications[id] == nil {
            guard let device = IOBluetoothDevice(addressString: id.address) else { continue }
            let notification = device.register(
                forDisconnectNotification: self,
                selector: #selector(disconnectionNotification(_:device:))
            )
            if let notification {
                disconnectNotifications[id] = notification
            }
        }
    }

    @objc private nonisolated func connectionNotification(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        forward(address: device.addressString)
    }

    @objc private nonisolated func disconnectionNotification(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        forward(address: device.addressString)
    }

    private nonisolated func forward(address: String?) {
        guard let address, let id = DeviceID(raw: address) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onDeviceActivity?(id)
            // Disconnect registrations are tied to the current link; refresh
            // after activity so the next drop is observed again.
            self.rearmDisconnectRegistration(for: id)
        }
    }

    /// Replaces the registration instead of stacking another one. The old
    /// registration is only dropped after the replacement exists, so a failed
    /// re-registration cannot silently remove disconnect monitoring.
    private func rearmDisconnectRegistration(for id: DeviceID) {
        guard isRunning, managedDevices.contains(id) else { return }
        guard let device = IOBluetoothDevice(addressString: id.address),
              let notification = device.register(
                  forDisconnectNotification: self,
                  selector: #selector(disconnectionNotification(_:device:))
              ) else { return }
        disconnectNotifications.removeValue(forKey: id)?.unregister()
        disconnectNotifications[id] = notification
    }

    deinit {
        // `stop()` is called explicitly on application termination. Calling
        // `unregister()` here would touch non-Sendable framework objects from
        // an arbitrary thread, so deinit intentionally only drops references.
    }
}

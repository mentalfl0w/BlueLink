import Foundation
import IOBluetooth
import BlueLinkCore

/// Pure mapping from `BluetoothClassOfDevice` bits to UI-facing categories.
public enum BluetoothDeviceClassifier {
    /// Major device class bit field, bits 8...12.
    public static func majorClass(of classOfDevice: UInt32) -> UInt32 {
        (classOfDevice >> 8) & 0x1F
    }

    /// HID peripherals (keyboard, pointing device, combo). The current user's
    /// main input devices must never be managed silently.
    public static func isInputDevice(classOfDevice: UInt32) -> Bool {
        majorClass(of: classOfDevice) == 0x05
    }

    public static func isAudioDevice(classOfDevice: UInt32) -> Bool {
        majorClass(of: classOfDevice) == 0x04
    }
}

/// IOBluetooth-backed classic Bluetooth transport.
///
/// The struct carries only a `DispatchQueue`; every device lookup happens on
/// that queue, and the blocking `openConnection`/`closeConnection` calls never
/// run on the main thread. Cancelling the Swift task does not cancel the
/// underlying system call, so callers must always observe the real connection
/// state after a late return.
public struct IOBluetoothTransport: BluetoothTransport {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(
        label: "dev.bluelink.bluetooth",
        qos: .userInitiated,
        attributes: .concurrent
    )) {
        self.queue = queue
    }

    public func pairedDevices() async throws -> [PairedDevice] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let raw = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
                    continuation.resume(returning: [])
                    return
                }
                let devices = raw.compactMap { device -> PairedDevice? in
                    guard let address = device.addressString, let id = DeviceID(raw: address) else {
                        return nil
                    }
                    let name = device.nameOrAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return PairedDevice(
                        id: id,
                        name: (name?.isEmpty == false ? name! : id.address),
                        isConnected: device.isConnected(),
                        isInputDevice: BluetoothDeviceClassifier.isInputDevice(classOfDevice: device.classOfDevice),
                        isAudioDevice: BluetoothDeviceClassifier.isAudioDevice(classOfDevice: device.classOfDevice),
                        isPaired: device.isPaired()
                    )
                }
                continuation.resume(returning: devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        }
    }

    public func isConnected(_ id: DeviceID) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let device = IOBluetoothDevice(addressString: id.address) else {
                    continuation.resume(throwing: BluetoothTransportError.deviceNotFound)
                    return
                }
                continuation.resume(returning: device.isConnected())
            }
        }
    }

    public func connect(_ id: DeviceID, timeout: Duration) async throws {
        let pageTimeout = Self.pageTimeout(for: timeout)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard let device = IOBluetoothDevice(addressString: id.address) else {
                    continuation.resume(throwing: BluetoothTransportError.deviceNotFound)
                    return
                }
                if device.isConnected() {
                    continuation.resume()
                    return
                }
                guard device.isPaired() else {
                    continuation.resume(throwing: BluetoothTransportError.notPaired)
                    return
                }
                let result = device.openConnection(
                    nil,
                    withPageTimeout: pageTimeout,
                    authenticationRequired: false
                )
                if result != kIOReturnSuccess {
                    continuation.resume(throwing: BluetoothTransportError.operationFailed(code: result))
                    return
                }
                if device.isConnected() {
                    continuation.resume()
                } else {
                    // The call returned successfully but the ACL link is not up.
                    // Report the truth; never claim a connection that does not exist.
                    continuation.resume(throwing: BluetoothTransportError.timedOut)
                }
            }
        }
    }

    public func disconnect(_ id: DeviceID, timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard let device = IOBluetoothDevice(addressString: id.address) else {
                    continuation.resume(throwing: BluetoothTransportError.deviceNotFound)
                    return
                }
                guard device.isConnected() else {
                    continuation.resume()
                    return
                }
                let result = device.closeConnection()
                guard result == kIOReturnSuccess else {
                    continuation.resume(throwing: BluetoothTransportError.operationFailed(code: result))
                    return
                }
                // Bounded confirmation; this is a single post-operation check,
                // not a recurring poll.
                let deadline = Date().addingTimeInterval(min(1.0, max(0.1, timeout.seconds)))
                while device.isConnected(), Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                continuation.resume()
            }
        }
    }

    /// Reads the host controller power state. `unavailable` after authorization
    /// denial cannot be distinguished from a powered-off controller through
    /// public APIs; both stop automatic work, which is the safe behaviour.
    public func availability() async -> BluetoothAvailability {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let controller = IOBluetoothHostController.default() else {
                    continuation.resume(returning: .unknown)
                    return
                }
                switch controller.powerState {
                case kBluetoothHCIPowerStateON:
                    continuation.resume(returning: .available)
                case kBluetoothHCIPowerStateOFF:
                    continuation.resume(returning: .unavailable)
                default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    /// Bluetooth HCI page timeout units are 0.625 ms. Clamped to the public
    /// 0x0016...0xFFFF range so a caller cannot request an unbounded wait.
    static func pageTimeout(for duration: Duration) -> BluetoothHCIPageTimeout {
        let units = Int((duration.seconds / 0.000_625).rounded())
        let clamped = min(max(units, 0x0016), 0xFFFF)
        return BluetoothHCIPageTimeout(clamped)
    }
}

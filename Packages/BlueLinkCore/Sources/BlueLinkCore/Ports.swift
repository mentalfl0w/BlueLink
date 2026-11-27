import Foundation

/// A paired device as the platform reports it. This is presentation and
/// selection data only; connection identity is always `DeviceID`.
public struct PairedDevice: Identifiable, Equatable, Sendable {
    public var id: DeviceID
    public var name: String
    public var isConnected: Bool
    public var isInputDevice: Bool
    public var isAudioDevice: Bool
    public var isPaired: Bool

    public init(
        id: DeviceID,
        name: String,
        isConnected: Bool,
        isInputDevice: Bool,
        isAudioDevice: Bool,
        isPaired: Bool
    ) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.isInputDevice = isInputDevice
        self.isAudioDevice = isAudioDevice
        self.isPaired = isPaired
    }
}

public enum BluetoothTransportError: Error, Equatable, Sendable {
    case deviceNotFound
    case notPaired
    case busy
    case operationFailed(code: Int32)
    case timedOut
    case unsupported
}

/// The only Bluetooth surface the engine may use.
public protocol BluetoothTransport: Sendable {
    func pairedDevices() async throws -> [PairedDevice]
    func isConnected(_ id: DeviceID) async throws -> Bool
    func connect(_ id: DeviceID, timeout: Duration) async throws
    func disconnect(_ id: DeviceID, timeout: Duration) async throws
}

public protocol EngineClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: EngineClock {
    public init() {}

    public func now() async -> Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Deterministic clock for tests: `advance(by:)` releases sleepers whose
/// deadline has passed, so retry tests never wait on wall time.
public actor TestClock: EngineClock {
    private var current: Date
    private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var deadlines: [UUID: Date] = [:]

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = now
    }

    public func now() async -> Date { current }

    public func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            sleepers[id] = continuation
            deadlines[id] = current.addingTimeInterval(duration.seconds)
        }
    }

    public func advance(by duration: Duration) {
        current = current.addingTimeInterval(duration.seconds)
        let due = deadlines.filter { $0.value <= current }.map(\.key)
        for id in due {
            deadlines.removeValue(forKey: id)
            sleepers.removeValue(forKey: id)?.resume()
        }
    }

    public func wakeAll() {
        let pending = sleepers
        sleepers.removeAll()
        deadlines.removeAll()
        for (_, continuation) in pending {
            continuation.resume()
        }
    }

    public func pendingSleepCount() -> Int { sleepers.count }

    public func setNow(_ date: Date) { current = date }
}

extension Duration {
    /// Seconds as `Double`; only used for clocks and deadlines.
    public var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

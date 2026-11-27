import Foundation

// MARK: - Configuration

/// Per-device automation policy. Every switch is independent; turning one off
/// never changes another.
public struct DevicePolicy: Codable, Equatable, Sendable {
    public var connectOnDisplayWake: Bool
    public var disconnectOnDisplaySleep: Bool
    public var reconnectOnUnexpectedDisconnect: Bool
    public var disconnectOnSystemSleep: Bool
    /// Stable CoreAudio UID. `nil` means "respect the system routing".
    public var preferredAudioUID: String?

    public init(
        connectOnDisplayWake: Bool = true,
        disconnectOnDisplaySleep: Bool = true,
        reconnectOnUnexpectedDisconnect: Bool = true,
        disconnectOnSystemSleep: Bool = true,
        preferredAudioUID: String? = nil
    ) {
        self.connectOnDisplayWake = connectOnDisplayWake
        self.disconnectOnDisplaySleep = disconnectOnDisplaySleep
        self.reconnectOnUnexpectedDisconnect = reconnectOnUnexpectedDisconnect
        self.disconnectOnSystemSleep = disconnectOnSystemSleep
        self.preferredAudioUID = preferredAudioUID
    }
}

public struct ManagedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: DeviceID
    /// Last known name, used only after the device disappears from the list.
    public var cachedName: String
    public var policy: DevicePolicy
    public var isPaused: Bool

    public init(id: DeviceID, cachedName: String, policy: DevicePolicy = .init(), isPaused: Bool = false) {
        self.id = id
        self.cachedName = cachedName
        self.policy = policy
        self.isPaused = isPaused
    }
}

/// Persisted user configuration. Connection state is never stored here.
public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var isGloballyEnabled: Bool
    public var devices: [ManagedDevice]

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        isGloballyEnabled: Bool = true,
        devices: [ManagedDevice] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isGloballyEnabled = isGloballyEnabled
        self.devices = devices
    }

    public var isEffectivelyEnabled: Bool { isGloballyEnabled && !devices.isEmpty }

    public func device(_ id: DeviceID) -> ManagedDevice? {
        devices.first { $0.id == id }
    }

    /// Replaces one device in place, preserving list order.
    public mutating func update(_ device: ManagedDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }
}

// MARK: - System state

public enum PowerState: String, Codable, Sendable, CaseIterable {
    case awake
    case goingToSleep
    case asleep
    case unknown
}

public enum DisplayState: String, Codable, Sendable, CaseIterable {
    case awake
    case asleep
    case unknown
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case active
    case inactive
    case unknown
}

public enum BluetoothAvailability: String, Codable, Sendable, CaseIterable {
    case available
    case unavailable
    /// Authorization was denied or the controller cannot be observed.
    case unauthorized
    case unknown
}

/// Everything the policy is allowed to observe about the host. Unknown is a
/// first-class value: the app never upgrades an unobservable state into awake.
public struct SystemSnapshot: Equatable, Sendable {
    public var power: PowerState
    public var display: DisplayState
    public var session: SessionState
    public var bluetooth: BluetoothAvailability

    public init(
        power: PowerState = .unknown,
        display: DisplayState = .unknown,
        session: SessionState = .unknown,
        bluetooth: BluetoothAvailability = .unknown
    ) {
        self.power = power
        self.display = display
        self.session = session
        self.bluetooth = bluetooth
    }

    public static let unknown = SystemSnapshot()

    /// The only state in which the app may start an automatic connection.
    public var permitsAutomaticConnection: Bool {
        power == .awake && display == .awake && session == .active && bluetooth == .available
    }
}

// MARK: - Device state

public enum ObservedConnection: String, Codable, Sendable, CaseIterable {
    case unknown
    case connected
    case disconnected
    /// The device was not found in the paired list.
    case unavailable
}

public enum OperationPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case connecting
    case disconnecting
    /// A system call overran its deadline; its late completion is still awaited.
    case settling
}

public enum DesiredConnection: String, Codable, Sendable, CaseIterable {
    case unmanaged
    case connected
    case disconnected
}

public struct DeviceFailure: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case connectFailed
        case disconnectFailed
        case timedOut
        case bluetoothUnavailable
        case unauthorized
        case deviceMissing
        case sessionInactive
        case audioUnavailable
        case reconnectRateLimited
        case unknown
    }

    public var kind: Kind
    /// Short, already-sanitized detail for diagnostics. Never an address.
    public var detail: String?
    public var occurredAt: Date

    public init(kind: Kind, detail: String? = nil, occurredAt: Date) {
        self.kind = kind
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

// MARK: - Engine input/output

public enum ObservedTransition: String, Sendable, Equatable {
    case none
    case becameConnected
    case becameDisconnected
}

public struct DeviceState: Identifiable, Equatable, Sendable {
    public var id: DeviceID
    public var name: String
    public var policy: DevicePolicy
    public var isPaused: Bool
    public var desired: DesiredConnection
    public var observed: ObservedConnection
    public var operation: OperationPhase
    public var failure: DeviceFailure?
    public var retryAttempt: Int
    public var retryExhausted: Bool
    public var isManualOverrideActive: Bool
    public var audioReady: Bool?

    public init(
        id: DeviceID,
        name: String,
        policy: DevicePolicy,
        isPaused: Bool,
        desired: DesiredConnection,
        observed: ObservedConnection,
        operation: OperationPhase,
        failure: DeviceFailure?,
        retryAttempt: Int,
        retryExhausted: Bool,
        isManualOverrideActive: Bool,
        audioReady: Bool?
    ) {
        self.id = id
        self.name = name
        self.policy = policy
        self.isPaused = isPaused
        self.desired = desired
        self.observed = observed
        self.operation = operation
        self.failure = failure
        self.retryAttempt = retryAttempt
        self.retryExhausted = retryExhausted
        self.isManualOverrideActive = isManualOverrideActive
        self.audioReady = audioReady
    }
}

public struct EngineState: Equatable, Sendable {
    public var system: SystemSnapshot
    public var isGloballyEnabled: Bool
    public var devices: [DeviceState]

    public init(system: SystemSnapshot, isGloballyEnabled: Bool, devices: [DeviceState]) {
        self.system = system
        self.isGloballyEnabled = isGloballyEnabled
        self.devices = devices
    }

    public var isManaging: Bool { isGloballyEnabled && devices.contains { !$0.isPaused } }
    public var managedDeviceCount: Int { devices.count }
    public var connectedCount: Int { devices.filter { $0.observed == .connected }.count }
}

public enum EngineEffect: Sendable, Equatable {
    /// Route output once for a successful connection. The receiver must not
    /// retry the Bluetooth connection because audio is late or missing.
    case routeAudio(device: DeviceID, uid: String)
}

public enum EngineEvent: Sendable, Equatable {
    case start
    case systemChanged(SystemSnapshot)
    /// A platform notification reported activity for a managed device. The
    /// engine re-reads the real state instead of trusting the notification.
    case externalDeviceChange(DeviceID)
    case observation(DeviceID, ObservedConnection)
    case configurationChanged(AppConfiguration)
    case manualConnect(DeviceID)
    case manualDisconnect(DeviceID)
    case retryNow(DeviceID)
    case audioReadiness(DeviceID, Bool)
    case retryDue(DeviceID, Int)
}

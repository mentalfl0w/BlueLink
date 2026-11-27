import Foundation

public enum ReconcileTrigger: String, Sendable, Equatable {
    case none
    /// A confirmed asleep → awake transition.
    case wakeCycle
    /// Application start while the system reads awake.
    case launch
    case configurationChange
    case bluetoothRecovered
    /// An explicit user request; always allowed while the session is usable.
    case explicitRetry
    case unexpectedDisconnect
}

public struct PolicyInput: Sendable, Equatable {
    public var isGloballyEnabled: Bool
    public var device: ManagedDevice
    public var system: SystemSnapshot
    public var observed: ObservedConnection
    public var operation: OperationPhase
    public var manualDisconnectInCurrentCycle: Bool
    public var trigger: ReconcileTrigger

    public init(
        isGloballyEnabled: Bool,
        device: ManagedDevice,
        system: SystemSnapshot,
        observed: ObservedConnection,
        operation: OperationPhase,
        manualDisconnectInCurrentCycle: Bool,
        trigger: ReconcileTrigger
    ) {
        self.isGloballyEnabled = isGloballyEnabled
        self.device = device
        self.system = system
        self.observed = observed
        self.operation = operation
        self.manualDisconnectInCurrentCycle = manualDisconnectInCurrentCycle
        self.trigger = trigger
    }
}

public enum PolicyDecision: String, Sendable, Equatable {
    case unmanaged
    case connect
    case disconnect
    /// No new intent; keep a legitimate in-progress goal untouched.
    case preserve
}

/// The single source of truth for automatic connection policy.
///
/// Rules are evaluated top-down and stop at the first match, matching
/// `docs/CONNECTION_POLICY.md`.
public enum ConnectionPolicy {
    public static func decide(_ input: PolicyInput) -> PolicyDecision {
        let system = input.system
        let policy = input.device.policy

        // Paused, removed or globally disabled: never issue new automatic work.
        guard input.isGloballyEnabled, !input.device.isPaused else { return .unmanaged }

        // A non-active session or an unavailable controller never races the user
        // and never powers Bluetooth on.
        guard system.session == .active, system.bluetooth == .available else { return .unmanaged }

        switch system.power {
        case .goingToSleep, .asleep:
            return policy.disconnectOnSystemSleep ? .disconnect : .unmanaged
        case .unknown:
            return .unmanaged
        case .awake:
            break
        }

        switch system.display {
        case .unknown:
            return .unmanaged
        case .asleep:
            return policy.disconnectOnDisplaySleep ? .disconnect : .unmanaged
        case .awake:
            break
        }

        // A manual disconnect suppresses automatic connects until the next real
        // wake cycle; a pause or removal is handled above.
        if input.manualDisconnectInCurrentCycle { return .unmanaged }

        switch input.trigger {
        case .wakeCycle, .launch, .configurationChange, .bluetoothRecovered:
            return policy.connectOnDisplayWake ? .connect : .unmanaged
        case .explicitRetry:
            return .connect
        case .unexpectedDisconnect:
            return policy.reconnectOnUnexpectedDisconnect ? .connect : .unmanaged
        case .none:
            // "Keep the legitimate current intent." A connect requested by the
            // current wake cycle must stay intact so a later unexpected drop is
            // still recognised; .none itself never starts new work.
            return .preserve
        }
    }
}

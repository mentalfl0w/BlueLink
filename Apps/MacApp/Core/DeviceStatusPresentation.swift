import Foundation
import BlueLinkCore

enum DeviceStatus: Equatable {
    case automationOff
    case paused
    case connecting
    case disconnecting
    case settling
    case connected
    case connectedAudioReady
    case connectedAudioUnavailable
    case reconnecting(attempt: Int)
    case failed(DeviceFailure.Kind)
    case manualOverride
    case unavailable
    case waitingForWake
    case disconnected
}

enum DeviceStatusPresentation {
    static func status(
        for device: DeviceState,
        system: SystemSnapshot,
        globallyEnabled: Bool
    ) -> DeviceStatus {
        guard globallyEnabled else { return .automationOff }
        if device.isPaused { return .paused }

        switch device.operation {
        case .connecting: return .connecting
        case .disconnecting: return .disconnecting
        case .settling: return .settling
        case .idle: break
        }

        if device.observed == .connected {
            switch device.audioReady {
            case true?: return .connectedAudioReady
            case false?: return .connectedAudioUnavailable
            case nil: return .connected
            }
        }

        if let failure = device.failure, device.retryExhausted {
            return .failed(failure.kind)
        }
        if device.retryAttempt > 0 {
            return .reconnecting(attempt: device.retryAttempt)
        }
        if device.isManualOverrideActive {
            return .manualOverride
        }
        if device.observed == .unavailable {
            return .unavailable
        }
        if system.display == .asleep || system.power != .awake {
            return .waitingForWake
        }
        return .disconnected
    }

    static func canDisconnect(_ device: DeviceState) -> Bool {
        device.observed == .connected && device.operation == .idle
    }

    static func canConnect(_ device: DeviceState) -> Bool {
        device.operation == .idle && device.observed != .connected
    }

    /// Short label used in compact status lines.
    static func failureSummary(_ kind: DeviceFailure.Kind) -> LocalizedStringResource {
        switch kind {
        case .connectFailed: "Couldn't connect"
        case .disconnectFailed: "Couldn't disconnect"
        case .timedOut: "Connection timed out"
        case .bluetoothUnavailable: "Bluetooth is off"
        case .unauthorized: "Bluetooth access denied"
        case .deviceMissing: "Device not found"
        case .sessionInactive: "Session is inactive"
        case .audioUnavailable: "Preferred audio unavailable"
        case .reconnectRateLimited: "Reconnection paused"
        case .unknown: "Operation failed"
        }
    }

    /// Sentence used in settings and detailed views.
    static func failureDetail(_ kind: DeviceFailure.Kind) -> LocalizedStringResource {
        switch kind {
        case .connectFailed: "Couldn't connect."
        case .disconnectFailed: "Couldn't disconnect."
        case .timedOut: "The connection timed out."
        case .bluetoothUnavailable: "Bluetooth is off or unavailable."
        case .unauthorized: "Bluetooth access was denied."
        case .deviceMissing: "The device is no longer paired."
        case .sessionInactive: "The session is not active."
        case .audioUnavailable: "The preferred audio output is unavailable."
        case .reconnectRateLimited: "The device disconnected repeatedly. Automatic reconnection stopped until the next wake cycle or a manual retry."
        case .unknown: "The operation failed."
        }
    }
}

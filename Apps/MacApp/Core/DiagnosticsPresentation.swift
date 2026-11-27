import Foundation
import BlueLinkCore

/// Formats diagnostic device state without exposing Core enum raw values to the UI.
enum DiagnosticsPresentation {
    static func deviceDetail(for device: DeviceState, locale: Locale = .current) -> String {
        var parts = [
            String(localized: "target \(desiredLabel(device.desired, locale: locale))", locale: locale),
            String(localized: "actual \(observedLabel(device.observed, locale: locale))", locale: locale),
            String(localized: "operation \(operationLabel(device.operation, locale: locale))", locale: locale),
        ]
        if device.retryAttempt > 0 {
            parts.append(String(localized: "retry \(device.retryAttempt)", locale: locale))
        }
        if device.isPaused {
            parts.append(String(localized: "paused", locale: locale))
        }
        if device.isManualOverrideActive {
            parts.append(String(localized: "manual override", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private static func desiredLabel(_ value: DesiredConnection, locale: Locale) -> String {
        switch value {
        case .connected: String(localized: "Connected", locale: locale)
        case .disconnected: String(localized: "Disconnected", locale: locale)
        case .unmanaged: String(localized: "Unmanaged", locale: locale)
        }
    }

    private static func observedLabel(_ value: ObservedConnection, locale: Locale) -> String {
        switch value {
        case .unknown: String(localized: "Unknown", locale: locale)
        case .connected: String(localized: "Connected", locale: locale)
        case .disconnected: String(localized: "Disconnected", locale: locale)
        case .unavailable: String(localized: "Unavailable", locale: locale)
        }
    }

    private static func operationLabel(_ value: OperationPhase, locale: Locale) -> String {
        switch value {
        case .idle: String(localized: "Idle", locale: locale)
        case .connecting: String(localized: "Connecting", locale: locale)
        case .disconnecting: String(localized: "Disconnecting", locale: locale)
        case .settling: String(localized: "Settling", locale: locale)
        }
    }
}

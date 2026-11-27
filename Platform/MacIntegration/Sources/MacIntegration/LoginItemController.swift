import Foundation
import ServiceManagement

/// Login item backed by `SMAppService.mainApp`. No LaunchDaemon or helper is
/// installed; macOS owns the registration and exposes approval state.
public struct LoginItemController: Sendable {
    public enum Status: String, Sendable, Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notFound
        case unknown
    }

    public init() {}

    public func status() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

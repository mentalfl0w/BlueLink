import Foundation

public enum ConfigurationLoadResult: Equatable, Sendable {
    case loaded(AppConfiguration)
    case missing
    case corrupt(reason: String)
    case unsupportedVersion(Int)
}

public enum ConfigurationError: Error, Equatable, Sendable {
    case encodingFailed(String)
}

/// Validates and migrates the persisted configuration.
///
/// Unknown schema versions are rejected instead of being silently rewritten,
/// and corrupt payloads are reported so the caller can preserve a backup before
/// starting over.
public enum ConfigurationCoder {
    public static func decode(_ data: Data) -> ConfigurationLoadResult {
        struct VersionProbe: Decodable {
            let schemaVersion: Int?
        }

        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return .corrupt(reason: "not-json")
        }
        let version = probe.schemaVersion ?? 0
        guard version == AppConfiguration.currentSchemaVersion else {
            return .unsupportedVersion(version)
        }
        guard let decoded = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .corrupt(reason: "invalid-fields")
        }
        return .loaded(sanitize(decoded))
    }

    public static func encode(_ configuration: AppConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(sanitize(configuration))
        } catch {
            throw ConfigurationError.encodingFailed(error.localizedDescription)
        }
    }

    /// Deduplicates devices, trims names and drops entries that cannot be
    /// represented safely. Sanitizing on both read and write keeps a
    /// hand-edited file from producing duplicate per-device actors.
    public static func sanitize(_ configuration: AppConfiguration) -> AppConfiguration {
        var seen = Set<DeviceID>()
        var devices: [ManagedDevice] = []
        devices.reserveCapacity(configuration.devices.count)
        for var device in configuration.devices {
            guard !seen.contains(device.id) else { continue }
            seen.insert(device.id)
            let trimmed = device.cachedName.trimmingCharacters(in: .whitespacesAndNewlines)
            device.cachedName = trimmed.isEmpty ? device.id.address : String(trimmed.prefix(128))
            if let uid = device.policy.preferredAudioUID,
               uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                device.policy.preferredAudioUID = nil
            }
            devices.append(device)
        }
        return AppConfiguration(
            schemaVersion: AppConfiguration.currentSchemaVersion,
            isGloballyEnabled: configuration.isGloballyEnabled,
            devices: devices
        )
    }
}

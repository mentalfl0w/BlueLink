import Foundation
import BlueLinkCore

public enum ConfigurationStoreError: Error, Equatable, Sendable {
    case writeFailed(String)
    case archiveFailed(String)
}

/// File-backed configuration with atomic replacement.
///
/// Corrupt files are preserved as a timestamped backup before a fresh
/// configuration is written. Unknown schema versions are never overwritten;
/// the caller must present an explicit reset action.
public struct ConfigurationStore: Sendable {
    public let directory: URL
    public let fileURL: URL

    public init(directory: URL) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("config.json", isDirectory: false)
    }

    public static func defaultStore(fileManager: FileManager = .default) -> ConfigurationStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ConfigurationStore(directory: base.appendingPathComponent("BlueLink", isDirectory: true))
    }

    public func load(fileManager: FileManager = .default) -> ConfigurationLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else {
            return .corrupt(reason: "unreadable")
        }
        return ConfigurationCoder.decode(data)
    }

    public func save(_ configuration: AppConfiguration, fileManager: FileManager = .default) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try ConfigurationCoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigurationStoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Moves the unreadable file aside so a later save cannot destroy the only
    /// copy. Returns the backup location for diagnostics.
    @discardableResult
    public func archiveCorruptFile(fileManager: FileManager = .default) throws -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = directory.appendingPathComponent("config.corrupt-\(stamp).json", isDirectory: false)
        do {
            try fileManager.moveItem(at: fileURL, to: backup)
            return backup
        } catch {
            throw ConfigurationStoreError.archiveFailed(error.localizedDescription)
        }
    }
}

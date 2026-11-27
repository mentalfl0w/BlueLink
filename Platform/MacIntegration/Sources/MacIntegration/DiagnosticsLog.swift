import Foundation
import os

public enum DiagnosticsCategory: String, Sendable, CaseIterable {
    case system
    case bluetooth
    case coordinator
    case audio
    case update
    case configuration
}

public struct DiagnosticsEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let category: DiagnosticsCategory
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), category: DiagnosticsCategory, message: String) {
        self.id = id
        self.date = date
        self.category = category
        self.message = message
    }
}

/// Bounded, in-memory recent history plus OSLog. Nothing is uploaded.
@MainActor
public final class DiagnosticsLog {
    private let capacity: Int
    private var entries: [DiagnosticsEntry] = []
    private let loggers: [DiagnosticsCategory: Logger]

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
        var loggers: [DiagnosticsCategory: Logger] = [:]
        for category in DiagnosticsCategory.allCases {
            loggers[category] = Logger(subsystem: "dev.bluelink.mac", category: category.rawValue)
        }
        self.loggers = loggers
    }

    public func record(_ category: DiagnosticsCategory, _ message: String, date: Date = Date()) {
        let sanitized = Sanitizer.sanitize(message)
        let entry = DiagnosticsEntry(date: date, category: category, message: sanitized)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        loggers[category]?.notice("\(sanitized, privacy: .public)")
    }

    public func recent(limit: Int = 50) -> [DiagnosticsEntry] {
        Array(entries.suffix(max(0, limit)).reversed())
    }

    public func exportText(header: String) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header, ""]
        for entry in entries.reversed() {
            lines.append("\(formatter.string(from: entry.date)) [\(entry.category.rawValue)] \(entry.message)")
        }
        return Sanitizer.sanitize(lines.joined(separator: "\n"))
    }
}

public enum Sanitizer {
    private static let addressPattern = try! NSRegularExpression(
        pattern: #"([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}"#
    )
    private static let homePattern = try! NSRegularExpression(pattern: #"/Users/[^/\s]+"#)

    /// Removes Bluetooth addresses, user home paths, and line breaks from a log
    /// message. Deliberately conservative: diagnostics must never contain
    /// device identifiers that can be used to track the user.
    public static func sanitize(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        var result = singleLine
        for pattern in [addressPattern, homePattern] {
            let range = NSRange(result.startIndex..., in: result)
            let replacement = pattern === addressPattern ? "<bluetooth-address>" : "~"
            result = pattern.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        return String(result.prefix(600))
    }
}

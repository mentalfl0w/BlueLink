import Foundation

public enum UpdateCheckError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case invalidResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Update channel not configured"
        case .invalidResponse:
            "Invalid update response"
        case .network(let message):
            "Network error: \(message)"
        }
    }
}

public struct UpdateRelease: Equatable, Sendable {
    public var version: String
    public var name: String
    public var notes: String
    public var pageURL: URL

    public init(version: String, name: String, notes: String, pageURL: URL) {
        self.version = version
        self.name = name
        self.notes = notes
        self.pageURL = pageURL
    }
}

/// GitHub Releases check. Disabled unless a repository is configured in the
/// bundle; the app never invents a remote endpoint. No silent installation.
public struct UpdateChecker: Sendable {
    public let repository: String?

    public init(repository: String?) {
        self.repository = repository?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func latestRelease(currentVersion: String) async throws -> UpdateRelease? {
        guard let repository else { throw UpdateCheckError.notConfigured }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20") else {
            throw UpdateCheckError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BlueLink-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateCheckError.invalidResponse
            }
            return Self.newestRelease(from: data, currentVersion: currentVersion)
        } catch let error as UpdateCheckError where error != .notConfigured {
            return try await latestReleaseFromWebPage(currentVersion: currentVersion)
        } catch {
            throw UpdateCheckError.network(error.localizedDescription)
        }
    }

    /// GitHub's release page redirects to the latest published tag and is not
    /// subject to the unauthenticated API rate limit. It is a fallback only;
    /// the API supplies release notes when it is available.
    private func latestReleaseFromWebPage(currentVersion: String) async throws -> UpdateRelease? {
        guard let repository,
              let url = URL(string: "https://github.com/\(repository)/releases/latest") else {
            throw UpdateCheckError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("BlueLink-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let finalURL = http.url,
              let tag = Self.tagName(fromReleaseURL: finalURL) else {
            throw UpdateCheckError.invalidResponse
        }
        let number = VersionNumber(tag)
        guard number > VersionNumber(currentVersion) else { return nil }
        return UpdateRelease(
            version: number.description,
            name: number.description,
            notes: "",
            pageURL: finalURL
        )
    }

    static func tagName(fromReleaseURL url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            return nil
        }
        let tag = components[tagIndex + 1]
        return tag.isEmpty ? nil : tag
    }

    /// Pure parser shared with tests.
    public static func newestRelease(from data: Data, currentVersion: String) -> UpdateRelease? {
        struct Release: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
            let draft: Bool
            let prerelease: Bool
        }
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else {
            return nil
        }
        let current = VersionNumber(currentVersion)
        return releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { release -> (UpdateRelease, VersionNumber)? in
                guard let pageURL = URL(string: release.html_url) else { return nil }
                let number = VersionNumber(release.tag_name)
                guard number > current else { return nil }
                return (
                    UpdateRelease(
                        version: number.description,
                        name: release.name ?? number.description,
                        notes: release.body ?? "",
                        pageURL: pageURL
                    ),
                    number
                )
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}

/// Small semantic-version comparison for `1.2.3` and `v1.2.3` tags. Missing
/// components compare as zero, and non-numeric suffixes are ignored.
struct VersionNumber: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]
    let prerelease: String?

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let pieces = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces.first.map(String.init) ?? withoutPrefix
        prerelease = pieces.count > 1 && !pieces[1].isEmpty ? String(pieces[1]) : nil
        components = core.split(separator: ".").map { piece in
            Int(piece.prefix { $0.isNumber }) ?? 0
        }
    }

    var description: String {
        let base = components.map(String.init).joined(separator: ".")
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left < right
        }
    }

    static func == (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

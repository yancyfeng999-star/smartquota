import Foundation

/// Semantic-ish app version (`major.minor.patch`) used for free update checks.
public struct AppVersion: Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `0.3.4`, `v0.3.4`, `mac-v0.3.4`, `mac-0.3.4`. Returns nil for Windows tags or junk.
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("windows") { return nil }

        var s = trimmed
        if lower.hasPrefix("mac-") {
            s = String(s.dropFirst(4))
        }
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }

        // Drop pre-release / build metadata: 0.3.4-beta.1 → 0.3.4
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<cut])
        }

        let parts = s.split(separator: ".").map(String.init)
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        let patch = parts.count == 3 ? (Int(parts[2]) ?? 0) : 0
        guard major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Helpers for classifying GitHub release tags / assets.
public enum ReleaseTagClassifier: Sendable {
    public static func isWindowsTag(_ tag: String) -> Bool {
        tag.lowercased().hasPrefix("windows")
    }

    /// Mac candidate: not Windows, and either has Mac installer assets or a normal version tag.
    public static func isMacCandidate(tag: String, assetNames: [String]) -> Bool {
        if isWindowsTag(tag) { return false }
        if AppVersion(string: tag) == nil { return false }
        let names = assetNames.map { $0.lowercased() }
        let hasMacInstaller = names.contains { name in
            name.hasSuffix(".dmg") || name.hasSuffix(".pkg") || name.hasSuffix(".zip")
        }
        // Version-only tags like v0.3.2 (historical Mac releases) still count.
        return hasMacInstaller || tag.lowercased().hasPrefix("v") || tag.lowercased().hasPrefix("mac")
    }
}

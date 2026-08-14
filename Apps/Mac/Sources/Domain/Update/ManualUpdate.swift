import Foundation

/// A remote release discovered via public GitHub Releases.
/// Install is still **user-triggered** (tap check, then confirm download/install).
/// Preferred asset is `.pkg`; `.dmg` is the fallback.
public struct RemoteRelease: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let htmlURL: URL
    /// Preferred installer download if present (prefer `.pkg`); otherwise nil → open release page.
    public let downloadURL: URL?
    public let releaseNotes: String
    public let publishedAt: Date?
    public let minimumOS: OperatingSystemVersion?
    public let assetSize: Int64?
    public let sha256: String?

    public init(
        version: AppVersion,
        tagName: String,
        htmlURL: URL,
        downloadURL: URL?,
        releaseNotes: String = "",
        publishedAt: Date? = nil,
        minimumOS: OperatingSystemVersion? = nil,
        assetSize: Int64? = nil,
        sha256: String? = nil
    ) {
        self.version = version
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.publishedAt = publishedAt
        self.minimumOS = minimumOS
        self.assetSize = assetSize
        self.sha256 = sha256
    }

    /// Best URL to open when the user taps “download” but no installer can be fetched.
    public var openURL: URL {
        downloadURL ?? htmlURL
    }

    public static func == (lhs: RemoteRelease, rhs: RemoteRelease) -> Bool {
        lhs.version == rhs.version
            && lhs.tagName == rhs.tagName
            && lhs.htmlURL == rhs.htmlURL
            && lhs.downloadURL == rhs.downloadURL
            && lhs.releaseNotes == rhs.releaseNotes
            && lhs.publishedAt == rhs.publishedAt
            && OSVersionOrdering.equals(lhs.minimumOS, rhs.minimumOS)
            && lhs.assetSize == rhs.assetSize
            && lhs.sha256 == rhs.sha256
    }
}

/// Result of a **manual** update check (version compare only; no background polling).
public enum ManualUpdateResult: Equatable, Sendable {
    case upToDate(current: AppVersion)
    case updateAvailable(current: AppVersion, latest: RemoteRelease)
}

/// Eligibility after a check: notes may be shown even when download is blocked.
public enum ManualUpdateAssessment: Sendable, Equatable {
    case upToDate(current: AppVersion)
    case available(current: AppVersion, latest: RemoteRelease)
    case unsupportedOS(
        current: AppVersion,
        latest: RemoteRelease,
        required: OperatingSystemVersion,
        running: OperatingSystemVersion
    )
    case missingAsset(current: AppVersion, latest: RemoteRelease)
    case missingChecksum(current: AppVersion, latest: RemoteRelease)

    public var allowsDownload: Bool {
        if case .available = self { return true }
        return false
    }

    public var shouldOpenReleasePage: Bool {
        switch self {
        case .missingAsset, .missingChecksum:
            return true
        default:
            return false
        }
    }

    public var latestRelease: RemoteRelease? {
        switch self {
        case .upToDate:
            return nil
        case .available(_, let latest),
             .unsupportedOS(_, let latest, _, _),
             .missingAsset(_, let latest),
             .missingChecksum(_, let latest):
            return latest
        }
    }

    public var currentVersion: AppVersion {
        switch self {
        case .upToDate(let current),
             .available(let current, _),
             .unsupportedOS(let current, _, _, _),
             .missingAsset(let current, _),
             .missingChecksum(let current, _):
            return current
        }
    }

    public static func == (lhs: ManualUpdateAssessment, rhs: ManualUpdateAssessment) -> Bool {
        switch (lhs, rhs) {
        case let (.upToDate(a), .upToDate(b)):
            return a == b
        case let (.available(c1, r1), .available(c2, r2)):
            return c1 == c2 && r1 == r2
        case let (.unsupportedOS(c1, r1, req1, run1), .unsupportedOS(c2, r2, req2, run2)):
            return c1 == c2
                && r1 == r2
                && OSVersionOrdering.equals(req1, req2)
                && OSVersionOrdering.equals(run1, run2)
        case let (.missingAsset(c1, r1), .missingAsset(c2, r2)):
            return c1 == c2 && r1 == r2
        case let (.missingChecksum(c1, r1), .missingChecksum(c2, r2)):
            return c1 == c2 && r1 == r2
        default:
            return false
        }
    }
}

/// Fields shown after a check completes (current / new / date / notes / size / min OS).
public struct UpdateDetailsSnapshot: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String?
    public let publishedAt: Date?
    public let releaseNotes: String
    public let assetSize: Int64?
    public let minimumOSLabel: String?
    public let allowsDownload: Bool
    public let shouldOpenReleasePage: Bool

    public init(
        currentVersion: String,
        latestVersion: String?,
        publishedAt: Date?,
        releaseNotes: String,
        assetSize: Int64?,
        minimumOSLabel: String?,
        allowsDownload: Bool,
        shouldOpenReleasePage: Bool
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.publishedAt = publishedAt
        self.releaseNotes = releaseNotes
        self.assetSize = assetSize
        self.minimumOSLabel = minimumOSLabel
        self.allowsDownload = allowsDownload
        self.shouldOpenReleasePage = shouldOpenReleasePage
    }

    public static func make(
        assessment: ManualUpdateAssessment,
        fallbackMinimumMajor: Int = CompatibilityOSPolicy.minimumMajorVersion
    ) -> UpdateDetailsSnapshot {
        let latest = assessment.latestRelease
        let minLabel: String?
        if let os = latest?.minimumOS {
            minLabel = OSVersionOrdering.displayString(os)
        } else if latest != nil || assessment.allowsDownload == false {
            minLabel = "\(fallbackMinimumMajor).0"
        } else {
            minLabel = "\(fallbackMinimumMajor).0"
        }
        return UpdateDetailsSnapshot(
            currentVersion: assessment.currentVersion.description,
            latestVersion: latest?.version.description,
            publishedAt: latest?.publishedAt,
            releaseNotes: latest?.releaseNotes ?? "",
            assetSize: latest?.assetSize,
            minimumOSLabel: minLabel,
            allowsDownload: assessment.allowsDownload,
            shouldOpenReleasePage: assessment.shouldOpenReleasePage
        )
    }
}

public enum ManualUpdateError: Error, Equatable, Sendable {
    case invalidCurrentVersion
    case noMacReleaseFound
    case network(String)
    case decode(String)
    /// Silent pkg install failed (expand/copy/installer). Current app is left in place.
    case install(String)
    case unsupportedOperatingSystem(required: String, current: String)
    case missingReleaseAsset
    case missingChecksum
    case checksumMismatch
    case downloadCancelled
    case downloadTimeout
    case downloadTooLarge(maxBytes: Int64)
    case targetNotNewer
}

/// Limits for a user-triggered installer download.
public enum ReleaseDownloadPolicy: Sendable {
    public static let maxBytes: Int64 = 200 * 1_024 * 1_024
    public static let timeout: TimeInterval = 120

    public static func isInstallerURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".pkg") || path.hasSuffix(".dmg") || path.hasSuffix(".zip")
    }
}

/// Compare / format `OperatingSystemVersion` without retroactive Equatable.
public enum OSVersionOrdering: Sendable {
    public static func equals(_ lhs: OperatingSystemVersion?, _ rhs: OperatingSystemVersion?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return equals(a, b)
        default:
            return false
        }
    }

    public static func equals(_ lhs: OperatingSystemVersion, _ rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion == rhs.majorVersion
            && lhs.minorVersion == rhs.minorVersion
            && lhs.patchVersion == rhs.patchVersion
    }

    public static func isAscending(_ lhs: OperatingSystemVersion, _ rhs: OperatingSystemVersion) -> Bool {
        if lhs.majorVersion != rhs.majorVersion { return lhs.majorVersion < rhs.majorVersion }
        if lhs.minorVersion != rhs.minorVersion { return lhs.minorVersion < rhs.minorVersion }
        return lhs.patchVersion < rhs.patchVersion
    }

    public static func displayString(_ version: OperatingSystemVersion) -> String {
        if version.patchVersion == 0 {
            return "\(version.majorVersion).\(version.minorVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

/// Parse Release notes / SHA256SUMS / GitHub asset digest.
public enum ReleaseMetadataParser: Sendable {
    public static func minimumOS(from notes: String) -> OperatingSystemVersion? {
        let text = notes.replacingOccurrences(of: "*", with: "")
        let pattern = #"(?i)(?:最低\s*)?(?:minimum\s*)?mac\s*os(?:\s*版本)?\s*[:：]?\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard let majorRange = Range(match.range(at: 1), in: text),
              let major = Int(text[majorRange]) else { return nil }
        let minor = intGroup(match, at: 2, in: text) ?? 0
        let patch = intGroup(match, at: 3, in: text) ?? 0
        return OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    public static func sha256(fromGitHubDigest digest: String?) -> String? {
        guard let raw = digest?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        let hex: String
        if lower.hasPrefix("sha256:") {
            hex = String(lower.dropFirst(7))
        } else {
            hex = lower
        }
        return isSHA256Hex(hex) ? hex : nil
    }

    public static func sha256(fromChecksums text: String, matching names: [String]) -> String? {
        let wanted = Set(names.map { normalizedAssetName($0) }.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, isSHA256Hex(parts[0]) else { continue }
            let file = normalizedAssetName(parts.dropFirst().joined(separator: " "))
            if wanted.contains(file) {
                return parts[0].lowercased()
            }
        }
        return nil
    }

    public static func isSHA256Hex(_ value: String) -> Bool {
        let hex = value.lowercased()
        guard hex.count == 64 else { return false }
        return hex.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    public static func normalizedAssetName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .lowercased() ?? ""
    }

    private static func intGroup(_ match: NSTextCheckingResult, at index: Int, in text: String) -> Int? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }
}

/// Read a marketing version from an `.app` Info.plist (expanded pkg or installed bundle).
public enum InstalledAppVersion: Sendable {
    public static func read(fromAppBundle url: URL) -> AppVersion? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let raw = (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String)
        guard let raw else { return nil }
        return AppVersion(string: raw)
    }

    public static func read(from bundle: Bundle) -> AppVersion? {
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let raw else { return nil }
        return AppVersion(string: raw)
    }
}

/// Guard: never install unless the incoming bundle is strictly newer.
public enum UpdateInstallGuard: Sendable {
    public static func ensureTargetIsNewer(target: AppVersion, current: AppVersion) throws {
        guard target > current else {
            throw ManualUpdateError.targetNotNewer
        }
    }

    public static func verifyExpandedApp(_ appURL: URL, currentVersion: AppVersion) throws -> AppVersion {
        guard let first = InstalledAppVersion.read(fromAppBundle: appURL) else {
            throw ManualUpdateError.install("安装包内无法读取版本")
        }
        try ensureTargetIsNewer(target: first, current: currentVersion)
        guard let reread = InstalledAppVersion.read(fromAppBundle: appURL), reread == first else {
            throw ManualUpdateError.install("安装包版本校验失败")
        }
        return reread
    }
}

/// Pure evaluation: compare installed version with a candidate remote release.
public enum ManualUpdateEvaluator: Sendable {
    public static func evaluate(current: AppVersion, latest: RemoteRelease) -> ManualUpdateResult {
        if latest.version > current {
            return .updateAvailable(current: current, latest: latest)
        }
        return .upToDate(current: current)
    }

    /// Version + asset + checksum + minimum OS. Download is allowed only for `.available`.
    public static func assess(
        current: AppVersion,
        latest: RemoteRelease,
        runningOS: OperatingSystemVersion
    ) -> ManualUpdateAssessment {
        if latest.version <= current {
            return .upToDate(current: current)
        }
        let installer = preferredInstallerURL(from: latest)
        if installer == nil {
            return .missingAsset(current: current, latest: latest)
        }
        let checksum = latest.sha256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if checksum.isEmpty || !ReleaseMetadataParser.isSHA256Hex(checksum) {
            return .missingChecksum(current: current, latest: latest)
        }
        if let required = latest.minimumOS, OSVersionOrdering.isAscending(runningOS, required) {
            return .unsupportedOS(current: current, latest: latest, required: required, running: runningOS)
        }
        return .available(current: current, latest: latest)
    }

    public static func preferredInstallerURL(from release: RemoteRelease) -> URL? {
        if let download = release.downloadURL, ReleaseDownloadPolicy.isInstallerURL(download) {
            return download
        }
        return nil
    }

    /// Picks the highest-version Mac release from a list of candidates.
    public static func pickLatest(_ releases: [RemoteRelease]) -> RemoteRelease? {
        releases.max(by: { $0.version < $1.version })
    }

    /// Prefer pkg (one-click install), then dmg, then zip.
    /// Within the same type: ASCII `smartquota` name ranks above localized names.
    public static func preferredDownloadURL(assetNamesAndURLs: [(name: String, url: URL)]) -> URL? {
        let ranked = assetNamesAndURLs.compactMap { item -> (Int, URL)? in
            let name = item.name.lowercased()
            let asciiBoost = name.contains("smartquota") ? 0 : 1
            let score: Int
            if name.hasSuffix(".pkg") {
                score = 0 + asciiBoost // 0 or 1
            } else if name.hasSuffix(".dmg") {
                score = 10 + asciiBoost // 10 or 11
            } else if name.hasSuffix(".zip") {
                score = 20 + asciiBoost
            } else {
                return nil
            }
            return (score, item.url)
        }
        return ranked.sorted { $0.0 < $1.0 }.first?.1
    }
}

import Foundation

/// A remote release discovered via public GitHub Releases.
/// Install is still **user-triggered** (tap check/update); preferred asset is `.pkg` for one-click replace.
public struct RemoteRelease: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let htmlURL: URL
    /// Preferred installer download if present (prefer `.pkg`); otherwise nil → open release page.
    public let downloadURL: URL?

    public init(version: AppVersion, tagName: String, htmlURL: URL, downloadURL: URL?) {
        self.version = version
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.downloadURL = downloadURL
    }

    /// Best URL to open when the user taps “download”.
    public var openURL: URL {
        downloadURL ?? htmlURL
    }
}

/// Result of a **manual** update check (no background polling).
public enum ManualUpdateResult: Equatable, Sendable {
    case upToDate(current: AppVersion)
    case updateAvailable(current: AppVersion, latest: RemoteRelease)
}

public enum ManualUpdateError: Error, Equatable, Sendable {
    case invalidCurrentVersion
    case noMacReleaseFound
    case network(String)
    case decode(String)
    /// Silent pkg install failed (expand/copy/installer).
    case install(String)
}

/// Pure evaluation: compare installed version with a candidate remote release.
public enum ManualUpdateEvaluator: Sendable {
    public static func evaluate(current: AppVersion, latest: RemoteRelease) -> ManualUpdateResult {
        if latest.version > current {
            return .updateAvailable(current: current, latest: latest)
        }
        return .upToDate(current: current)
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

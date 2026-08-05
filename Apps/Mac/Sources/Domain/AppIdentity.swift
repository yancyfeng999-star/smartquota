import Foundation

/// Product identity shared across Domain / Infrastructure / App.
public enum AppIdentity: Sendable {
    public static let nameEN = "SmartQuota"
    public static let nameCN = "智额"
    public static let appBundleId = "com.smartquota.app"
    public static let subsystem = "com.smartquota.app"

    /// Public GitHub repo used for free manual update checks (Releases API).
    public static let githubOwner = "yancyfeng999-star"
    public static let githubRepo = "smartquota"

    public static var githubReleasesPageURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    }

    public static var githubReleasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases?per_page=30")!
    }

    /// Config dir: `~/.smartquota`
    public static let configDirName = ".smartquota"

    public static let logsDirName = "SmartQuota"
    public static let logFileName = "SmartQuota.log"

    public static let probeFolderName = "SmartQuota"
    public static let probeSubfolderName = "Probe"

    public static let hookMarker = "__smartquota_hook"
    public static let hookPortFileName = "smartquota-hook-port"

    public static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var configDirectoryURL: URL {
        homeDirectory.appendingPathComponent(configDirName, isDirectory: true)
    }

    public static var settingsFileURL: URL {
        configDirectoryURL.appendingPathComponent("settings.json")
    }

    public static var themesDirectoryURL: URL {
        configDirectoryURL.appendingPathComponent("themes", isDirectory: true)
    }

    public static var extensionsDirectoryURL: URL {
        configDirectoryURL.appendingPathComponent("extensions", isDirectory: true)
    }

    /// Ensures `~/.smartquota` exists.
    @discardableResult
    public static func ensureConfigDirectory() -> URL {
        let fm = FileManager.default
        let dir = configDirectoryURL
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Alias kept for call sites that previously used the migration helper name.
    @discardableResult
    public static func ensureConfigDirectoryMigrated() -> URL {
        ensureConfigDirectory()
    }
}

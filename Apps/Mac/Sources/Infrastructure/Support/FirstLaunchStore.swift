import Foundation
import Domain

/// Persists first-launch step completion under an injected config root.
/// Tests must pass a temp directory. Production must pass `AppIdentity`'s
/// config directory explicitly — this type never defaults to `~/.smartquota`.
public final class FirstLaunchStore: Sendable {
    public static let fileName = "first-launch.json"

    public let configRoot: URL

    public var fileURL: URL {
        configRoot.appendingPathComponent(Self.fileName)
    }

    public init(configRoot: URL) {
        self.configRoot = configRoot
    }

    /// Production entry. Caller must pass `AppIdentity.configDirectoryURL`
    /// (or `AppIdentity.ensureConfigDirectory()`) — never omit the path.
    public static func usingAppIdentity(_ configDirectory: URL) -> FirstLaunchStore {
        FirstLaunchStore(configRoot: configDirectory)
    }

    public func load() -> FirstLaunchState {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fresh
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FirstLaunchState.self, from: data)
        } catch {
            return .fresh
        }
    }

    public func save(_ state: FirstLaunchState) throws {
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

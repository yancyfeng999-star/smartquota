import Foundation
import Domain

/// Persists first-launch step completion under an injected config root.
/// Tests must pass a temp directory. Production must pass `AppIdentity`'s
/// config directory explicitly — this type never defaults to `~/.smartquota`.
///
/// Existence of `settings.json` / prior ready+clean markers is snapshotted
/// at init, before `migrateIfNeeded()` or `beginLaunch()` mutate the root.
public final class FirstLaunchStore: Sendable {
    public static let fileName = "first-launch.json"

    public let configRoot: URL
    private let settingsExistedAtInit: Bool
    private let priorReadyMarkerExisted: Bool
    private let priorCleanMarkerExisted: Bool

    public var fileURL: URL {
        configRoot.appendingPathComponent(Self.fileName)
    }

    public init(configRoot: URL) {
        self.configRoot = configRoot
        let fm = FileManager.default
        self.settingsExistedAtInit = fm.fileExists(
            atPath: configRoot.appendingPathComponent("settings.json").path
        )
        let recovery = configRoot.appendingPathComponent(
            CrashRecoveryMarker.directoryName,
            isDirectory: true
        )
        self.priorReadyMarkerExisted = fm.fileExists(
            atPath: recovery.appendingPathComponent(CrashRecoveryMarker.ready).path
        )
        self.priorCleanMarkerExisted = fm.fileExists(
            atPath: recovery.appendingPathComponent(CrashRecoveryMarker.clean).path
        )
    }

    /// Production entry. Caller must pass `AppIdentity.configDirectoryURL`
    /// (or `AppIdentity.ensureConfigDirectory()`) — never omit the path.
    public static func usingAppIdentity(_ configDirectory: URL) -> FirstLaunchStore {
        FirstLaunchStore(configRoot: configDirectory)
    }

    public func load() -> FirstLaunchState {
        let recorded = readRecord()
        let signals = FirstLaunchSignals(
            recordExists: recorded != nil,
            settingsFileExisted: settingsExistedAtInit,
            priorReadyMarkerExisted: priorReadyMarkerExisted,
            priorCleanMarkerExisted: priorCleanMarkerExisted
        )
        let state = FirstLaunchState.resolved(from: signals, recorded: recorded)
        if recorded == nil, state.isCompleted {
            try? save(state)
        }
        return state
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

    private func readRecord() -> FirstLaunchState? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FirstLaunchState.self, from: data)
        } catch {
            return nil
        }
    }
}

import Foundation
import Domain

/// On-disk names under `<configRoot>/recovery/`.
///
/// Task 8 hook: when `SettingsMigrationRunner.migrateIfNeeded()` throws, call
/// `recordMigrationFailure(_:)` (or write `migration-failed`) so the next
/// `beginLaunch()` enters `.safeMode(reason: .migrationFailed)`.
public enum CrashRecoveryMarker: Sendable {
    public static let directoryName = "recovery"
    public static let session = "session"
    public static let ready = "ready"
    public static let clean = "clean"
    public static let startupFailures = "startup-failures"
    public static let migrationFailed = "migration-failed"
    public static let corruptDirectoryName = "corrupt"
}

/// Session / ready / clean markers and Safe Mode recovery actions.
/// Always inject `configRoot` in tests — never the developer's real `~/.smartquota`.
public final class CrashRecoveryStore: @unchecked Sendable {
    public let configRoot: URL

    private let settingsStore: JSONSettingsStore
    private let backupManager: any BackupManaging
    private let lock = NSLock()
    private var _lastLaunchMode: AppLaunchMode = .normal
    private var _recordedMigrationBackupDirectory: URL?

    public init(
        configRoot: URL,
        settingsStore: JSONSettingsStore? = nil,
        backupManager: (any BackupManaging)? = nil
    ) {
        self.configRoot = configRoot
        self.settingsStore = settingsStore ?? JSONSettingsStore(
            fileURL: configRoot.appendingPathComponent("settings.json")
        )
        self.backupManager = backupManager ?? BackupManager(configRoot: configRoot)
    }

    public var lastLaunchMode: AppLaunchMode {
        lock.lock()
        defer { lock.unlock() }
        return _lastLaunchMode
    }

    public var hasSessionMarker: Bool { fileExists(sessionURL) }
    public var hasReadyMarker: Bool { fileExists(readyURL) }
    public var hasCleanMarker: Bool { fileExists(cleanURL) }
    public var hasMigrationFailureMarker: Bool { fileExists(migrationFailedURL) }

    public var startupFailureCount: Int { readFailureCount() }

    public var lastCorruptCopyURL: URL? { settingsStore.lastCorruptCopyURL }

    /// Pre-migration backup folder recorded when `migrateIfNeeded()` failed.
    public var recordedMigrationBackupDirectory: URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = _recordedMigrationBackupDirectory {
            return cached
        }
        let parsed = parseBackupDirectoryFromMarker()
        _recordedMigrationBackupDirectory = parsed
        return parsed
    }

    /// Reads previous markers, decides launch mode, then writes a new session marker.
    @discardableResult
    public func beginLaunch() -> AppLaunchMode {
        lock.lock()
        defer { lock.unlock() }

        let leftover = fileExists(sessionURL) && !fileExists(cleanURL)
        var count = readFailureCount()
        // Only a leftover session is an unclean failure. A first-ever launch
        // (no prior session, no clean marker) must not increment.
        if leftover {
            count += 1
            writeFailureCount(count)
        }

        let mode = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: leftover,
                settingsDecodeFailed: probeSettingsCorrupt(),
                migrationFailed: fileExists(migrationFailedURL),
                consecutiveUncleanLaunches: count
            )
        ).launchMode
        _lastLaunchMode = mode

        writeMarker(sessionURL)
        removeFile(cleanURL)
        removeFile(readyURL)
        return mode
    }

    public func markReady() {
        lock.lock()
        defer { lock.unlock() }
        writeMarker(readyURL)
    }

    /// Must run on the user-initiated quit path before the process dies.
    public func markCleanQuit() {
        lock.lock()
        defer { lock.unlock() }
        writeMarker(cleanURL)
        removeFile(sessionURL)
        removeFile(readyURL)
        writeFailureCount(0)
    }

    public func recordMigrationFailure(
        _ error: SettingsPersistenceError? = nil,
        backupDirectory: URL? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        let directory = backupDirectory
            ?? error?.backupDirectoryPath.map { URL(fileURLWithPath: $0) }
        _recordedMigrationBackupDirectory = directory

        var payload: [String: String] = [
            "code": error?.code ?? SafeModeReason.migrationFailed.rawValue,
        ]
        if let hint = error?.recoveryHint {
            payload["hint"] = hint
        }
        if let directory {
            payload["backupDirectory"] = directory.path
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            writeString(text, to: migrationFailedURL)
        } else {
            writeString(error?.code ?? SafeModeReason.migrationFailed.rawValue, to: migrationFailedURL)
        }
    }

    public func clearMigrationFailure() {
        lock.lock()
        defer { lock.unlock() }
        removeFile(migrationFailedURL)
        _recordedMigrationBackupDirectory = nil
    }

    public func restoreLatestBackup() throws {
        lock.lock()
        defer { lock.unlock() }

        let backups = try backupManager.listBackups()
        guard let latest = backups.first else {
            throw SettingsPersistenceError.backupNotFound
        }
        try backupManager.restore(latest)
        removeFile(migrationFailedURL)
        _recordedMigrationBackupDirectory = nil
        markRecoverySucceeded()
    }

    public func resetAppSettings() throws {
        lock.lock()
        defer { lock.unlock() }

        try settingsStore.replaceAll([
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
        ])
        removeFile(migrationFailedURL)
        _recordedMigrationBackupDirectory = nil
        markRecoverySucceeded()
    }

    public func exportAllowlistedSettings(to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        let payload = SettingsBackupPolicy.sanitizeDictionary(settingsStore.readAll())
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw SettingsPersistenceError.validationFailed("exported settings are not valid JSON")
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try SettingsFileIO.performAtomicWrite(data, to: url)
    }

    /// Re-evaluate without treating the current session as a previous crash.
    @discardableResult
    public func retryNormalLaunch() -> AppLaunchMode {
        lock.lock()
        defer { lock.unlock() }

        let mode = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: false,
                settingsDecodeFailed: probeSettingsCorrupt(),
                migrationFailed: fileExists(migrationFailedURL),
                consecutiveUncleanLaunches: 0
            )
        ).launchMode
        _lastLaunchMode = mode
        if !AppRecoveryState(launchMode: mode).isSafeMode {
            markRecoverySucceeded()
        }
        return mode
    }

    // MARK: - Paths

    public var recoveryDirectory: URL {
        configRoot.appendingPathComponent(CrashRecoveryMarker.directoryName, isDirectory: true)
    }

    private var sessionURL: URL {
        recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.session)
    }

    private var readyURL: URL {
        recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.ready)
    }

    private var cleanURL: URL {
        recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.clean)
    }

    private var startupFailuresURL: URL {
        recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.startupFailures)
    }

    private var migrationFailedURL: URL {
        recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.migrationFailed)
    }

    // MARK: - I/O

    private func parseBackupDirectoryFromMarker() -> URL? {
        guard let data = try? Data(contentsOf: migrationFailedURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["backupDirectory"] as? String,
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func probeSettingsCorrupt() -> Bool {
        do {
            _ = try settingsStore.readAllThrowing()
            return false
        } catch let error as SettingsPersistenceError {
            if case .corruptJSON = error { return true }
            return false
        } catch {
            return false
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func writeMarker(_ url: URL) {
        writeString(ISO8601DateFormatter().string(from: Date()), to: url)
    }

    private func writeFailureCount(_ count: Int) {
        writeString(String(count), to: startupFailuresURL)
    }

    private func readFailureCount() -> Int {
        guard let data = try? Data(contentsOf: startupFailuresURL),
              let text = String(data: data, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return max(0, value)
    }

    private func writeString(_ text: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try SettingsFileIO.performAtomicWrite(Data(text.utf8), to: url)
        } catch {
            // Marker I/O must not crash launch; next launch will re-evaluate leftovers.
        }
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Successful restore/reset/retry: next process start must not see a leftover session.
    private func markRecoverySucceeded() {
        writeMarker(cleanURL)
        removeFile(sessionURL)
        removeFile(readyURL)
        writeFailureCount(0)
    }
}

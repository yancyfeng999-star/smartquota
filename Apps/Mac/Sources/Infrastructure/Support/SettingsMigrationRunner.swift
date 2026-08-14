import Foundation
import Domain

/// Runs ordered settings schema steps on a copy, then atomically replaces the file.
public final class SettingsMigrationRunner: @unchecked Sendable {
    private let store: JSONSettingsStore
    private let backupManager: any BackupManaging
    private let steps: [any SettingsMigrationStep]
    private let currentVersion: Int
    private let fileIO: SettingsFileIO
    private let lock = NSLock()

    public init(
        store: JSONSettingsStore,
        backupManager: any BackupManaging,
        steps: [any SettingsMigrationStep] = [LegacySettingsToV1Step()],
        currentVersion: Int = SettingsSchema.currentVersion,
        fileIO: SettingsFileIO = .live
    ) {
        self.store = store
        self.backupManager = backupManager
        self.steps = steps
        self.currentVersion = currentVersion
        self.fileIO = fileIO
    }

    /// Migrates `settings.json` to `currentVersion` when needed.
    /// Returns the pre-mutation backup, or `nil` when already current.
    @discardableResult
    public func migrateIfNeeded() throws -> BackupManifest? {
        lock.lock()
        defer { lock.unlock() }

        let originalData = (try? Data(contentsOf: store.fileURL)) ?? Data()
        let originalDict: [String: Any]
        if originalData.isEmpty {
            originalDict = [:]
        } else {
            do {
                let json = try JSONSerialization.jsonObject(with: originalData)
                guard let dict = json as? [String: Any] else {
                    _ = try backupManager.createPreMutationBackup()
                    throw SettingsPersistenceError.corruptJSON(path: store.fileURL.path)
                }
                originalDict = dict
            } catch let error as SettingsPersistenceError {
                throw error
            } catch {
                _ = try backupManager.createPreMutationBackup()
                throw SettingsPersistenceError.corruptJSON(path: store.fileURL.path)
            }
        }

        let fromVersion = SettingsJSON.intValue(originalDict[SettingsSchema.versionKey]) ?? 0
        if fromVersion >= currentVersion {
            return nil
        }

        let backup = try backupManager.createPreMutationBackup()
        var working = originalDict
        var version = fromVersion

        while version < currentVersion {
            guard let step = steps.first(where: { $0.fromVersion == version }) else {
                throw SettingsPersistenceError.migrationFailed(
                    from: version,
                    to: currentVersion,
                    reason: "missing migration step from \(version)"
                )
            }
            do {
                working = try step.migrate(working)
            } catch let error as SettingsPersistenceError {
                throw error
            } catch {
                throw SettingsPersistenceError.migrationFailed(
                    from: step.fromVersion,
                    to: step.toVersion,
                    reason: error.localizedDescription
                )
            }
            version = step.toVersion
        }

        try SettingsValidator.validate(working, expectedVersion: currentVersion)
        guard JSONSerialization.isValidJSONObject(working) else {
            throw SettingsPersistenceError.validationFailed("migrated document is not valid JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: working, options: [.prettyPrinted, .sortedKeys])
        do {
            try fileIO.writeAtomically(data, store.fileURL)
        } catch let error as SettingsPersistenceError {
            throw error
        } catch {
            throw SettingsPersistenceError.writeFailed(error.localizedDescription)
        }
        return backup
    }
}

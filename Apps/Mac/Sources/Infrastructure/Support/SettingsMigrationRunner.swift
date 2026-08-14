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

    public private(set) var lastBackupDirectory: URL?

    public init(
        store: JSONSettingsStore,
        backupManager: any BackupManaging,
        steps: [any SettingsMigrationStep] = SettingsMigrationCatalog.orderedSteps,
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

        lastBackupDirectory = nil
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
        if let manager = backupManager as? BackupManager {
            lastBackupDirectory = manager.directoryURL(for: backup)
        }

        var didReplaceLiveFile = false
        do {
            var working = originalDict
            var version = fromVersion

            while version < currentVersion {
                guard let step = steps.first(where: { $0.fromVersion == version }) else {
                    throw annotate(
                        SettingsPersistenceError.migrationFailed(
                            from: version,
                            to: currentVersion,
                            reason: "missing migration step from \(version)"
                        )
                    )
                }
                do {
                    working = try step.migrate(working)
                } catch let error as SettingsPersistenceError {
                    throw annotate(error)
                } catch {
                    throw annotate(
                        SettingsPersistenceError.migrationFailed(
                            from: step.fromVersion,
                            to: step.toVersion,
                            reason: error.localizedDescription
                        )
                    )
                }
                guard step.toVersion == version + 1 else {
                    throw annotate(
                        SettingsPersistenceError.migrationFailed(
                            from: step.fromVersion,
                            to: step.toVersion,
                            reason: "migration steps must advance one version at a time"
                        )
                    )
                }
                version = step.toVersion
            }

            try SettingsValidator.validate(working, expectedVersion: currentVersion)
            guard JSONSerialization.isValidJSONObject(working) else {
                throw annotate(
                    SettingsPersistenceError.validationFailed("migrated document is not valid JSON")
                )
            }
            let data = try JSONSerialization.data(withJSONObject: working, options: [.prettyPrinted, .sortedKeys])
            do {
                try fileIO.writeAtomically(data, store.fileURL)
                didReplaceLiveFile = true
            } catch let error as SettingsPersistenceError {
                throw annotate(error)
            } catch {
                throw annotate(SettingsPersistenceError.writeFailed(error.localizedDescription))
            }

            try validateFilePermissions()
            return backup
        } catch let error as SettingsPersistenceError {
            try restoreOrRethrow(
                originalData,
                didReplaceLiveFile: didReplaceLiveFile,
                originalError: error
            )
        } catch {
            try restoreOrRethrow(
                originalData,
                didReplaceLiveFile: didReplaceLiveFile,
                originalError: .migrationFailed(
                    from: fromVersion,
                    to: currentVersion,
                    reason: error.localizedDescription
                )
            )
        }
    }

    private func validateFilePermissions() throws {
        let mode = try fileIO.posixPermissions(store.fileURL)
        if (mode & 0o777) != SettingsSchema.posixFilePermission {
            throw SettingsPersistenceError.validationFailed(
                "settings file permission \(String(mode, radix: 8)) != 0600"
            )
        }
    }

    private func annotate(_ error: SettingsPersistenceError) -> SettingsPersistenceError {
        guard let path = lastBackupDirectory?.path else { return error }
        return error.includingBackupDirectory(path)
    }

    private func restoreOrRethrow(
        _ originalData: Data,
        didReplaceLiveFile: Bool,
        originalError: SettingsPersistenceError
    ) throws -> Never {
        do {
            try restoreOriginalBytes(originalData)
        } catch {
            if didReplaceLiveFile {
                let detail = (error as? SettingsPersistenceError)?.errorDescription
                    ?? error.localizedDescription
                throw annotate(originalError.includingRestoreFailure(detail))
            }
        }
        throw annotate(originalError)
    }

    private func restoreOriginalBytes(_ data: Data) throws {
        try fileIO.writeAtomically(data, store.fileURL)
        let written = try Data(contentsOf: store.fileURL)
        guard written == data else {
            throw SettingsPersistenceError.writeFailed("restored settings bytes do not match the original")
        }
    }
}

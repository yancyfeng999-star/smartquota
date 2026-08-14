import Foundation
import Domain

/// Launch-time settings migration. Must run before Safe Mode evaluation so a
/// thrown `migrateIfNeeded()` becomes `.safeMode(reason: .migrationFailed)`.
public enum LaunchSettingsBootstrap: Sendable {
    @discardableResult
    public static func migrateThenBeginLaunch(
        runner: SettingsMigrationRunner,
        recovery: CrashRecoveryStore
    ) -> AppLaunchMode {
        do {
            _ = try runner.migrateIfNeeded()
            recovery.clearMigrationFailure()
        } catch let error as SettingsPersistenceError {
            recovery.recordMigrationFailure(error, backupDirectory: runner.lastBackupDirectory)
        } catch {
            recovery.recordMigrationFailure(
                .migrationFailed(
                    from: 0,
                    to: SettingsSchema.currentVersion,
                    reason: error.localizedDescription
                ),
                backupDirectory: runner.lastBackupDirectory
            )
        }
        return recovery.beginLaunch()
    }
}

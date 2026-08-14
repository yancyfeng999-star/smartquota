import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: Crash recovery and Safe Mode
///
/// Acceptance: settings corruption, migration failure, interrupted launch,
/// and a user-initiated clean quit each take the documented path.
@Suite("Feature: Recovery")
struct RecoverySpec {

    @Test
    func `corrupt settings enter read-only safe mode and keep original plus a copy`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        try RecoveryHarness.copyFixture("corrupted-settings.json", to: env.settingsURL)
        let original = try Data(contentsOf: env.settingsURL)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        let mode = store.beginLaunch()
        let state = AppRecoveryState(launchMode: mode)

        #expect(mode == .safeMode(reason: .settingsDecodeFailed))
        #expect(state.usesReadOnlyDefaultSettings)
        #expect(state.shouldLoadUserExtensions == false)
        #expect(state.shouldStartBackgroundRefresh == false)
        #expect(state.shouldStartHookService == false)
        #expect(try Data(contentsOf: env.settingsURL) == original)

        let copy = try #require(store.lastCorruptCopyURL)
        #expect(try Data(contentsOf: copy) == original)
        #expect(env.settingsStore.readAll().isEmpty)
    }

    @Test
    func `Task 8 migration-failed marker starts safe mode and leaves settings bytes unchanged`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        try RecoveryHarness.copyFixture("old-fields-settings.json", to: env.settingsURL)
        let original = try Data(contentsOf: env.settingsURL)

        // Task 8 should call recordMigrationFailure() when migrateIfNeeded() throws.
        // On-disk hook: <configRoot>/recovery/migration-failed
        let store = CrashRecoveryStore(configRoot: env.configRoot)
        store.recordMigrationFailure(
            .migrationFailed(from: 0, to: 1, reason: "simulated Task 8 failure")
        )
        #expect(FileManager.default.fileExists(atPath: env.migrationFailedURL.path))

        let mode = store.beginLaunch()
        #expect(mode == .safeMode(reason: .migrationFailed))
        #expect(AppRecoveryState(launchMode: mode).shouldStartHookService == false)
        #expect(try Data(contentsOf: env.settingsURL) == original)
    }

    @Test
    func `interrupted launch without ready marker is safe mode and skips extensions refresh and hooks`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        let crashed = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(crashed.beginLaunch() == .normal)

        let relaunch = CrashRecoveryStore(configRoot: env.configRoot)
        let mode = relaunch.beginLaunch()
        let state = AppRecoveryState(launchMode: mode)
        #expect(mode == .safeMode(reason: .previousLaunchDidNotFinish))
        #expect(state.shouldLoadUserExtensions == false)
        #expect(state.shouldStartBackgroundRefresh == false)
        #expect(state.shouldStartHookService == false)
    }

    @Test
    func `user-initiated clean quit writes a clean marker and the next launch is normal`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        let session = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(session.beginLaunch() == .normal)
        session.markReady()
        session.markCleanQuit()
        #expect(session.hasCleanMarker)
        #expect(session.hasSessionMarker == false)

        let next = CrashRecoveryStore(configRoot: env.configRoot)
        let mode = next.beginLaunch()
        #expect(mode == .normal)
        #expect(AppRecoveryState(launchMode: mode).shouldStartBackgroundRefresh)
    }

    @Test
    func `restore latest backup then retry returns to normal and keeps the backup`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        try """
        {"app":{"themeMode":"cli","language":"zh-Hans"},"schemaVersion":1}
        """.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        _ = try BackupManager(configRoot: env.configRoot).createPreMutationBackup()
        try Data("broken".utf8).write(to: env.settingsURL)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.beginLaunch() == .safeMode(reason: .settingsDecodeFailed))
        try store.restoreLatestBackup()
        #expect(store.retryNormalLaunch() == .normal)
        #expect((env.settingsStore.readAll()["app"] as? [String: Any])?["themeMode"] as? String == "cli")
        #expect(try BackupManager(configRoot: env.configRoot).listBackups().isEmpty == false)
    }

    @Test
    func `reset only rewrites 智额 config and leaves external CLI auth alone`() throws {
        let env = try RecoveryHarness.make()
        defer { env.cleanup() }

        try """
        {"app":{"themeMode":"dark"},"schemaVersion":1}
        """.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let cliHome = env.externalCLIHome.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: cliHome, withIntermediateDirectories: true)
        let auth = cliHome.appendingPathComponent("credentials.json")
        try Data("oauth-token".utf8).write(to: auth)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        _ = store.beginLaunch()
        try store.resetAppSettings()

        #expect(try Data(contentsOf: auth) == Data("oauth-token".utf8))
        #expect(env.settingsStore.readAll()["app"] == nil)
        #expect(store.retryNormalLaunch() == .normal)
    }
}

private enum RecoveryHarness {
    struct Env {
        let parent: URL
        let configRoot: URL
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        var settingsStore: JSONSettingsStore { JSONSettingsStore(fileURL: settingsURL) }
        var externalCLIHome: URL { parent.appendingPathComponent("home", isDirectory: true) }
        var migrationFailedURL: URL {
            configRoot
                .appendingPathComponent(CrashRecoveryMarker.directoryName, isDirectory: true)
                .appendingPathComponent(CrashRecoveryMarker.migrationFailed)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    static func make() throws -> Env {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-recovery-spec-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("dot-smartquota", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(parent: parent, configRoot: root)
    }

    static func copyFixture(_ name: String, to destination: URL) throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/settings/\(name)")
        try FileManager.default.copyItem(at: fixture, to: destination)
    }
}

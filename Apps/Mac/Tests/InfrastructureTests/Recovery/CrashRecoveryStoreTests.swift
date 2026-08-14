import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("CrashRecoveryStore Tests")
struct CrashRecoveryStoreTests {

    @Test
    func `beginLaunch writes session marker and markReady writes ready marker`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.hasSessionMarker == false)
        #expect(store.hasReadyMarker == false)

        let mode = store.beginLaunch()
        #expect(mode == .normal)
        #expect(store.hasSessionMarker)
        #expect(store.hasReadyMarker == false)
        #expect(store.hasCleanMarker == false)

        store.markReady()
        #expect(store.hasReadyMarker)
        #expect(FileManager.default.fileExists(atPath: env.sessionURL.path))
        #expect(FileManager.default.fileExists(atPath: env.readyURL.path))
    }

    @Test
    func `interrupted launch without ready marker enters previous-launch safe mode`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let first = CrashRecoveryStore(configRoot: env.configRoot)
        _ = first.beginLaunch()
        #expect(first.hasSessionMarker)
        #expect(first.hasReadyMarker == false)

        let second = CrashRecoveryStore(configRoot: env.configRoot)
        let mode = second.beginLaunch()
        #expect(mode == .safeMode(reason: .previousLaunchDidNotFinish))
        #expect(second.lastLaunchMode == mode)
    }

    @Test
    func `crash after ready without clean quit is still unfinished launch`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let first = CrashRecoveryStore(configRoot: env.configRoot)
        _ = first.beginLaunch()
        first.markReady()

        let second = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(second.beginLaunch() == .safeMode(reason: .previousLaunchDidNotFinish))
    }

    @Test
    func `clean quit is not treated as a crash on next launch`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let first = CrashRecoveryStore(configRoot: env.configRoot)
        _ = first.beginLaunch()
        first.markReady()
        first.markCleanQuit()
        #expect(first.hasCleanMarker)
        #expect(first.hasSessionMarker == false)
        #expect(first.hasReadyMarker == false)

        let second = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(second.beginLaunch() == .normal)
    }

    @Test
    func `clean marker wins over leftover session files`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try FileManager.default.createDirectory(at: env.recoveryDir, withIntermediateDirectories: true)
        try Data("session".utf8).write(to: env.sessionURL)
        try Data("ready".utf8).write(to: env.readyURL)
        try Data("clean".utf8).write(to: env.cleanURL)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.beginLaunch() == .normal)
    }

    @Test
    func `three interrupted launches escalate to repeated startup failure`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        var lastMode: AppLaunchMode = .normal
        for _ in 0..<RecoverySignals.repeatedFailureThreshold {
            let store = CrashRecoveryStore(configRoot: env.configRoot)
            lastMode = store.beginLaunch()
        }
        #expect(lastMode == .safeMode(reason: .repeatedStartupFailure))
    }

    @Test
    func `clean quit resets the unclean-launch counter`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        for _ in 0..<(RecoverySignals.repeatedFailureThreshold - 1) {
            _ = CrashRecoveryStore(configRoot: env.configRoot).beginLaunch()
        }

        let recovered = CrashRecoveryStore(configRoot: env.configRoot)
        _ = recovered.beginLaunch()
        recovered.markReady()
        recovered.markCleanQuit()

        let next = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(next.beginLaunch() == .normal)
        #expect(next.startupFailureCount == 0)
    }

    @Test
    func `corrupt settings enter decode-failed safe mode and keep a copy`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let broken = Data("not valid json {{{".utf8)
        try broken.write(to: env.settingsURL)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.beginLaunch() == .safeMode(reason: .settingsDecodeFailed))

        let live = try Data(contentsOf: env.settingsURL)
        #expect(live == broken)

        let copyURL = try #require(store.lastCorruptCopyURL ?? env.settingsStore.lastCorruptCopyURL)
        #expect(FileManager.default.fileExists(atPath: copyURL.path))
        #expect(try Data(contentsOf: copyURL) == broken)
        #expect(env.settingsStore.readAll().isEmpty)
        #expect(env.settingsStore.lastError?.code == "settings.corrupt_json")
    }

    @Test
    func `migration failure marker is a Task 8 hook into safe mode`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let first = CrashRecoveryStore(configRoot: env.configRoot)
        first.recordMigrationFailure(
            SettingsPersistenceError.migrationFailed(from: 0, to: 1, reason: "step exploded")
        )
        #expect(first.hasMigrationFailureMarker)
        #expect(FileManager.default.fileExists(atPath: env.migrationFailedURL.path))

        let second = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(second.beginLaunch() == .safeMode(reason: .migrationFailed))
    }

    @Test
    func `restore latest backup then retry leaves normal mode and keeps backup`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try """
        {"app":{"themeMode":"dark","language":"en"},"schemaVersion":1}
        """.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let backup = BackupManager(configRoot: env.configRoot)
        _ = try backup.createPreMutationBackup()

        try Data("{".utf8).write(to: env.settingsURL)
        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.beginLaunch() == .safeMode(reason: .settingsDecodeFailed))

        try store.restoreLatestBackup()
        let afterRestore = env.settingsStore.readAll()
        #expect((afterRestore["app"] as? [String: Any])?["themeMode"] as? String == "dark")
        #expect(try backup.listBackups().count == 1)

        #expect(store.retryNormalLaunch() == .normal)
        #expect(store.lastLaunchMode == .normal)
    }

    @Test
    func `failed restore keeps safe mode`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try Data("{".utf8).write(to: env.settingsURL)
        let store = CrashRecoveryStore(configRoot: env.configRoot)
        #expect(store.beginLaunch() == .safeMode(reason: .settingsDecodeFailed))

        let error = #expect(throws: SettingsPersistenceError.self) {
            try store.restoreLatestBackup()
        }
        #expect(error == .backupNotFound)
        #expect(store.lastLaunchMode == .safeMode(reason: .settingsDecodeFailed))
        #expect(store.retryNormalLaunch() == .safeMode(reason: .settingsDecodeFailed))
    }

    @Test
    func `reset rewrites settings inside the injected root and never touches external CLI files`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try """
        {"app":{"themeMode":"dark"},"schemaVersion":1}
        """.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        _ = try BackupManager(configRoot: env.configRoot).createPreMutationBackup()

        let externalRoot = env.configRoot.deletingLastPathComponent().appendingPathComponent("fake-claude")
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let externalAuth = externalRoot.appendingPathComponent("auth.json")
        try Data("cli-secret".utf8).write(to: externalAuth)

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        _ = store.beginLaunch()
        try store.resetAppSettings()

        let reset = env.settingsStore.readAll()
        #expect(SettingsJSON.intValue(reset[SettingsSchema.versionKey]) == SettingsSchema.currentVersion)
        #expect(reset["app"] == nil)
        #expect(try BackupManager(configRoot: env.configRoot).listBackups().count == 1)
        #expect(try Data(contentsOf: externalAuth) == Data("cli-secret".utf8))
        #expect(store.retryNormalLaunch() == .normal)
    }

    @Test
    func `export writes allowlisted settings and omits secrets`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        env.settingsStore.write(value: "dark", key: "app.themeMode")
        env.settingsStore.write(value: "super-secret", key: "copilotToken")
        env.settingsStore.write(value: "cookie-value", key: "mimo.cookie")

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        let dest = env.configRoot.appendingPathComponent("export.json")
        try store.exportAllowlistedSettings(to: dest)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dest))
        let dict = try #require(json as? [String: Any])
        #expect(dict["copilotToken"] == nil)
        #expect(dict["mimo"] == nil)
        #expect((dict["app"] as? [String: Any])?["themeMode"] as? String == "dark")
    }

    @Test
    func `injected root never writes recovery markers into the default config directory`() throws {
        let defaultRecovery = AppIdentity.configDirectoryURL.appendingPathComponent(
            CrashRecoveryMarker.directoryName,
            isDirectory: true
        )
        let defaultSession = defaultRecovery.appendingPathComponent(CrashRecoveryMarker.session)
        let existedBefore = FileManager.default.fileExists(atPath: defaultRecovery.path)
        let sessionBefore = try? Data(contentsOf: defaultSession)

        let env = try makeEnv()
        defer { env.cleanup() }

        let store = CrashRecoveryStore(configRoot: env.configRoot)
        _ = store.beginLaunch()
        store.markReady()
        store.recordMigrationFailure()
        store.markCleanQuit()

        #expect(env.configRoot.path.contains(NSTemporaryDirectory()) || env.configRoot.path.contains("/tmp"))
        #expect(!env.configRoot.path.contains("/.smartquota"))

        if existedBefore {
            #expect((try? Data(contentsOf: defaultSession)) == sessionBefore)
        } else {
            #expect(!FileManager.default.fileExists(atPath: defaultRecovery.path))
        }
    }

    // MARK: - Helpers

    private struct Env {
        let configRoot: URL
        let settingsStore: JSONSettingsStore
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        var recoveryDir: URL {
            configRoot.appendingPathComponent(CrashRecoveryMarker.directoryName, isDirectory: true)
        }
        var sessionURL: URL { recoveryDir.appendingPathComponent(CrashRecoveryMarker.session) }
        var readyURL: URL { recoveryDir.appendingPathComponent(CrashRecoveryMarker.ready) }
        var cleanURL: URL { recoveryDir.appendingPathComponent(CrashRecoveryMarker.clean) }
        var migrationFailedURL: URL {
            recoveryDir.appendingPathComponent(CrashRecoveryMarker.migrationFailed)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: configRoot.deletingLastPathComponent())
        }
    }

    private func makeEnv() throws -> Env {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-recovery-test-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("dot-smartquota", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsURL = root.appendingPathComponent("settings.json")
        return Env(configRoot: root, settingsStore: JSONSettingsStore(fileURL: settingsURL))
    }
}

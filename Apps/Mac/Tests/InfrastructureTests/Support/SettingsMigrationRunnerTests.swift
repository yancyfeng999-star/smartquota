import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("SettingsMigrationRunner Tests")
struct SettingsMigrationRunnerTests {

    @Test
    func `old fixture upgrade keeps theme language order enabled plan renewal and refresh`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        var dict = try loadFixtureJSON("old-fields-settings.json")
        var app = dict["app"] as? [String: Any] ?? [:]
        app["membershipOrder"] = ["claude", "kimi"]
        dict["app"] = app
        var providers = dict["providers"] as? [String: Any] ?? [:]
        var claude = providers["claude"] as? [String: Any] ?? [:]
        claude["planLabel"] = "Pro 20X"
        claude["renewalDate"] = "2026-12-01"
        providers["claude"] = claude
        dict["providers"] = providers
        try writeJSON(dict, to: env.settingsURL)

        let repo = JSONSettingsRepository(store: env.store)
        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        let backup = try runner.migrateIfNeeded()
        #expect(backup != nil)

        #expect(repo.schemaVersion() == SettingsSchema.currentVersion)
        #expect(repo.themeMode() == "dark")
        #expect(repo.appLanguage() == "zh-Hans")
        #expect(repo.membershipOrder() == ["claude", "kimi"])
        #expect(repo.isEnabled(forProvider: "claude") == true)
        #expect(repo.planLabel(forProvider: "claude") == "Pro 20X")
        #expect(repo.renewalDate(forProvider: "claude") == "2026-12-01")
        #expect(repo.backgroundSyncInterval() == 900)
    }

    @Test
    func `migrate is idempotent on re-run`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)

        let first = try runner.migrateIfNeeded()
        #expect(first != nil)
        let afterFirst = try Data(contentsOf: env.settingsURL)

        let second = try runner.migrateIfNeeded()
        #expect(second == nil)
        let afterSecond = try Data(contentsOf: env.settingsURL)
        #expect(afterSecond == afterFirst)
        #expect(env.store.schemaVersion() == SettingsSchema.currentVersion)

        let listed = try env.backupManager.listBackups()
        #expect(listed.count == 1)
    }

    @Test
    func `unknown fields are preserved through migration`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("unknown-fields-settings.json", to: env.settingsURL)
        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        _ = try runner.migrateIfNeeded()

        let all = env.store.readAll()
        #expect(all["legacyRootKey"] as? String == "must-survive-migration")
        #expect(intValue(all["schemaVersion"]) == SettingsSchema.currentVersion)

        let app = try #require(all["app"] as? [String: Any])
        #expect(app["futureFeatureFlag"] as? String == "keep-me")
        let layout = try #require(app["experimentalLayout"] as? [String: Any])
        #expect(intValue(layout["columns"]) == 3)
        #expect(layout["density"] as? String == "compact")
        #expect(app["themeMode"] as? String == "system")
        #expect(app["language"] as? String == "en")

        let providers = try #require(all["providers"] as? [String: Any])
        let claude = try #require(providers["claude"] as? [String: Any])
        let meta = try #require(claude["unknownProviderMeta"] as? [String: Any])
        #expect(meta["source"] as? String == "legacy-import")
        #expect(intValue(meta["priority"]) == 1)
        #expect(claude["planLabel"] as? String == "Pro")
        #expect(claude["renewalDate"] as? String == "2026-12-01")
    }

    @Test
    func `migrate failure rolls back and leaves original bytes unchanged`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            steps: [FailingMigrationStep()]
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        if case .migrationFailed(let from, let to, _) = error {
            #expect(from == 0)
            #expect(to == 1)
        } else {
            Issue.record("expected migrationFailed, got \(String(describing: error))")
        }

        let after = try Data(contentsOf: env.settingsURL)
        #expect(after == originalBytes)
        #expect(try env.backupManager.listBackups().count == 1)
    }

    @Test
    func `write failure after migrate leaves original bytes unchanged`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        var io = SettingsFileIO.live
        io.writeAtomically = { _, _ in
            throw SettingsPersistenceError.writeFailed("simulated disk full")
        }
        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            fileIO: io
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        if case .writeFailed = error {
            // expected
        } else {
            Issue.record("expected writeFailed, got \(String(describing: error))")
        }

        let after = try Data(contentsOf: env.settingsURL)
        #expect(after == originalBytes)
    }

    @Test
    func `corrupt fixture is not overwritten and surfaces a recovery hint`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("corrupted-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        if case .corruptJSON = error {
            #expect(error?.recoveryHint.isEmpty == false)
            #expect(error?.code == "settings.corrupt_json")
        } else {
            Issue.record("expected corruptJSON, got \(String(describing: error))")
        }

        let after = try Data(contentsOf: env.settingsURL)
        #expect(after == originalBytes)
    }

    @Test
    func `empty fixture upgrades to current schema with defaults`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("empty-settings.json", to: env.settingsURL)
        let repo = JSONSettingsRepository(store: env.store)
        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        _ = try runner.migrateIfNeeded()

        #expect(repo.schemaVersion() == SettingsSchema.currentVersion)
        #expect(repo.themeMode() == "system")
        #expect(repo.appLanguage() == "zh-Hans")
        #expect(repo.membershipOrder() == [])
        #expect(repo.backgroundSyncInterval() == 900)
    }

    @Test
    func `repository export hook strips secrets`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        env.store.write(value: "dark", key: "app.themeMode")
        env.store.write(value: "secret-token", key: "copilotToken")
        let repo = JSONSettingsRepository(store: env.store)
        let exported = repo.exportAllowlistedSettings()
        #expect(exported["copilotToken"] == nil)
        #expect((exported["app"] as? [String: Any])?["themeMode"] as? String == "dark")
    }

    @Test
    func `three historical fixtures upgrade then rollback via backup`() throws {
        let fixtures = [
            "empty-settings.json",
            "old-fields-settings.json",
            "v1-settings.json",
        ]
        for name in fixtures {
            let env = try makeEnv()
            defer { env.cleanup() }

            try copyFixture(name, to: env.settingsURL)
            let originalBytes = try Data(contentsOf: env.settingsURL)
            let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
            let backup = try #require(try runner.migrateIfNeeded())

            #expect(env.store.schemaVersion() == SettingsSchema.currentVersion)
            let attrs = try FileManager.default.attributesOfItem(atPath: env.settingsURL.path)
            let perms = attrs[.posixPermissions] as? NSNumber
            #expect(perms?.uint16Value == UInt16(SettingsSchema.posixFilePermission))

            try env.backupManager.restore(backup)
            let restored = env.store.readAll()
            let restoredVersion = env.store.schemaVersion()
            #expect(restoredVersion < SettingsSchema.currentVersion)

            if name == "empty-settings.json" {
                #expect(originalBytes.isEmpty)
                #expect(restored[SettingsSchema.versionKey] == nil)
                #expect(restoredVersion == 0)
                #expect(restored["app"] == nil)
            } else if name == "v1-settings.json" {
                #expect(restoredVersion == 1)
            } else {
                #expect(restoredVersion == 0)
            }
        }
    }

    @Test
    func `v1 snapshot upgrades to current and keeps unknown fields`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("v1-settings.json", to: env.settingsURL)
        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        let backup = try runner.migrateIfNeeded()
        #expect(backup != nil)

        let all = env.store.readAll()
        #expect(intValue(all["schemaVersion"]) == SettingsSchema.currentVersion)
        #expect(all["legacyRootKey"] as? String == "v1-snapshot-must-survive")
        let app = try #require(all["app"] as? [String: Any])
        #expect(app["futureV2Flag"] as? String == "keep-through-v2")
        #expect(app["themeMode"] as? String == "cli")
        #expect(app["language"] as? String == "en")
        #expect((all["providers"] as? [String: Any]).flatMap { $0["claude"] as? [String: Any] }?["planLabel"] as? String == "Pro")
    }

    @Test
    func `missing intermediate step does not guess fields across versions`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("v1-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)
        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            steps: [LegacySettingsToV1Step()],
            currentVersion: 2
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        if case .migrationFailed(let from, let to, let reason) = error {
            #expect(from == 1)
            #expect(to == 2)
            #expect(reason.contains("missing migration step"))
            #expect(error?.recoveryHint.contains("backup") == true || error?.recoveryHint.contains("Backup") == true)
        } else {
            Issue.record("expected migrationFailed, got \(String(describing: error))")
        }
        #expect(try Data(contentsOf: env.settingsURL) == originalBytes)
    }

    @Test
    func `migrate failure restores original and names the backup directory`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            steps: [FailingMigrationStep()]
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        #expect(try Data(contentsOf: env.settingsURL) == originalBytes)
        let backupDir = try #require(runner.lastBackupDirectory)
        #expect(FileManager.default.fileExists(atPath: backupDir.path))
        #expect(error?.recoveryHint.contains(backupDir.path) == true)
        #expect(error?.backupDirectoryPath == backupDir.path)
    }

    @Test
    func `permission failure after write restores original bytes`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        var io = SettingsFileIO.live
        io.posixPermissions = { _ in 0o644 }
        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            fileIO: io
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        if case .validationFailed(let reason) = error {
            #expect(reason.contains("permission") || reason.contains("0600"))
        } else {
            Issue.record("expected validationFailed, got \(String(describing: error))")
        }
        #expect(try Data(contentsOf: env.settingsURL) == originalBytes)
    }

    @Test
    func `restore failure after replace does not claim the original was restored`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)

        let writes = WriteCounter()
        var io = SettingsFileIO.live
        io.writeAtomically = { data, url in
            writes.count += 1
            if writes.count == 1 {
                try SettingsFileIO.performAtomicWrite(data, to: url)
                return
            }
            throw SettingsPersistenceError.writeFailed("restore disk full")
        }
        io.posixPermissions = { _ in 0o644 }
        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            fileIO: io
        )

        let error = #expect(throws: SettingsPersistenceError.self) {
            try runner.migrateIfNeeded()
        }
        let after = try Data(contentsOf: env.settingsURL)
        #expect(after != originalBytes)
        #expect(env.store.schemaVersion() == SettingsSchema.currentVersion)
        #expect(error?.recoveryHint.contains("could not be restored") == true)
        #expect(error?.recoveryHint.localizedCaseInsensitiveContains("the original file was restored") == false)
        #expect(error?.backupDirectoryPath != nil)
    }

    @Test
    func `launch bootstrap records migration failure for Safe Mode`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("old-fields-settings.json", to: env.settingsURL)
        let originalBytes = try Data(contentsOf: env.settingsURL)
        let recovery = CrashRecoveryStore(configRoot: env.configRoot, settingsStore: env.store)
        let runner = SettingsMigrationRunner(
            store: env.store,
            backupManager: env.backupManager,
            steps: [FailingMigrationStep()]
        )

        let mode = LaunchSettingsBootstrap.migrateThenBeginLaunch(runner: runner, recovery: recovery)
        #expect(mode == .safeMode(reason: .migrationFailed))
        #expect(recovery.hasMigrationFailureMarker)
        #expect(recovery.recordedMigrationBackupDirectory != nil)
        #expect(try Data(contentsOf: env.settingsURL) == originalBytes)
    }

    @Test
    func `launch bootstrap clears a previous migration marker after success`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try copyFixture("v1-settings.json", to: env.settingsURL)
        let recovery = CrashRecoveryStore(configRoot: env.configRoot, settingsStore: env.store)
        recovery.recordMigrationFailure(.migrationFailed(from: 1, to: 2, reason: "stale"))
        #expect(recovery.hasMigrationFailureMarker)

        let runner = SettingsMigrationRunner(store: env.store, backupManager: env.backupManager)
        let mode = LaunchSettingsBootstrap.migrateThenBeginLaunch(runner: runner, recovery: recovery)
        #expect(mode == .normal)
        #expect(recovery.hasMigrationFailureMarker == false)
        #expect(env.store.schemaVersion() == SettingsSchema.currentVersion)
    }

    // MARK: - Helpers

    private struct Env {
        let configRoot: URL
        let store: JSONSettingsStore
        let backupManager: BackupManager
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-migrate-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = JSONSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let backups = BackupManager(configRoot: root, appVersion: "0.3.28")
        return Env(configRoot: root, store: store, backupManager: backups)
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/settings", isDirectory: true)
    }

    private func copyFixture(_ name: String, to dest: URL) throws {
        try FileManager.default.copyItem(at: fixturesDirectory().appendingPathComponent(name), to: dest)
    }

    private func loadFixtureJSON(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent(name))
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    private func writeJSON(_ dict: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

private final class WriteCounter: @unchecked Sendable {
    var count = 0
}

private struct FailingMigrationStep: SettingsMigrationStep {
    var fromVersion: Int { 0 }
    var toVersion: Int { 1 }

    func migrate(_ input: [String: Any]) throws -> [String: Any] {
        throw SettingsPersistenceError.migrationFailed(from: 0, to: 1, reason: "forced failure")
    }
}

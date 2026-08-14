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

private struct FailingMigrationStep: SettingsMigrationStep {
    var fromVersion: Int { 0 }
    var toVersion: Int { 1 }

    func migrate(_ input: [String: Any]) throws -> [String: Any] {
        throw SettingsPersistenceError.migrationFailed(from: 0, to: 1, reason: "forced failure")
    }
}

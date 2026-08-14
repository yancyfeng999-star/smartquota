import Testing
import Foundation
import CryptoKit
@testable import Domain
@testable import Infrastructure

@Suite("BackupManager Tests")
struct BackupManagerTests {

    // MARK: - Checksum reject

    @Test
    func `restore rejects backup when checksum does not match and leaves live settings unchanged`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let original = """
        {"app":{"themeMode":"dark","language":"en"},"schemaVersion":1}
        """
        try original.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let liveBytesBefore = try Data(contentsOf: env.settingsURL)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        let backupSettings = try backupFileURL(root: env.configRoot, named: "settings.json")
        try "tampered-bytes".write(to: backupSettings, atomically: true, encoding: .utf8)

        let error = #expect(throws: SettingsPersistenceError.self) {
            try manager.restore(manifest)
        }
        if case .checksumMismatch(let file) = error {
            #expect(file == "settings.json")
        } else {
            Issue.record("expected checksumMismatch, got \(String(describing: error))")
        }

        let liveBytesAfter = try Data(contentsOf: env.settingsURL)
        #expect(liveBytesAfter == liveBytesBefore)
    }

    // MARK: - Layout and checksum

    @Test
    func `createPreMutationBackup writes timestamped folder with manifest and sha256`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let json = """
        {
          "app": {
            "themeMode": "dark",
            "language": "zh-Hans",
            "membershipOrder": ["claude"],
            "backgroundSyncInterval": 900
          },
          "providers": {
            "claude": {
              "isEnabled": true,
              "planLabel": "Pro",
              "renewalDate": "2026-12-01"
            }
          },
          "schemaVersion": 1
        }
        """
        try json.write(to: env.settingsURL, atomically: true, encoding: .utf8)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        #expect(manifest.appVersion == "0.3.28")
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.includedFiles == ["settings.json"])
        #expect(manifest.sha256["settings.json"] != nil)

        let backupDir = try backupDirectory(root: env.configRoot)
        let settingsCopy = backupDir.appendingPathComponent("settings.json")
        let manifestURL = backupDir.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: settingsCopy.path))
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let copyData = try Data(contentsOf: settingsCopy)
        let digest = SHA256.hash(data: copyData).map { String(format: "%02x", $0) }.joined()
        #expect(manifest.sha256["settings.json"] == digest)
    }

    @Test
    func `backup allowlist drops unknown extra keys from fixture`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/settings/unknown-fields-settings.json")
        try FileManager.default.copyItem(at: fixture, to: env.settingsURL)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        _ = try manager.createPreMutationBackup()

        let backup = try storeDictionary(at: try backupFileURL(root: env.configRoot, named: "settings.json"))
        let keys = allKeys(backup)
        #expect(!keys.contains("legacyRootKey"))
        #expect(!keys.contains("futureFeatureFlag"))
        #expect(!keys.contains("experimentalLayout"))
        #expect(!keys.contains("unknownProviderMeta"))
        #expect(backup["legacyRootKey"] == nil)

        #expect(SettingsJSON.intValue(backup["schemaVersion"]) == 0)
        let app = try #require(backup["app"] as? [String: Any])
        #expect(app["themeMode"] as? String == "system")
        #expect(app["language"] as? String == "en")
        #expect(app["usageDisplayMode"] as? String == "remaining")
        #expect(app["futureFeatureFlag"] == nil)
        #expect(app["experimentalLayout"] == nil)

        let claude = try #require((backup["providers"] as? [String: Any])?["claude"] as? [String: Any])
        #expect(claude["isEnabled"] as? Bool == true)
        #expect(claude["planLabel"] as? String == "Pro")
        #expect(claude["renewalDate"] as? String == "2026-12-01")
        #expect(claude["unknownProviderMeta"] == nil)

        let live = try storeDictionary(at: env.settingsURL)
        #expect(live["legacyRootKey"] as? String == "must-survive-migration")
    }

    @Test
    func `backup keeps cookieSource enums and drops actual cookies tokens passwords and api keys`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let json = """
        {
          "schemaVersion": 1,
          "app": { "themeMode": "dark" },
          "mimo": { "cookieSource": "auto" },
          "alibaba": { "cookieSource": "manual", "region": "international" },
          "claude": { "probeMode": "cli" },
          "copilotToken": "ghp_should-not-be-backed-up",
          "sessionCookie": "cookie-secret",
          "apiKey": "sk-secret",
          "password": "hunter2"
        }
        """
        try json.write(to: env.settingsURL, atomically: true, encoding: .utf8)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        _ = try manager.createPreMutationBackup()

        let backup = try storeDictionary(at: try backupFileURL(root: env.configRoot, named: "settings.json"))
        #expect((backup["mimo"] as? [String: Any])?["cookieSource"] as? String == "auto")
        #expect((backup["alibaba"] as? [String: Any])?["cookieSource"] as? String == "manual")
        #expect((backup["alibaba"] as? [String: Any])?["region"] as? String == "international")
        #expect((backup["claude"] as? [String: Any])?["probeMode"] as? String == "cli")

        let copied = try String(
            contentsOf: try backupFileURL(root: env.configRoot, named: "settings.json"),
            encoding: .utf8
        )
        #expect(!copied.contains("ghp_should-not-be-backed-up"))
        #expect(!copied.contains("cookie-secret"))
        #expect(!copied.contains("sk-secret"))
        #expect(!copied.contains("hunter2"))
        #expect(backup["copilotToken"] == nil)
        #expect(backup["sessionCookie"] == nil)
        #expect(backup["apiKey"] == nil)
        #expect(backup["password"] == nil)
    }

    @Test
    func `backup omits secrets tokens cookies and does not copy logs or snapshots`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let json = """
        {
          "app": { "themeMode": "dark" },
          "copilotToken": "ghp_should-not-be-backed-up",
          "sessionCookie": "cookie-secret",
          "apiKey": "sk-secret",
          "password": "hunter2",
          "schemaVersion": 1
        }
        """
        try json.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        try "raw log line".write(to: env.configRoot.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "{}".write(to: env.configRoot.appendingPathComponent("quota-snapshot.json"), atomically: true, encoding: .utf8)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        #expect(manifest.includedFiles == ["settings.json"])
        #expect(!manifest.includedFiles.contains("debug.log"))
        #expect(!manifest.includedFiles.contains("quota-snapshot.json"))

        let settingsCopy = try backupFileURL(root: env.configRoot, named: "settings.json")
        let copied = try String(contentsOf: settingsCopy, encoding: .utf8)
        #expect(!copied.contains("ghp_should-not-be-backed-up"))
        #expect(!copied.contains("cookie-secret"))
        #expect(!copied.contains("sk-secret"))
        #expect(!copied.contains("hunter2"))
        #expect(!copied.lowercased().contains("copilottoken"))
        #expect(!copied.lowercased().contains("sessioncookie"))
        #expect(!copied.lowercased().contains("apikey"))
        #expect(!copied.lowercased().contains("password"))
        #expect(copied.contains("dark"))

        let live = try String(contentsOf: env.settingsURL, encoding: .utf8)
        #expect(live.contains("ghp_should-not-be-backed-up"))
    }

    @Test
    func `listBackups returns manifests newest first`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try #"{"schemaVersion":1,"app":{"themeMode":"dark"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)

        let clock = LockedDate(Date(timeIntervalSince1970: 1_700_000_000))
        let manager = BackupManager(
            configRoot: env.configRoot,
            appVersion: "0.3.28",
            now: { clock.value }
        )
        let first = try manager.createPreMutationBackup()
        clock.advance(5)
        let second = try manager.createPreMutationBackup()

        let listed = try manager.listBackups()
        #expect(listed.count == 2)
        #expect(listed.first?.createdAt == second.createdAt)
        #expect(listed.last?.createdAt == first.createdAt)
    }

    @Test
    func `restore replaces live settings from a valid backup`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let original = """
        {"schemaVersion":1,"app":{"themeMode":"dark","language":"en"}}
        """
        try original.write(to: env.settingsURL, atomically: true, encoding: .utf8)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        try #"{"schemaVersion":1,"app":{"themeMode":"light"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)

        try manager.restore(manifest)

        let restored = try storeDictionary(at: env.settingsURL)
        #expect(restored["schemaVersion"] as? Int == 1)
        #expect((restored["app"] as? [String: Any])?["themeMode"] as? String == "dark")
        #expect((restored["app"] as? [String: Any])?["language"] as? String == "en")
    }

    @Test
    func `restore verifies in a temp directory then atomically replaces live settings`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let original = """
        {"schemaVersion":1,"app":{"themeMode":"dark","language":"en"}}
        """
        try original.write(to: env.settingsURL, atomically: true, encoding: .utf8)

        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        try #"{"schemaVersion":1,"app":{"themeMode":"light"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let liveBeforeRestore = try Data(contentsOf: env.settingsURL)

        try manager.restore(manifest)

        let restored = try storeDictionary(at: env.settingsURL)
        #expect((restored["app"] as? [String: Any])?["themeMode"] as? String == "dark")
        #expect((restored["app"] as? [String: Any])?["language"] as? String == "en")
        #expect(try Data(contentsOf: env.settingsURL) != liveBeforeRestore)

        let listed = try manager.listBackups()
        #expect(listed.count >= 2)
    }

    @Test
    func `restore failure after temp verification leaves live bytes unchanged`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try #"{"schemaVersion":1,"app":{"themeMode":"dark"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let manifest = try manager.createPreMutationBackup()

        try #"{"schemaVersion":1,"app":{"themeMode":"light"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let liveBytes = try Data(contentsOf: env.settingsURL)

        let backupSettings = try backupFileURL(root: env.configRoot, named: "settings.json")
        try "not-valid-json".write(to: backupSettings, atomically: true, encoding: .utf8)

        let error = #expect(throws: SettingsPersistenceError.self) {
            try manager.restore(manifest)
        }
        #expect(error != nil)
        #expect(try Data(contentsOf: env.settingsURL) == liveBytes)
    }

    @Test
    func `inspectBackups reports time version files and checksum status`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try #"{"schemaVersion":1,"app":{"themeMode":"dark"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let manager = BackupManager(configRoot: env.configRoot, appVersion: "0.3.28")
        let valid = try manager.createPreMutationBackup()

        let inspections = try manager.inspectBackups()
        #expect(inspections.count == 1)
        let first = try #require(inspections.first)
        #expect(first.manifest.appVersion == "0.3.28")
        #expect(first.manifest.schemaVersion == 1)
        #expect(first.manifest.includedFiles == ["settings.json"])
        #expect(first.manifest.createdAt == valid.createdAt)
        #expect(first.checksumValid)
        #expect(first.failureReason == nil)

        let backupSettings = try backupFileURL(root: env.configRoot, named: "settings.json")
        try "tampered".write(to: backupSettings, atomically: true, encoding: .utf8)
        let afterTamper = try manager.inspectBackups()
        #expect(afterTamper.first?.checksumValid == false)
        #expect(afterTamper.first?.failureReason?.isEmpty == false)
    }

    @Test
    func `backup root is the injected config root not the user home`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try #"{"schemaVersion":1}"#.write(to: env.settingsURL, atomically: true, encoding: .utf8)
        let manager = BackupManager(configRoot: env.configRoot, appVersion: "test")
        _ = try manager.createPreMutationBackup()

        let backups = env.configRoot.appendingPathComponent("backups", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: backups.path))
        #expect(!env.configRoot.path.contains("/.smartquota"))
    }

    // MARK: - Helpers

    private struct Env {
        let configRoot: URL
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-backup-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(configRoot: root)
    }

    private func backupDirectory(root: URL) throws -> URL {
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let dirs = try FileManager.default.contentsOfDirectory(
            at: backups,
            includingPropertiesForKeys: nil
        ).filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        guard let first = dirs.first else {
            throw NSError(domain: "BackupManagerTests", code: 1)
        }
        return first
    }

    private func backupFileURL(root: URL, named name: String) throws -> URL {
        try backupDirectory(root: root).appendingPathComponent(name)
    }

    private func storeDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    private func allKeys(_ value: Any) -> Set<String> {
        if let dict = value as? [String: Any] {
            return dict.keys.reduce(into: Set<String>()) { result, key in
                result.insert(key)
                result.formUnion(allKeys(dict[key] as Any))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, item in
                result.formUnion(allKeys(item))
            }
        }
        return []
    }
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date = date.addingTimeInterval(seconds)
    }
}

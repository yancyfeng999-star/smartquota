import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("SettingsTransferService Tests")
struct SettingsTransferServiceTests {

    @Test
    func `export JSON omits secrets tokens cookies passwords and keys but keeps cookieSource`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try seedLiveSettings(env, includeEmail: true, includeSecrets: true)
        let service = makeService(env)

        let preview = try service.makeExportPreview(includeEmail: false)
        #expect(preview.includeEmail == false)
        #expect(!preview.fields.contains { $0.kind == .optionalEmail })
        #expect(Set(preview.omittedCategories) == Set(PortableOmittedCategory.allCases))

        let data = try service.exportData(includeEmail: false)
        let text = try #require(String(data: data, encoding: .utf8))
        let json = try storeDictionary(from: data)
        let keys = PortableSettings.jsonObjectKeys(json)

        #expect(PortableSettings.forbiddenSecretFieldNames(in: keys).isEmpty)
        #expect(keys.contains("cookieSource"))
        #expect(!text.contains("ghp_should-not-export"))
        #expect(!text.contains("cookie-secret"))
        #expect(!text.contains("sk-live-should-stay-on-disk"))
        #expect(!text.contains("hunter2"))
        #expect(!text.contains("user@example.com"))
        #expect(!text.lowercased().contains("\"token\""))
        #expect(!text.lowercased().contains("\"password\""))
        #expect(!text.lowercased().contains("\"secret\""))
        #expect((json["mimo"] as? [String: Any])?["cookieSource"] as? String == "auto")
    }

    @Test
    func `export includes email only after explicit opt-in`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try seedLiveSettings(env, includeEmail: true, includeSecrets: false)
        let service = makeService(env)

        let off = try String(data: try service.exportData(includeEmail: false), encoding: .utf8)
        #expect(off?.contains("user@example.com") == false)

        let on = try String(data: try service.exportData(includeEmail: true), encoding: .utf8)
        #expect(on?.contains("user@example.com") == true)
    }

    @Test
    func `import parses validates diffs backups then restores order and remarks without keys`() throws {
        let source = try makeEnv()
        let dest = try makeEnv()
        defer {
            source.cleanup()
            dest.cleanup()
        }

        try seedLiveSettings(source, includeEmail: true, includeSecrets: true, order: ["claude", "codex"], label: "Work")
        try #"{"schemaVersion":2,"app":{"themeMode":"light","language":"zh-Hans","membershipOrder":["kimi"]},"apiKey":"dest-key"}"#
            .write(to: dest.settingsURL, atomically: true, encoding: .utf8)
        try "login".write(
            to: dest.externalLoginURL,
            atomically: true,
            encoding: .utf8
        )
        dest.credentials.set("keychain-token", forKey: "copilot.token")

        let exported = try makeService(source).exportData(includeEmail: false)
        let destService = makeService(dest)
        let preview = try destService.previewImport(data: exported)
        #expect(preview.diff.changed.contains { $0.contains("membershipOrder") } || preview.diff.added.contains { $0.contains("membershipOrder") })

        let backupsBefore = try dest.backupManager.listBackups().count
        try destService.importData(exported, mode: .overwrite)
        #expect(try dest.backupManager.listBackups().count == backupsBefore + 1)

        let live = try storeDictionary(at: dest.settingsURL)
        let importedOrder = stringArray((live["app"] as? [String: Any])?["membershipOrder"])
        #expect(importedOrder == ["claude", "codex"])
        #expect(accountLabels(in: live) == ["Work"])
        #expect(accountEmails(in: live).isEmpty)
        #expect(live["apiKey"] as? String == "dest-key")
        #expect(try String(contentsOf: dest.externalLoginURL, encoding: .utf8) == "login")
        #expect(dest.credentials.string(forKey: "copilot.token") == "keychain-token")
        #expect(accountProbeConfig(in: live).isEmpty)
    }

    @Test
    func `merge import keeps current language and does not enable unknown providers`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try seedLiveSettings(env, includeEmail: true, includeSecrets: false, order: ["claude"], label: "Local")
        let incoming: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": [
                "themeMode": "light",
                "membershipOrder": ["codex", "claude"],
            ],
            "providers": [
                "claude": [
                    "isEnabled": true,
                    "accounts": encodeAccounts([
                        ["accountId": "acc-1", "label": "Imported", "organization": "Acme"],
                    ]),
                ],
                "future-ai": ["isEnabled": true, "planLabel": "Nope"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: incoming, options: [.prettyPrinted, .sortedKeys])
        try makeService(env).importData(data, mode: .merge)

        let live = try storeDictionary(at: env.settingsURL)
        let app = live["app"] as? [String: Any]
        let mergedOrder = stringArray(app?["membershipOrder"])
        #expect(app?["language"] as? String == "en")
        #expect(mergedOrder == ["codex", "claude"])
        #expect(accountLabels(in: live) == ["Imported"])
        #expect(accountEmails(in: live) == ["user@example.com"])
        #expect(accountProbeConfig(in: live)["profile"] == "default")
        #expect(((live["providers"] as? [String: Any])?["future-ai"] as? [String: Any])?["isEnabled"] as? Bool == false)
    }

    @Test
    func `import rejects corrupt JSON without writing or backing up`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try seedLiveSettings(env, includeEmail: false, includeSecrets: false)
        let before = try Data(contentsOf: env.settingsURL)

        #expect(throws: SettingsPersistenceError.self) {
            try makeService(env).importData(Data("{" .utf8), mode: .merge)
        }
        #expect(try Data(contentsOf: env.settingsURL) == before)
        #expect(try env.backupManager.listBackups().isEmpty)
    }

    @Test
    func `restore defaults backups then resets portable settings`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try seedLiveSettings(env, includeEmail: true, includeSecrets: true)
        try "login".write(to: env.externalLoginURL, atomically: true, encoding: .utf8)
        env.credentials.set("stay", forKey: "copilot.token")

        try makeService(env).restoreFactoryDefaults()
        #expect(try env.backupManager.listBackups().isEmpty == false)

        let live = try storeDictionary(at: env.settingsURL)
        let resetApp = live["app"] as? [String: Any]
        let resetOrder = stringArray(resetApp?["membershipOrder"])
        #expect(SettingsJSON.intValue(live[SettingsSchema.versionKey]) == SettingsSchema.currentVersion)
        #expect(resetApp?["themeMode"] as? String == "system")
        #expect(resetOrder.isEmpty)
        #expect(live["apiKey"] == nil)
        #expect(try String(contentsOf: env.externalLoginURL, encoding: .utf8) == "login")
        #expect(env.credentials.string(forKey: "copilot.token") == "stay")
    }

    @Test
    func `clear all local data wipes config root but never Keychain or external logins`() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try seedLiveSettings(env, includeEmail: true, includeSecrets: true)
        _ = try env.backupManager.createPreMutationBackup()
        try "log".write(to: env.configRoot.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "login".write(to: env.externalLoginURL, atomically: true, encoding: .utf8)
        env.credentials.set("stay", forKey: "copilot.token")

        try makeService(env).clearAllLocalData()

        #expect(try env.backupManager.listBackups().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.configRoot.appendingPathComponent("debug.log").path))
        let live = try storeDictionary(at: env.settingsURL)
        #expect(SettingsJSON.intValue(live[SettingsSchema.versionKey]) == SettingsSchema.currentVersion)
        #expect(try String(contentsOf: env.externalLoginURL, encoding: .utf8) == "login")
        #expect(env.credentials.string(forKey: "copilot.token") == "stay")
        #expect(!env.configRoot.path.contains("/.smartquota"))
    }

    // MARK: - Helpers

    private struct Env {
        let configRoot: URL
        let externalRoot: URL
        let credentials: UserDefaults
        let credentialsSuite: String
        let backupManager: BackupManager
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        var externalLoginURL: URL {
            externalRoot.appendingPathComponent(".claude/credentials.json")
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: externalRoot)
            credentials.removePersistentDomain(forName: credentialsSuite)
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-transfer-\(UUID().uuidString)", isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-external-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: external.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        let suite = "smartquota.transfer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Env(
            configRoot: root,
            externalRoot: external,
            credentials: defaults,
            credentialsSuite: suite,
            backupManager: BackupManager(configRoot: root, appVersion: "0.3.28")
        )
    }

    private func makeService(_ env: Env) -> SettingsTransferService {
        SettingsTransferService(
            configRoot: env.configRoot,
            store: JSONSettingsStore(fileURL: env.settingsURL),
            backupManager: env.backupManager
        )
    }

    private func seedLiveSettings(
        _ env: Env,
        includeEmail: Bool,
        includeSecrets: Bool,
        order: [String] = ["claude"],
        label: String = "Personal"
    ) throws {
        var account: [String: Any] = [
            "accountId": "acc-1",
            "label": label,
            "organization": "Acme",
            "probeConfig": ["profile": "default"],
        ]
        if includeEmail {
            account["email"] = "user@example.com"
        }
        var dict: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": [
                "themeMode": "dark",
                "language": "en",
                "usageDisplayMode": "remaining",
                "membershipOrder": order,
                "backgroundSyncInterval": 900,
            ],
            "providers": [
                "claude": [
                    "isEnabled": true,
                    "planLabel": "Pro",
                    "renewalDate": "2026-12-01",
                    "accounts": encodeAccounts([account]),
                ],
            ],
            "mimo": ["cookieSource": "auto"],
        ]
        if includeSecrets {
            dict["apiKey"] = "sk-live-should-stay-on-disk"
            dict["copilotToken"] = "ghp-should-not-export"
            dict["sessionCookie"] = "cookie-secret"
            dict["password"] = "hunter2"
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: env.settingsURL)
    }

    private func encodeAccounts(_ accounts: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: accounts)
        return data.base64EncodedString()
    }

    private func decodeAccounts(_ value: Any?) -> [[String: Any]] {
        guard let base64 = value as? String,
              let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    private func accountEmails(in dict: [String: Any]) -> [String] {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        return providers.values.flatMap { raw -> [String] in
            guard let entry = raw as? [String: Any] else { return [] }
            return decodeAccounts(entry["accounts"]).compactMap { $0["email"] as? String }
        }
    }

    private func accountLabels(in dict: [String: Any]) -> [String] {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        return providers.values.flatMap { raw -> [String] in
            guard let entry = raw as? [String: Any] else { return [] }
            return decodeAccounts(entry["accounts"]).compactMap { $0["label"] as? String }
        }
    }

    private func accountProbeConfig(in dict: [String: Any]) -> [String: String] {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        for raw in providers.values {
            guard let entry = raw as? [String: Any] else { continue }
            if let first = decodeAccounts(entry["accounts"]).first,
               let probe = first["probeConfig"] as? [String: String] {
                return probe
            }
        }
        return [:]
    }

    private func storeDictionary(at url: URL) throws -> [String: Any] {
        try storeDictionary(from: try Data(contentsOf: url))
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let any = value as? [Any] { return any.compactMap { $0 as? String } }
        return []
    }

    private func storeDictionary(from data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }
}

import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: Safe settings export/import and backup restore
///
/// Acceptance: exported JSON has no secret fields; import restores membership
/// order and remarks; keys still need to be reconfigured; unknown providers
/// stay disabled; restore failures keep current data.
@Suite("Feature: Settings Transfer")
struct SettingsTransferSpec {

    @Test
    func `exported JSON has no token cookie secret password or key secret fields`() throws {
        let env = try TransferHarness.make()
        defer { env.cleanup() }

        try TransferHarness.seed(
            env,
            order: ["claude", "codex"],
            label: "Work desk",
            email: "user@example.com",
            secrets: true
        )

        let exported = try env.service.exportData(includeEmail: false)
        let text = try #require(String(data: exported, encoding: .utf8))
        let json = try TransferHarness.dictionary(from: exported)
        let keys = PortableSettings.jsonObjectKeys(json)
        let forbidden = PortableSettings.forbiddenSecretFieldNames(in: keys)

        #expect(forbidden.isEmpty, "secret fields leaked: \(forbidden)")
        #expect(keys.contains("cookieSource"))
        #expect(!text.contains("user@example.com"))
        #expect(!text.contains("ghp_should-not-export"))
        #expect(!text.contains("cookie-secret"))
        #expect(!text.contains("sk-live-should-stay-on-disk"))
        #expect(!text.contains("hunter2"))
        for needle in ["\"token\"", "\"cookie\"", "\"secret\"", "\"password\"", "\"apiKey\""] {
            #expect(!text.contains(needle), "export contained \(needle)")
        }
    }

    @Test
    func `import restores membership order and remarks and still requires key reconfigure`() throws {
        let source = try TransferHarness.make()
        let dest = try TransferHarness.make()
        defer {
            source.cleanup()
            dest.cleanup()
        }

        try TransferHarness.seed(
            source,
            order: ["codex", "claude"],
            label: "Work desk",
            email: "user@example.com",
            secrets: true
        )
        try #"{"schemaVersion":2,"app":{"themeMode":"light","membershipOrder":["kimi"]}}"#
            .write(to: dest.settingsURL, atomically: true, encoding: .utf8)

        let payload = try source.service.exportData(includeEmail: false)
        let preview = try dest.service.previewImport(data: payload)
        #expect(preview.diff.changed.isEmpty == false || preview.diff.added.isEmpty == false)

        try dest.service.importData(payload, mode: .overwrite)

        let live = try TransferHarness.dictionary(at: dest.settingsURL)
        let importedOrder = TransferHarness.stringArray((live["app"] as? [String: Any])?["membershipOrder"])
        #expect(importedOrder == ["codex", "claude"])
        #expect(TransferHarness.accountLabels(in: live) == ["Work desk"])
        #expect(TransferHarness.accountEmails(in: live).isEmpty)
        #expect(live["apiKey"] == nil)
        #expect(live["copilotToken"] == nil)
        #expect(TransferHarness.accountProbeConfig(in: live).isEmpty)
    }

    @Test
    func `merge overwrite unknown provider and repeat import stay safe`() throws {
        let env = try TransferHarness.make()
        defer { env.cleanup() }
        try TransferHarness.seed(env, order: ["claude"], label: "Local", email: "keep@example.com", secrets: false)

        var incoming = try TransferHarness.dictionary(from: try env.service.exportData(includeEmail: false))
        var app = incoming["app"] as? [String: Any] ?? [:]
        app["membershipOrder"] = ["kimi", "claude"]
        incoming["app"] = app
        var providers = incoming["providers"] as? [String: Any] ?? [:]
        providers["future-ai"] = ["isEnabled": true, "planLabel": "Ghost"]
        incoming["providers"] = providers
        let data = try JSONSerialization.data(withJSONObject: incoming, options: [.sortedKeys])

        try env.service.importData(data, mode: .merge)
        try env.service.importData(data, mode: .merge)

        let live = try TransferHarness.dictionary(at: env.settingsURL)
        let mergedOrder = TransferHarness.stringArray((live["app"] as? [String: Any])?["membershipOrder"])
        #expect(mergedOrder == ["kimi", "claude"])
        #expect(TransferHarness.accountLabels(in: live) == ["Local"])
        #expect(TransferHarness.accountEmails(in: live) == ["keep@example.com"])
        #expect(((live["providers"] as? [String: Any])?["future-ai"] as? [String: Any])?["isEnabled"] as? Bool == false)
    }

    @Test
    func `restore and dangerous ops backup first and never touch external logins`() throws {
        let env = try TransferHarness.make()
        defer { env.cleanup() }
        try TransferHarness.seed(env, order: ["claude"], label: "Keep", email: nil, secrets: false)
        try "cli-login".write(to: env.externalLoginURL, atomically: true, encoding: .utf8)

        let manifest = try env.backupManager.createPreMutationBackup()
        try #"{"schemaVersion":2,"app":{"themeMode":"light"}}"#
            .write(to: env.settingsURL, atomically: true, encoding: .utf8)
        try env.backupManager.restore(manifest)

        let restored = try TransferHarness.dictionary(at: env.settingsURL)
        #expect((restored["app"] as? [String: Any])?["themeMode"] as? String == "dark")
        #expect(try String(contentsOf: env.externalLoginURL, encoding: .utf8) == "cli-login")

        let inspections = try env.backupManager.inspectBackups()
        #expect(inspections.contains { $0.checksumValid && $0.manifest.includedFiles == ["settings.json"] })

        try env.service.restoreFactoryDefaults()
        #expect(try String(contentsOf: env.externalLoginURL, encoding: .utf8) == "cli-login")

        var defaults = DualConfirmation(action: .restoreDefaults)
        var wipe = DualConfirmation(action: .clearAllLocalData)
        defaults.confirm()
        #expect(defaults.isComplete == false)
        #expect(wipe.isComplete == false)
        defaults.confirm()
        #expect(defaults.isComplete)
        wipe.confirm()
        wipe.confirm()
        #expect(wipe.isComplete)
        #expect(defaults.action != wipe.action)
    }
}

private struct TransferHarness {
    let configRoot: URL
    let externalRoot: URL
    let backupManager: BackupManager
    let service: SettingsTransferService

    var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
    var externalLoginURL: URL {
        externalRoot.appendingPathComponent(".claude/credentials.json")
    }

    static func make() throws -> TransferHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-transfer-spec-\(UUID().uuidString)", isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-external-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: external.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        let backups = BackupManager(configRoot: root, appVersion: "0.3.28")
        let service = SettingsTransferService(
            configRoot: root,
            store: JSONSettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            backupManager: backups
        )
        return TransferHarness(configRoot: root, externalRoot: external, backupManager: backups, service: service)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: configRoot)
        try? FileManager.default.removeItem(at: externalRoot)
    }

    static func seed(
        _ env: TransferHarness,
        order: [String],
        label: String,
        email: String?,
        secrets: Bool
    ) throws {
        var account: [String: Any] = [
            "accountId": "acc-1",
            "label": label,
            "organization": "Acme",
            "probeConfig": ["profile": "default", "token": "must-not-export"],
        ]
        if let email {
            account["email"] = email
        }
        var dict: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": [
                "themeMode": "dark",
                "language": "en",
                "usageDisplayMode": "remaining",
                "membershipOrder": order,
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
        if secrets {
            dict["apiKey"] = "sk-live-should-stay-on-disk"
            dict["copilotToken"] = "ghp_should-not-export"
            dict["sessionCookie"] = "cookie-secret"
            dict["password"] = "hunter2"
        }
        try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            .write(to: env.settingsURL)
    }

    static func encodeAccounts(_ accounts: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: accounts)
        return data.base64EncodedString()
    }

    static func decodeAccounts(_ value: Any?) -> [[String: Any]] {
        guard let base64 = value as? String,
              let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    static func accountEmails(in dict: [String: Any]) -> [String] {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        return providers.values.flatMap { raw -> [String] in
            guard let entry = raw as? [String: Any] else { return [] }
            return decodeAccounts(entry["accounts"]).compactMap { $0["email"] as? String }
        }
    }

    static func accountLabels(in dict: [String: Any]) -> [String] {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        return providers.values.flatMap { raw -> [String] in
            guard let entry = raw as? [String: Any] else { return [] }
            return decodeAccounts(entry["accounts"]).compactMap { $0["label"] as? String }
        }
    }

    static func accountProbeConfig(in dict: [String: Any]) -> [String: String] {
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

    static func dictionary(at url: URL) throws -> [String: Any] {
        try dictionary(from: try Data(contentsOf: url))
    }

    static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let any = value as? [Any] { return any.compactMap { $0 as? String } }
        return []
    }

    static func dictionary(from data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }
}

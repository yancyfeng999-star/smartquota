import Testing
import Foundation
@testable import Domain

@Suite("PortableSettings Tests")
struct PortableSettingsTests {

    @Test
    func `sanitize without email matches SettingsBackupPolicy and drops secrets`() {
        let source = sampleSettings(includeSecrets: true, includeEmail: true)
        let portable = PortableSettings.sanitize(source, includeEmail: false)
        let policy = SettingsBackupPolicy.sanitizeDictionary(source)
        let portableExport = PortableSettings.exportDocument(source, includeEmail: false)
        let policyExport = PortableSettings.expandAccountBlobs(policy)

        #expect(jsonEquals(portableExport, policyExport))
        #expect(accountEmails(in: portable).isEmpty)
        #expect(portable["apiKey"] == nil)
        #expect(portable["copilotToken"] == nil)
        #expect(portable["sessionCookie"] == nil)
        #expect(portable["password"] == nil)
        #expect((portable["mimo"] as? [String: Any])?["cookieSource"] as? String == "auto")

        let keys = PortableSettings.jsonObjectKeys(portable)
        #expect(PortableSettings.forbiddenSecretFieldNames(in: keys).isEmpty)
        #expect(keys.contains("cookieSource"))
    }

    @Test
    func `email is omitted by default and included only when requested`() {
        let source = sampleSettings(includeSecrets: false, includeEmail: true)

        let withoutEmail = PortableSettings.exportDocument(source, includeEmail: false)
        #expect(accountEmails(in: withoutEmail).isEmpty)
        #expect(!jsonContains(withoutEmail, "user@example.com"))

        let withEmail = PortableSettings.exportDocument(source, includeEmail: true)
        #expect(accountEmails(in: withEmail) == ["user@example.com"])
        #expect(jsonContains(withEmail, "user@example.com"))

        let previewOff = PortableSettings.preview(of: source, includeEmail: false)
        #expect(previewOff.includeEmail == false)
        #expect(previewOff.fields.contains { $0.path.contains("accountId") })
        #expect(previewOff.fields.contains { $0.path.contains("label") })
        #expect(!previewOff.fields.contains { $0.kind == .optionalEmail })
        #expect(Set(previewOff.omittedCategories) == Set(PortableOmittedCategory.allCases))

        let previewOn = PortableSettings.preview(of: source, includeEmail: true)
        #expect(previewOn.includeEmail == true)
        #expect(previewOn.fields.contains { $0.kind == .optionalEmail })
    }

    @Test
    func `parse rejects invalid JSON and future schema`() throws {
        #expect(throws: SettingsPersistenceError.self) {
            try PortableSettings.parse(Data("not-json".utf8))
        }

        let future: [String: Any] = [SettingsSchema.versionKey: SettingsSchema.currentVersion + 5]
        let futureData = try JSONSerialization.data(withJSONObject: future)
        let error = #expect(throws: SettingsPersistenceError.self) {
            _ = try PortableSettings.parseAndNormalize(futureData)
        }
        if case .validationFailed(let reason) = error {
            #expect(reason.contains("schema"))
        } else {
            Issue.record("expected validationFailed, got \(String(describing: error))")
        }
    }

    @Test
    func `parse migrates older schema then validates`() throws {
        let v1: [String: Any] = [
            SettingsSchema.versionKey: 1,
            "app": [
                "themeMode": "dark",
                "language": "en",
                "membershipOrder": ["claude"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: v1)
        let normalized = try PortableSettings.parseAndNormalize(data)
        #expect(SettingsJSON.intValue(normalized[SettingsSchema.versionKey]) == SettingsSchema.currentVersion)
        #expect((normalized["app"] as? [String: Any])?["usageDisplayMode"] as? String == "remaining")
    }

    @Test
    func `merge keeps current extras and applies incoming order and remarks`() {
        let current = sampleSettings(includeSecrets: true, includeEmail: true, order: ["claude"], label: "Old")
        let incoming = sampleSettings(includeSecrets: true, includeEmail: false, order: ["codex", "claude"], label: "Work")

        let merged = PortableSettings.apply(
            incoming: incoming,
            onto: current,
            mode: .merge
        )

        let app = merged["app"] as? [String: Any]
        let mergedOrder = stringArray(app?["membershipOrder"])
        #expect(app?["language"] as? String == "en")
        #expect(app?["themeMode"] as? String == "dark")
        #expect(mergedOrder == ["codex", "claude"])
        #expect(accountLabels(in: merged) == ["Work"])
        #expect(accountEmails(in: merged) == ["user@example.com"])
        #expect(accountProbeConfig(in: merged)["profile"] == "default")
        #expect(merged["apiKey"] as? String == "sk-live-should-stay-on-disk")
        #expect(merged["legacyRootKey"] as? String == "keep-me")
    }

    @Test
    func `overwrite replaces portable fields and still preserves secrets and probeConfig`() {
        let current = sampleSettings(includeSecrets: true, includeEmail: true, order: ["claude"], label: "Old")
        var incoming = sampleSettings(includeSecrets: true, includeEmail: false, order: ["kimi"], label: "Imported")
        var app = incoming["app"] as? [String: Any] ?? [:]
        app.removeValue(forKey: "language")
        incoming["app"] = app

        let overwritten = PortableSettings.apply(
            incoming: incoming,
            onto: current,
            mode: .overwrite
        )

        let resultApp = overwritten["app"] as? [String: Any]
        let overwrittenOrder = stringArray(resultApp?["membershipOrder"])
        #expect(overwrittenOrder == ["kimi"])
        #expect(resultApp?["language"] == nil)
        #expect(accountLabels(in: overwritten) == ["Imported"])
        #expect(accountEmails(in: overwritten).isEmpty)
        #expect(accountProbeConfig(in: overwritten)["profile"] == "default")
        #expect(overwritten["apiKey"] as? String == "sk-live-should-stay-on-disk")
    }

    @Test
    func `unknown providers are never auto-enabled`() {
        var incoming = sampleSettings(includeSecrets: false, includeEmail: false)
        var providers = incoming["providers"] as? [String: Any] ?? [:]
        providers["future-ai"] = ["isEnabled": true, "planLabel": "Mystery"]
        incoming["providers"] = providers

        let applied = PortableSettings.apply(
            incoming: incoming,
            onto: [:],
            mode: .overwrite
        )
        let future = (applied["providers"] as? [String: Any])?["future-ai"] as? [String: Any]
        #expect(future?["isEnabled"] as? Bool == false)
        #expect(future?["planLabel"] as? String == "Mystery")

        let diff = PortableSettings.diff(
            current: SettingsBackupPolicy.sanitizeDictionary([:]),
            incoming: SettingsBackupPolicy.sanitizeDictionary(incoming)
        )
        #expect(diff.unknownProvidersKeptDisabled.contains("future-ai"))
    }

    @Test
    func `forbidden secret field names allow cookieSource and quota key setting names`() {
        let keys = [
            "token", "refreshToken", "cookie", "sessionCookie", "secret",
            "password", "apiKey", "api_key", "cookieSource",
            "menuBarPercentageQuotaKey", "menuBarSecondaryQuotaKey", "themeMode",
        ]
        let forbidden = PortableSettings.forbiddenSecretFieldNames(in: keys)
        #expect(forbidden.contains("token"))
        #expect(forbidden.contains("cookie"))
        #expect(forbidden.contains("secret"))
        #expect(forbidden.contains("password"))
        #expect(forbidden.contains("apiKey"))
        #expect(!forbidden.contains("cookieSource"))
        #expect(!forbidden.contains("menuBarPercentageQuotaKey"))
        #expect(!forbidden.contains("themeMode"))
    }

    @Test
    func `merge preview lists added and changed paths and never implies removals`() {
        let current = sampleSettings(includeSecrets: false, includeEmail: false, order: ["claude"], label: "Local")
        var incoming = sampleSettings(includeSecrets: false, includeEmail: false, order: ["kimi", "claude"], label: "Imported")
        var app = incoming["app"] as? [String: Any] ?? [:]
        app.removeValue(forKey: "language")
        incoming["app"] = app

        let mergeDiff = PortableSettings.diff(
            current: SettingsBackupPolicy.sanitizeDictionary(current),
            incoming: SettingsBackupPolicy.sanitizeDictionary(incoming),
            mode: .merge
        )
        #expect(mergeDiff.removed.isEmpty)
        #expect(mergeDiff.changed.contains { $0.contains("membershipOrder") })
        #expect(mergeDiff.changed.contains { $0.contains("label") })
        #expect(!mergeDiff.added.isEmpty || !mergeDiff.changed.isEmpty)

        let overwriteDiff = PortableSettings.diff(
            current: SettingsBackupPolicy.sanitizeDictionary(current),
            incoming: SettingsBackupPolicy.sanitizeDictionary(incoming),
            mode: .overwrite
        )
        #expect(overwriteDiff.removed.contains { $0.contains("language") })
        #expect(overwriteDiff.changed.contains { $0.contains("membershipOrder") })
    }

    @Test
    func `overwrite keeps live isEnabled when incoming omits that known provider`() {
        let current: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "providers": [
                "claude": ["isEnabled": false, "planLabel": "Pro"],
                "kimi": ["isEnabled": true, "planLabel": "Old"],
            ],
        ]
        let incoming: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": ["themeMode": "light"],
            "providers": [
                "kimi": ["isEnabled": true, "planLabel": "Plus"],
            ],
        ]

        let overwritten = PortableSettings.apply(incoming: incoming, onto: current, mode: .overwrite)
        let providers = overwritten["providers"] as? [String: Any]
        #expect((providers?["claude"] as? [String: Any])?["isEnabled"] as? Bool == false)
        #expect((providers?["kimi"] as? [String: Any])?["planLabel"] as? String == "Plus")

        let overwriteDiff = PortableSettings.diff(
            current: SettingsBackupPolicy.sanitizeDictionary(current),
            incoming: SettingsBackupPolicy.sanitizeDictionary(incoming),
            mode: .overwrite
        )
        #expect(!overwriteDiff.removed.contains("providers.claude.isEnabled"))
    }

    @Test
    func `dangerous actions require two independent confirmations`() {
        var defaults = DualConfirmation()
        var wipe = DualConfirmation()
        #expect(defaults.isComplete == false)
        defaults.confirm()
        #expect(defaults.isComplete == false)
        #expect(wipe.isComplete == false)
        defaults.confirm()
        #expect(defaults.isComplete == true)
        #expect(wipe.isComplete == false)
        wipe.confirm()
        wipe.cancel()
        #expect(wipe.isComplete == false)
        wipe.confirm()
        #expect(wipe.isAwaitingSecondConfirmation)
        wipe.confirm()
        #expect(wipe.isComplete == true)
        #expect(defaults.action == nil)
        defaults = DualConfirmation(action: .restoreDefaults)
        wipe = DualConfirmation(action: .clearAllLocalData)
        #expect(defaults.action != wipe.action)
    }

    // MARK: - Helpers

    private func sampleSettings(
        includeSecrets: Bool,
        includeEmail: Bool,
        order: [String] = ["claude"],
        label: String = "Personal"
    ) -> [String: Any] {
        var account: [String: Any] = [
            "accountId": "acc-1",
            "label": label,
            "organization": "Acme",
            "probeConfig": ["profile": "default", "tokenEnv": "SECRET_TOKEN"],
        ]
        if includeEmail {
            account["email"] = "user@example.com"
        }
        var dict: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "legacyRootKey": "keep-me",
            "app": [
                "themeMode": "dark",
                "language": "en",
                "usageDisplayMode": "remaining",
                "membershipOrder": order,
                "backgroundSyncInterval": 900,
                "menuBarPercentageQuotaKey": "session",
            ],
            "providers": [
                "claude": [
                    "isEnabled": true,
                    "planLabel": "Pro",
                    "renewalDate": "2026-12-01",
                    "accounts": encodeAccounts([account]),
                    "acc-1": [
                        "planLabel": "Pro",
                        "renewalDate": "2026-12-01",
                    ],
                ],
            ],
            "mimo": ["cookieSource": "auto"],
        ]
        if includeSecrets {
            dict["apiKey"] = "sk-live-should-stay-on-disk"
            dict["copilotToken"] = "ghp_should-not-export"
            dict["sessionCookie"] = "cookie-secret"
            dict["password"] = "hunter2"
        }
        return dict
    }

    private func encodeAccounts(_ accounts: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: accounts)
        return data.base64EncodedString()
    }

    private func decodeAccounts(_ value: Any?) -> [[String: Any]] {
        PortableSettings.decodeAccountDicts(value)
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

    private func jsonContains(_ dict: [String: Any], _ needle: String) -> Bool {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(needle)
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let any = value as? [Any] { return any.compactMap { $0 as? String } }
        return []
    }

    private func jsonEquals(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        let l = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys])
        let r = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys])
        return l == r
    }
}

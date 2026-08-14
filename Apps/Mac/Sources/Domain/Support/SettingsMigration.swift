import CryptoKit
import Foundation

public enum SettingsSchema: Sendable {
    public static let currentVersion = 1
    public static let versionKey = "schemaVersion"
    /// Used when `Bundle.main` has no marketing version (unit tests).
    public static let fallbackAppVersion = "0.3.28"
}

public protocol SettingsMigrationStep: Sendable {
    var fromVersion: Int { get }
    var toVersion: Int { get }
    func migrate(_ input: [String: Any]) throws -> [String: Any]
}

public enum SettingsPersistenceError: Error, Equatable, Sendable, LocalizedError {
    case corruptJSON(path: String)
    case validationFailed(String)
    case migrationFailed(from: Int, to: Int, reason: String)
    case writeFailed(String)
    case checksumMismatch(file: String)
    case backupNotFound
    case restoreRejected(String)

    public var code: String {
        switch self {
        case .corruptJSON:
            "settings.corrupt_json"
        case .validationFailed:
            "settings.validation_failed"
        case .migrationFailed:
            "settings.migration_failed"
        case .writeFailed:
            "settings.write_failed"
        case .checksumMismatch:
            "backup.checksum_mismatch"
        case .backupNotFound:
            "backup.not_found"
        case .restoreRejected:
            "backup.restore_rejected"
        }
    }

    /// Machine-readable next step; UI localization happens later.
    public var recoveryHint: String {
        switch self {
        case .corruptJSON:
            "The settings file is unreadable. Restore a local backup or reset settings. The original file was left unchanged."
        case .validationFailed:
            "Migrated settings failed validation. The original file was left unchanged. Restore a backup if the app cannot start."
        case .migrationFailed:
            "Settings migration failed. The original file was left unchanged. Restore the pre-migration backup under backups/."
        case .writeFailed:
            "Writing settings failed. The original file was left unchanged. Free disk space or restore a backup."
        case .checksumMismatch:
            "Backup checksum verification failed. The live settings file was left unchanged. Choose another backup."
        case .backupNotFound:
            "The requested backup could not be found. Pick a backup from the list and try again."
        case .restoreRejected:
            "Restore was rejected because the backup contains a file that is not on the allowlist. The live settings file was left unchanged."
        }
    }

    public var errorDescription: String? {
        switch self {
        case .corruptJSON(let path):
            "Settings JSON is unreadable (\(path)). \(recoveryHint)"
        case .validationFailed(let reason):
            "Settings validation failed: \(reason). \(recoveryHint)"
        case .migrationFailed(let from, let to, let reason):
            "Settings migration from \(from) to \(to) failed: \(reason). \(recoveryHint)"
        case .writeFailed(let reason):
            "Settings write failed: \(reason). \(recoveryHint)"
        case .checksumMismatch(let file):
            "Backup checksum mismatch for \(file). \(recoveryHint)"
        case .backupNotFound:
            "Backup not found. \(recoveryHint)"
        case .restoreRejected(let reason):
            "Backup restore rejected: \(reason). \(recoveryHint)"
        }
    }
}

public enum SettingsJSON: Sendable {
    public static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    public static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum SettingsBackupPolicy: Sendable {
    public static let includedRelativePaths = ["settings.json"]

    public static let appKeys: Set<String> = [
        "themeMode",
        "language",
        "userHasChosenTheme",
        "usageDisplayMode",
        "menuBarPercentageEnabled",
        "menuBarStatusIconEnabled",
        "menuBarDurationEnabled",
        "menuBarStackedEnabled",
        "menuBarStackedSize",
        "menuBarPercentageProviderId",
        "menuBarPercentageQuotaKey",
        "menuBarSecondaryQuotaKey",
        "showDailyUsageCards",
        "overviewModeEnabled",
        "overviewMode",
        "membershipOrder",
        "backgroundSyncEnabled",
        "backgroundSyncInterval",
        "claudeApiBudgetEnabled",
        "claudeApiBudget",
        "burnRateWarningEnabled",
        "burnRateThreshold",
        "quotaThresholdAlertsEnabled",
        "sessionAlertThreshold",
        "weeklyAlertThreshold",
        "nearResetAlertHours",
        "underuseAlertRemaining",
        "receiveBetaUpdates",
    ]

    public static let providerEntryKeys: Set<String> = [
        "isEnabled",
        "customCardURL",
        "planLabel",
        "renewalDate",
        "accounts",
        "selectedAccountId",
    ]

    public static let accountSettingKeys: Set<String> = [
        "planLabel",
        "renewalDate",
    ]

    public static let accountConfigKeys: Set<String> = [
        "accountId",
        "label",
        "organization",
    ]

    public static let claudeKeys: Set<String> = ["probeMode", "cliFallbackEnabled"]
    public static let codexKeys: Set<String> = ["probeMode"]
    public static let kimiKeys: Set<String> = ["probeMode"]
    public static let zaiKeys: Set<String> = ["configPath", "glmAuthEnvVar"]
    public static let copilotKeys: Set<String> = [
        "probeMode",
        "authEnvVar",
        "monthlyLimit",
        "manualUsageValue",
        "manualUsageIsPercent",
        "manualOverrideEnabled",
        "apiReturnedEmpty",
        "lastUsagePeriodMonth",
        "lastUsagePeriodYear",
    ]
    public static let bedrockKeys: Set<String> = ["awsProfile", "regions", "dailyBudget"]
    public static let mimoKeys: Set<String> = ["cookieSource"]
    public static let alibabaKeys: Set<String> = ["region", "cookieSource"]
    public static let minimaxKeys: Set<String> = ["region", "authEnvVar"]
    public static let hookKeys: Set<String> = ["enabled", "port"]

    /// Copies only allowlisted settings. Unknown keys and secrets are omitted.
    public static func sanitizeDictionary(_ dict: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]

        if let version = dict[SettingsSchema.versionKey] {
            output[SettingsSchema.versionKey] = version
        }
        if let app = dict["app"] as? [String: Any] {
            let filtered = pick(app, allowed: appKeys)
            if !filtered.isEmpty {
                output["app"] = filtered
            }
        }
        if let providers = dict["providers"] as? [String: Any] {
            let filtered = allowlistProviders(providers)
            if !filtered.isEmpty {
                output["providers"] = filtered
            }
        }

        let providerRoots: [(String, Set<String>)] = [
            ("claude", claudeKeys),
            ("codex", codexKeys),
            ("kimi", kimiKeys),
            ("zai", zaiKeys),
            ("copilot", copilotKeys),
            ("bedrock", bedrockKeys),
            ("mimo", mimoKeys),
            ("alibaba", alibabaKeys),
            ("minimax", minimaxKeys),
            ("hook", hookKeys),
        ]
        for (root, keys) in providerRoots {
            guard let nested = dict[root] as? [String: Any] else { continue }
            let filtered = pick(nested, allowed: keys)
            if !filtered.isEmpty {
                output[root] = filtered
            }
        }

        return output
    }

    private static func pick(_ dict: [String: Any], allowed: Set<String>) -> [String: Any] {
        var output: [String: Any] = [:]
        for key in allowed {
            if let value = dict[key] {
                output[key] = value
            }
        }
        return output
    }

    private static func allowlistProviders(_ providers: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (providerId, raw) in providers {
            guard let entry = raw as? [String: Any] else { continue }
            var kept: [String: Any] = [:]
            for (key, value) in entry {
                if providerEntryKeys.contains(key) {
                    if key == "accounts" {
                        if let accounts = allowlistAccounts(value) {
                            kept[key] = accounts
                        }
                    } else {
                        kept[key] = value
                    }
                } else if let nested = value as? [String: Any] {
                    let account = pick(nested, allowed: accountSettingKeys)
                    if !account.isEmpty {
                        kept[key] = account
                    }
                }
            }
            if !kept.isEmpty {
                output[providerId] = kept
            }
        }
        return output
    }

    private static func allowlistAccounts(_ value: Any) -> String? {
        guard let base64 = value as? String,
              let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }
        let cleaned: [[String: Any]] = json.compactMap { item in
            guard let account = item as? [String: Any] else { return nil }
            let picked = pick(account, allowed: accountConfigKeys)
            return picked.isEmpty ? nil : picked
        }
        guard JSONSerialization.isValidJSONObject(cleaned),
              let encoded = try? JSONSerialization.data(withJSONObject: cleaned) else {
            return nil
        }
        return encoded.base64EncodedString()
    }
}

public enum SettingsValidator: Sendable {
    public static func validate(_ dict: [String: Any], expectedVersion: Int) throws {
        let version = SettingsJSON.intValue(dict[SettingsSchema.versionKey])
        guard version == expectedVersion else {
            throw SettingsPersistenceError.validationFailed(
                "schemaVersion \(String(describing: version)) != \(expectedVersion)"
            )
        }

        if let app = dict["app"] {
            guard let appDict = app as? [String: Any] else {
                throw SettingsPersistenceError.validationFailed("app must be an object")
            }
            try requireOptionalString(appDict["themeMode"], name: "app.themeMode")
            try requireOptionalString(appDict["language"], name: "app.language")
            if let order = appDict["membershipOrder"], !(order is [Any]) {
                throw SettingsPersistenceError.validationFailed("app.membershipOrder must be an array")
            }
            if let interval = appDict["backgroundSyncInterval"],
               SettingsJSON.doubleValue(interval) == nil {
                throw SettingsPersistenceError.validationFailed("app.backgroundSyncInterval must be a number")
            }
        }

        if let providers = dict["providers"] {
            guard let providerDict = providers as? [String: Any] else {
                throw SettingsPersistenceError.validationFailed("providers must be an object")
            }
            for (id, raw) in providerDict {
                guard let entry = raw as? [String: Any] else {
                    throw SettingsPersistenceError.validationFailed("providers.\(id) must be an object")
                }
                if let enabled = entry["isEnabled"], !(enabled is Bool) {
                    throw SettingsPersistenceError.validationFailed("providers.\(id).isEnabled must be a bool")
                }
                try requireOptionalString(entry["planLabel"], name: "providers.\(id).planLabel")
                try requireOptionalString(entry["renewalDate"], name: "providers.\(id).renewalDate")
            }
        }
    }

    private static func requireOptionalString(_ value: Any?, name: String) throws {
        guard let value else { return }
        guard value is String else {
            throw SettingsPersistenceError.validationFailed("\(name) must be a string")
        }
    }
}

public struct LegacySettingsToV1Step: SettingsMigrationStep {
    public init() {}

    public var fromVersion: Int { 0 }
    public var toVersion: Int { 1 }

    public func migrate(_ input: [String: Any]) throws -> [String: Any] {
        var output = input
        output[SettingsSchema.versionKey] = SettingsSchema.currentVersion

        var app = output["app"] as? [String: Any] ?? [:]
        if app["themeMode"] == nil {
            app["themeMode"] = "system"
        }
        if app["language"] == nil {
            app["language"] = "zh-Hans"
        }
        if app["membershipOrder"] == nil {
            app["membershipOrder"] = [String]()
        }
        if app["backgroundSyncInterval"] == nil {
            app["backgroundSyncInterval"] = 900
        }
        if app["overviewModeEnabled"] == nil, let legacy = app["overviewMode"] {
            app["overviewModeEnabled"] = legacy
        }
        output["app"] = app
        return output
    }
}

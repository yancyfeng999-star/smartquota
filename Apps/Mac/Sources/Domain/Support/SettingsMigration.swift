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

    public static func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        let banned = [
            "token",
            "cookie",
            "password",
            "secret",
            "keychain",
            "authorization",
            "apikey",
            "api_key",
            "api-key",
            "access_token",
            "refresh_token",
        ]
        return banned.contains { lowered.contains($0) }
    }

    public static func sanitizeDictionary(_ dict: [String: Any]) -> [String: Any] {
        sanitize(dict) as? [String: Any] ?? [:]
    }

    public static func sanitize(_ value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, child) in dict {
                if isSensitiveKey(key) { continue }
                if key == "accounts", let base64 = child as? String {
                    if let sanitized = sanitizeAccountsBlob(base64) {
                        output[key] = sanitized
                    }
                    continue
                }
                if let cleaned = sanitize(child) {
                    output[key] = cleaned
                }
            }
            return output
        }
        if let array = value as? [Any] {
            return array.compactMap { sanitize($0) }
        }
        return value
    }

    private static func sanitizeAccountsBlob(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data),
              let cleaned = sanitize(json),
              JSONSerialization.isValidJSONObject(cleaned),
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

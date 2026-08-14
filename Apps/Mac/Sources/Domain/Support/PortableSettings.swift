import Foundation

public enum SettingsImportMode: String, Sendable, Equatable {
    case merge
    case overwrite
}

public enum PortableOmittedCategory: String, CaseIterable, Sendable, Equatable {
    case apiKey
    case token
    case cookie
    case password
    case oauth
    case keychain
    case rawProviderResponse
    case logs
    case diagnosticSecrets
}

public enum PortableFieldKind: String, Sendable, Equatable {
    case setting
    case accountMetadata
    case optionalEmail
}

public struct PortableSettingsField: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let kind: PortableFieldKind

    public init(path: String, kind: PortableFieldKind) {
        self.path = path
        self.kind = kind
    }
}

public struct PortableSettingsPreview: Equatable, Sendable {
    public let includeEmail: Bool
    public let fields: [PortableSettingsField]
    public let omittedCategories: [PortableOmittedCategory]

    public init(
        includeEmail: Bool,
        fields: [PortableSettingsField],
        omittedCategories: [PortableOmittedCategory]
    ) {
        self.includeEmail = includeEmail
        self.fields = fields
        self.omittedCategories = omittedCategories
    }
}

public struct SettingsImportDiff: Equatable, Sendable {
    public let added: [String]
    public let changed: [String]
    public let removed: [String]
    public let unknownProvidersKeptDisabled: [String]

    public init(
        added: [String],
        changed: [String],
        removed: [String],
        unknownProvidersKeptDisabled: [String]
    ) {
        self.added = added
        self.changed = changed
        self.removed = removed
        self.unknownProvidersKeptDisabled = unknownProvidersKeptDisabled
    }
}

public struct SettingsImportPreview: Equatable, Sendable {
    public let schemaVersion: Int
    public let includeEmail: Bool
    public let diff: SettingsImportDiff

    public init(schemaVersion: Int, includeEmail: Bool, diff: SettingsImportDiff) {
        self.schemaVersion = schemaVersion
        self.includeEmail = includeEmail
        self.diff = diff
    }
}

public enum DangerousSettingsAction: String, Sendable, Equatable {
    case restoreDefaults
    case clearAllLocalData
}

public struct DualConfirmation: Equatable, Sendable {
    public var action: DangerousSettingsAction?
    public private(set) var step: Int

    public init(action: DangerousSettingsAction? = nil) {
        self.action = action
        self.step = 0
    }

    public var isComplete: Bool { step >= 2 }

    /// First confirm succeeded; the second independent alert may now be shown.
    public var isAwaitingSecondConfirmation: Bool { step == 1 }

    public mutating func confirm() {
        if step < 2 { step += 1 }
    }

    public mutating func cancel() {
        step = 0
    }
}

/// Portable settings use `SettingsBackupPolicy` as the only sanitizer.
public enum PortableSettings: Sendable {
    public static func sanitize(_ dict: [String: Any], includeEmail: Bool) -> [String: Any] {
        SettingsBackupPolicy.sanitizeDictionary(
            normalizeAccountBlobs(dict),
            includeEmail: includeEmail
        )
    }

    /// Same allowlist as `sanitize`, with account records expanded to JSON objects
    /// so an export file can be reviewed without decoding base64.
    public static func exportDocument(_ dict: [String: Any], includeEmail: Bool) -> [String: Any] {
        expandAccountBlobs(sanitize(dict, includeEmail: includeEmail))
    }

    public static func preview(of dict: [String: Any], includeEmail: Bool) -> PortableSettingsPreview {
        let sanitized = sanitize(dict, includeEmail: includeEmail)
        return PortableSettingsPreview(
            includeEmail: includeEmail,
            fields: fieldPaths(in: sanitized, includeEmail: includeEmail),
            omittedCategories: PortableOmittedCategory.allCases
        )
    }

    public static func parse(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            throw SettingsPersistenceError.validationFailed("empty document")
        }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SettingsPersistenceError.corruptJSON(path: "import")
        }
        guard let dict = json as? [String: Any] else {
            throw SettingsPersistenceError.validationFailed("root must be an object")
        }
        return dict
    }

    public static func parseAndNormalize(_ data: Data) throws -> [String: Any] {
        try normalize(normalizeAccountBlobs(try parse(data)))
    }

    public static func normalize(_ dict: [String: Any]) throws -> [String: Any] {
        var working = dict
        var version = SettingsJSON.intValue(working[SettingsSchema.versionKey]) ?? 0
        if version > SettingsSchema.currentVersion {
            throw SettingsPersistenceError.validationFailed(
                "schemaVersion \(version) is newer than \(SettingsSchema.currentVersion)"
            )
        }
        while version < SettingsSchema.currentVersion {
            guard let step = SettingsMigrationCatalog.orderedSteps.first(where: { $0.fromVersion == version }) else {
                throw SettingsPersistenceError.validationFailed("missing migration step from \(version)")
            }
            working = try step.migrate(working)
            version = step.toVersion
        }
        try SettingsValidator.validate(working, expectedVersion: SettingsSchema.currentVersion)
        return working
    }

    public static func factoryDefaults() -> [String: Any] {
        [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": [
                "themeMode": "system",
                "language": "zh-Hans",
                "usageDisplayMode": "remaining",
                "membershipOrder": [String](),
                "backgroundSyncInterval": 900,
            ],
        ]
    }

    public static func jsonObjectKeys(_ value: Any) -> [String] {
        var keys: [String] = []
        collectKeys(value, into: &keys)
        return keys
    }

    public static func forbiddenSecretFieldNames(in keys: [String]) -> [String] {
        keys.filter(isForbiddenSecretField)
    }

    public static func isForbiddenSecretField(_ key: String) -> Bool {
        let allowed: Set<String> = [
            "cookieSource",
            "menuBarPercentageQuotaKey",
            "menuBarSecondaryQuotaKey",
        ]
        if allowed.contains(key) { return false }
        let lower = key.lowercased()
        if ["token", "cookie", "secret", "password"].contains(where: { lower.contains($0) }) {
            return true
        }
        return lower == "key"
            || lower.contains("apikey")
            || lower.contains("api_key")
            || lower.contains("api-key")
    }

    public static func apply(
        incoming: [String: Any],
        onto current: [String: Any],
        mode: SettingsImportMode,
        knownProviderIDs: Set<String> = Set(ProviderEnablement.knownProviderIDs)
    ) -> [String: Any] {
        let incomingPortable = disableUnknownProviders(
            sanitize(incoming, includeEmail: true),
            known: knownProviderIDs
        )
        let currentPortable = sanitize(current, includeEmail: true)
        let portable: [String: Any]
        switch mode {
        case .merge:
            portable = disableUnknownProviders(
                deepMerge(currentPortable, incomingPortable),
                known: knownProviderIDs
            )
        case .overwrite:
            portable = incomingPortable
        }
        return recombine(current: current, portable: portable, mode: mode)
    }

    public static func diff(
        current: [String: Any],
        incoming: [String: Any],
        mode: SettingsImportMode = .overwrite
    ) -> SettingsImportDiff {
        let currentFlat = Dictionary(uniqueKeysWithValues: flatten(current))
        let incomingFlat = Dictionary(uniqueKeysWithValues: flatten(incoming))
        var added: [String] = []
        var changed: [String] = []
        var removed: [String] = []
        for key in Set(currentFlat.keys).union(incomingFlat.keys).sorted() {
            let left = currentFlat[key]
            let right = incomingFlat[key]
            if left == nil {
                added.append(key)
            } else if right == nil {
                removed.append(key)
            } else if left != right {
                changed.append(key)
            }
        }
        if mode == .merge {
            removed = []
        } else {
            let incomingIDs = incomingProviderIDs(incoming)
            removed = removed.filter { path in
                !isPreservedLiveEnablementPath(path, incomingProviderIDs: incomingIDs)
            }
        }
        return SettingsImportDiff(
            added: added,
            changed: changed,
            removed: removed,
            unknownProvidersKeptDisabled: unknownEnabledProviders(in: incoming)
        )
    }

    public static func unknownEnabledProviders(
        in dict: [String: Any],
        knownProviderIDs: Set<String> = Set(ProviderEnablement.knownProviderIDs)
    ) -> [String] {
        guard let providers = dict["providers"] as? [String: Any] else { return [] }
        return providers.keys.sorted().filter { id in
            guard !knownProviderIDs.contains(id) else { return false }
            let entry = providers[id] as? [String: Any]
            return entry?["isEnabled"] as? Bool == true
        }
    }

    // MARK: - Recombine / merge

    private static func recombine(
        current: [String: Any],
        portable: [String: Any],
        mode: SettingsImportMode
    ) -> [String: Any] {
        var output = current
        if let version = portable[SettingsSchema.versionKey] {
            output[SettingsSchema.versionKey] = version
        }
        output["app"] = recombineObject(
            current: current["app"] as? [String: Any] ?? [:],
            portable: portable["app"] as? [String: Any] ?? [:],
            allowed: SettingsBackupPolicy.appKeys,
            mode: mode
        )
        output["providers"] = recombineProviders(
            current: current["providers"] as? [String: Any] ?? [:],
            portable: portable["providers"] as? [String: Any] ?? [:],
            mode: mode
        )

        let roots: [(String, Set<String>)] = [
            ("claude", SettingsBackupPolicy.claudeKeys),
            ("codex", SettingsBackupPolicy.codexKeys),
            ("kimi", SettingsBackupPolicy.kimiKeys),
            ("zai", SettingsBackupPolicy.zaiKeys),
            ("copilot", SettingsBackupPolicy.copilotKeys),
            ("bedrock", SettingsBackupPolicy.bedrockKeys),
            ("mimo", SettingsBackupPolicy.mimoKeys),
            ("alibaba", SettingsBackupPolicy.alibabaKeys),
            ("minimax", SettingsBackupPolicy.minimaxKeys),
            ("hook", SettingsBackupPolicy.hookKeys),
        ]
        for (root, keys) in roots {
            let currentNested = current[root] as? [String: Any]
            let portableNested = portable[root] as? [String: Any]
            if currentNested == nil && portableNested == nil { continue }
            output[root] = recombineObject(
                current: currentNested ?? [:],
                portable: portableNested ?? [:],
                allowed: keys,
                mode: mode
            )
        }
        return output
    }

    private static func recombineObject(
        current: [String: Any],
        portable: [String: Any],
        allowed: Set<String>,
        mode: SettingsImportMode
    ) -> [String: Any] {
        var output = current
        if mode == .overwrite {
            for key in allowed {
                output.removeValue(forKey: key)
            }
        }
        for (key, value) in portable {
            output[key] = value
        }
        return output
    }

    private static func recombineProviders(
        current: [String: Any],
        portable: [String: Any],
        mode: SettingsImportMode
    ) -> [String: Any] {
        var output = current
        for id in Set(current.keys).union(portable.keys) {
            let currentEntry = current[id] as? [String: Any] ?? [:]
            guard let portableEntry = portable[id] as? [String: Any] else {
                if mode == .overwrite {
                    var kept = currentEntry
                    for key in SettingsBackupPolicy.providerEntryKeys where key != "isEnabled" {
                        kept.removeValue(forKey: key)
                    }
                    if kept.isEmpty {
                        output.removeValue(forKey: id)
                    } else {
                        output[id] = kept
                    }
                }
                continue
            }

            var entry = currentEntry
            if mode == .overwrite {
                for key in SettingsBackupPolicy.providerEntryKeys {
                    entry.removeValue(forKey: key)
                }
            }
            for (key, value) in portableEntry {
                if key == "accounts" {
                    entry[key] = mergeAccounts(
                        current: currentEntry["accounts"],
                        incoming: value,
                        mode: mode
                    ) ?? value
                } else {
                    entry[key] = value
                }
            }
            if portableEntry["isEnabled"] == nil, let liveEnabled = currentEntry["isEnabled"] {
                entry["isEnabled"] = liveEnabled
            }
            output[id] = entry
        }
        return output
    }

    private static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var output = base
        for (key, value) in overlay {
            if key == "providers", let overlayProviders = value as? [String: Any] {
                var providers = output["providers"] as? [String: Any] ?? [:]
                for (id, raw) in overlayProviders {
                    guard let overlayEntry = raw as? [String: Any] else {
                        providers[id] = raw
                        continue
                    }
                    var merged = providers[id] as? [String: Any] ?? [:]
                    for (nestedKey, nestedValue) in overlayEntry {
                        if nestedKey == "accounts" {
                            merged[nestedKey] = mergeAccounts(
                                current: (providers[id] as? [String: Any])?["accounts"],
                                incoming: nestedValue,
                                mode: .merge
                            ) ?? nestedValue
                        } else {
                            merged[nestedKey] = nestedValue
                        }
                    }
                    providers[id] = merged
                }
                output["providers"] = providers
            } else if let overlayDict = value as? [String: Any],
                      let currentDict = output[key] as? [String: Any] {
                output[key] = deepMerge(currentDict, overlayDict)
            } else {
                output[key] = value
            }
        }
        return output
    }

    private static func mergeAccounts(current: Any?, incoming: Any, mode: SettingsImportMode) -> String? {
        let currentAccounts = decodeAccountDicts(current)
        let incomingAccounts = decodeAccountDicts(incoming)
        let currentByID = Dictionary(
            uniqueKeysWithValues: currentAccounts.compactMap { account -> (String, [String: Any])? in
                guard let id = account["accountId"] as? String else { return nil }
                return (id, account)
            }
        )

        let merged: [[String: Any]]
        switch mode {
        case .overwrite:
            merged = incomingAccounts.map { incomingAccount in
                let id = incomingAccount["accountId"] as? String
                return mergeOneAccount(
                    incoming: incomingAccount,
                    existing: id.flatMap { currentByID[$0] },
                    mode: .overwrite
                )
            }
        case .merge:
            var byID = currentByID
            var order = currentAccounts.compactMap { $0["accountId"] as? String }
            for incomingAccount in incomingAccounts {
                guard let id = incomingAccount["accountId"] as? String else { continue }
                if byID[id] == nil {
                    order.append(id)
                }
                byID[id] = mergeOneAccount(
                    incoming: incomingAccount,
                    existing: byID[id],
                    mode: .merge
                )
            }
            merged = order.compactMap { byID[$0] }
        }
        return encodeAccountDicts(merged)
    }

    private static func mergeOneAccount(
        incoming: [String: Any],
        existing: [String: Any]?,
        mode: SettingsImportMode
    ) -> [String: Any] {
        var output = existing ?? [:]
        for key in ["accountId", "label", "organization"] {
            if let value = incoming[key] {
                output[key] = value
            }
        }
        if incoming.keys.contains("email") {
            output["email"] = incoming["email"]
        } else if mode == .overwrite {
            output.removeValue(forKey: "email")
        }
        if let probe = existing?["probeConfig"] {
            output["probeConfig"] = probe
        } else {
            output.removeValue(forKey: "probeConfig")
        }
        return output
    }

    private static func incomingProviderIDs(_ dict: [String: Any]) -> Set<String> {
        Set((dict["providers"] as? [String: Any])?.keys.map { $0 } ?? [])
    }

    private static func isPreservedLiveEnablementPath(
        _ path: String,
        incomingProviderIDs: Set<String>
    ) -> Bool {
        let prefix = "providers."
        let suffix = ".isEnabled"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return false }
        let id = String(path.dropFirst(prefix.count).dropLast(suffix.count))
        return !id.isEmpty && !incomingProviderIDs.contains(id)
    }

    private static func disableUnknownProviders(
        _ dict: [String: Any],
        known: Set<String>
    ) -> [String: Any] {
        guard var providers = dict["providers"] as? [String: Any] else { return dict }
        for (id, raw) in providers {
            guard !known.contains(id), var entry = raw as? [String: Any] else { continue }
            entry["isEnabled"] = false
            providers[id] = entry
        }
        var output = dict
        output["providers"] = providers
        return output
    }

    // MARK: - Walkers

    private static func fieldPaths(in dict: [String: Any], includeEmail: Bool) -> [PortableSettingsField] {
        var fields: [PortableSettingsField] = []
        walkFields(dict, path: "", includeEmail: includeEmail, into: &fields)
        return fields
    }

    private static func walkFields(
        _ value: Any,
        path: String,
        includeEmail: Bool,
        into fields: inout [PortableSettingsField]
    ) {
        if path.hasSuffix(".accounts") {
            let accounts = decodeAccountDicts(value)
            guard !accounts.isEmpty else { return }
            for (index, account) in accounts.enumerated() {
                for key in ["accountId", "label", "organization"] where account[key] != nil {
                    fields.append(
                        PortableSettingsField(
                            path: "\(path)[\(index)].\(key)",
                            kind: .accountMetadata
                        )
                    )
                }
                if includeEmail, account["email"] != nil {
                    fields.append(
                        PortableSettingsField(
                            path: "\(path)[\(index)].email",
                            kind: .optionalEmail
                        )
                    )
                }
            }
            return
        }
        if let nested = value as? [String: Any] {
            for key in nested.keys.sorted() {
                let next = path.isEmpty ? key : "\(path).\(key)"
                walkFields(nested[key] as Any, path: next, includeEmail: includeEmail, into: &fields)
            }
            return
        }
        if !path.isEmpty {
            fields.append(PortableSettingsField(path: path, kind: .setting))
        }
    }

    private static func flatten(_ value: Any, path: String = "") -> [(String, String)] {
        if path.hasSuffix(".accounts") {
            let accounts = decodeAccountDicts(value)
            return accounts.enumerated().flatMap { index, account in
                flatten(account, path: "\(path)[\(index)]")
            }
        }
        if let dict = value as? [String: Any] {
            return dict.keys.sorted().flatMap { key in
                let next = path.isEmpty ? key : "\(path).\(key)"
                return flatten(dict[key] as Any, path: next)
            }
        }
        if let array = value as? [Any] {
            if let strings = array as? [String] {
                return [(path, strings.joined(separator: ","))]
            }
            return array.enumerated().flatMap { index, item in
                flatten(item, path: "\(path)[\(index)]")
            }
        }
        if path.isEmpty { return [] }
        return [(path, stringify(value))]
    }

    private static func stringify(_ value: Any) -> String {
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private static func collectKeys(_ value: Any, into keys: inout [String]) {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict {
                keys.append(key)
                if key == "accounts" {
                    collectKeys(decodeAccountDicts(nested), into: &keys)
                } else {
                    collectKeys(nested, into: &keys)
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                collectKeys(item, into: &keys)
            }
        }
    }

    public static func decodeAccountDicts(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        guard let base64 = value as? String,
              let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return json.compactMap { $0 as? [String: Any] }
    }

    public static func normalizeAccountBlobs(_ dict: [String: Any]) -> [String: Any] {
        guard var providers = dict["providers"] as? [String: Any] else { return dict }
        for (id, raw) in providers {
            guard var entry = raw as? [String: Any] else { continue }
            if let array = entry["accounts"] as? [Any],
               JSONSerialization.isValidJSONObject(array),
               let data = try? JSONSerialization.data(withJSONObject: array) {
                entry["accounts"] = data.base64EncodedString()
                providers[id] = entry
            }
        }
        var output = dict
        output["providers"] = providers
        return output
    }

    public static func expandAccountBlobs(_ dict: [String: Any]) -> [String: Any] {
        guard var providers = dict["providers"] as? [String: Any] else { return dict }
        for (id, raw) in providers {
            guard var entry = raw as? [String: Any] else { continue }
            let accounts = decodeAccountDicts(entry["accounts"])
            if !accounts.isEmpty {
                entry["accounts"] = accounts
                providers[id] = entry
            }
        }
        var output = dict
        output["providers"] = providers
        return output
    }

    private static func encodeAccountDicts(_ accounts: [[String: Any]]) -> String? {
        guard JSONSerialization.isValidJSONObject(accounts),
              let data = try? JSONSerialization.data(withJSONObject: accounts) else {
            return nil
        }
        return data.base64EncodedString()
    }
}

import Foundation
import Domain

public protocol SettingsTransferring: Sendable {
    func makeExportPreview(includeEmail: Bool) throws -> PortableSettingsPreview
    func exportData(includeEmail: Bool) throws -> Data
    func writeExport(to url: URL, includeEmail: Bool) throws
    func previewImport(data: Data, mode: SettingsImportMode) throws -> SettingsImportPreview
    func importData(_ data: Data, mode: SettingsImportMode) throws
    func restoreFactoryDefaults() throws
    func clearAllLocalData() throws
}

/// Export/import non-secret settings. Reuses `SettingsBackupPolicy` via `PortableSettings`.
public final class SettingsTransferService: SettingsTransferring, @unchecked Sendable {
    public let configRoot: URL

    private let store: JSONSettingsStore
    private let backupManager: any BackupManaging
    private let knownProviderIDs: Set<String>
    private let lock = NSLock()

    public init(
        configRoot: URL,
        store: JSONSettingsStore,
        backupManager: (any BackupManaging)? = nil,
        knownProviderIDs: Set<String> = Set(ProviderEnablement.knownProviderIDs)
    ) {
        self.configRoot = configRoot
        self.store = store
        self.backupManager = backupManager ?? BackupManager(configRoot: configRoot)
        self.knownProviderIDs = knownProviderIDs
    }

    public func makeExportPreview(includeEmail: Bool) throws -> PortableSettingsPreview {
        lock.lock()
        defer { lock.unlock() }
        return PortableSettings.preview(of: liveDictionary(), includeEmail: includeEmail)
    }

    public func exportData(includeEmail: Bool) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let document = PortableSettings.exportDocument(liveDictionary(), includeEmail: includeEmail)
        guard JSONSerialization.isValidJSONObject(document) else {
            throw SettingsPersistenceError.validationFailed("exported settings are not valid JSON")
        }
        return try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public func writeExport(to url: URL, includeEmail: Bool) throws {
        try SettingsFileIO.performAtomicWrite(try exportData(includeEmail: includeEmail), to: url)
    }

    public func previewImport(from url: URL, mode: SettingsImportMode = .merge) throws -> SettingsImportPreview {
        try previewImport(data: try Data(contentsOf: url), mode: mode)
    }

    public func previewImport(data: Data, mode: SettingsImportMode = .merge) throws -> SettingsImportPreview {
        lock.lock()
        defer { lock.unlock() }
        let normalized = try PortableSettings.parseAndNormalize(data)
        let incoming = PortableSettings.sanitize(normalized, includeEmail: true)
        let current = PortableSettings.sanitize(liveDictionary(), includeEmail: true)
        return SettingsImportPreview(
            schemaVersion: SettingsJSON.intValue(normalized[SettingsSchema.versionKey]) ?? 0,
            includeEmail: containsAccountEmail(incoming),
            diff: PortableSettings.diff(current: current, incoming: incoming, mode: mode)
        )
    }

    public func importData(from url: URL, mode: SettingsImportMode) throws {
        try importData(try Data(contentsOf: url), mode: mode)
    }

    public func importData(_ data: Data, mode: SettingsImportMode) throws {
        lock.lock()
        defer { lock.unlock() }
        let normalized = try PortableSettings.parseAndNormalize(data)
        _ = try backupManager.createPreMutationBackup()
        let applied = PortableSettings.apply(
            incoming: normalized,
            onto: liveDictionary(),
            mode: mode,
            knownProviderIDs: knownProviderIDs
        )
        try store.replaceAll(applied)
    }

    public func restoreFactoryDefaults() throws {
        lock.lock()
        defer { lock.unlock() }
        _ = try backupManager.createPreMutationBackup()
        try store.replaceAll(PortableSettings.factoryDefaults())
    }

    public func clearAllLocalData() throws {
        lock.lock()
        defer { lock.unlock() }
        try Self.clearLocalData(configRoot: configRoot) {
            try store.replaceAll(PortableSettings.factoryDefaults())
        }
    }

    /// Writes defaults first. Siblings are removed only after that write succeeds.
    public static func clearLocalData(
        configRoot: URL,
        settingsFileName: String = "settings.json",
        writeDefaults: () throws -> Void
    ) throws {
        try writeDefaults()
        let items = (try? FileManager.default.contentsOfDirectory(
            at: configRoot,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        for item in items where item.lastPathComponent != settingsFileName {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private func liveDictionary() -> [String: Any] {
        store.readAll()
    }

    private func containsAccountEmail(_ dict: [String: Any]) -> Bool {
        let providers = dict["providers"] as? [String: Any] ?? [:]
        for raw in providers.values {
            guard let entry = raw as? [String: Any] else { continue }
            if PortableSettings.decodeAccountDicts(entry["accounts"]).contains(where: { $0["email"] != nil }) {
                return true
            }
        }
        return false
    }
}

import Foundation
import Domain

/// Atomic writer used by backups and settings migration.
public struct SettingsFileIO: Sendable {
    public var writeAtomically: @Sendable (Data, URL) throws -> Void

    public init(writeAtomically: @escaping @Sendable (Data, URL) throws -> Void) {
        self.writeAtomically = writeAtomically
    }

    public static let live = SettingsFileIO { data, url in
        try performAtomicWrite(data, to: url)
    }

    public static func performAtomicWrite(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temp = parent.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            if let persistence = error as? SettingsPersistenceError {
                throw persistence
            }
            throw SettingsPersistenceError.writeFailed(error.localizedDescription)
        }
    }
}

/// Pre-mutation backups under `<configRoot>/backups/<timestamp>/`.
public final class BackupManager: BackupManaging, @unchecked Sendable {
    public let configRoot: URL
    public let appVersion: String

    private let now: @Sendable () -> Date
    private let fileIO: SettingsFileIO
    private let lock = NSLock()

    public init(
        configRoot: URL,
        appVersion: String = SettingsSchema.fallbackAppVersion,
        now: @escaping @Sendable () -> Date = Date.init,
        fileIO: SettingsFileIO = .live
    ) {
        self.configRoot = configRoot
        self.appVersion = appVersion
        self.now = now
        self.fileIO = fileIO
    }

    public func createPreMutationBackup() throws -> BackupManifest {
        lock.lock()
        defer { lock.unlock() }

        let createdAt = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        let backupDir = backupsRoot.appendingPathComponent(folderName(for: createdAt), isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var includedFiles: [String] = []
        var hashes: [String: String] = [:]
        var schemaVersion = 0

        let settingsURL = configRoot.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let raw = try Data(contentsOf: settingsURL)
            let payload: Data
            if raw.isEmpty {
                payload = try JSONSerialization.data(
                    withJSONObject: [String: Any](),
                    options: [.prettyPrinted, .sortedKeys]
                )
            } else if let json = try? JSONSerialization.jsonObject(with: raw),
                      let dict = json as? [String: Any] {
                schemaVersion = SettingsJSON.intValue(dict[SettingsSchema.versionKey]) ?? 0
                let sanitized = SettingsBackupPolicy.sanitizeDictionary(dict)
                guard JSONSerialization.isValidJSONObject(sanitized) else {
                    throw SettingsPersistenceError.validationFailed("sanitized settings are not valid JSON")
                }
                payload = try JSONSerialization.data(
                    withJSONObject: sanitized,
                    options: [.prettyPrinted, .sortedKeys]
                )
            } else {
                // Unreadable JSON cannot be allowlisted; do not copy raw bytes.
                payload = try JSONSerialization.data(
                    withJSONObject: [String: Any](),
                    options: [.prettyPrinted, .sortedKeys]
                )
            }

            try fileIO.writeAtomically(payload, backupDir.appendingPathComponent("settings.json"))
            includedFiles.append("settings.json")
            hashes["settings.json"] = SettingsJSON.sha256Hex(payload)
        }

        let manifest = BackupManifest(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            createdAt: createdAt,
            includedFiles: includedFiles,
            sha256: hashes
        )
        let manifestData = try Self.encoder.encode(manifest)
        try fileIO.writeAtomically(manifestData, backupDir.appendingPathComponent("manifest.json"))
        return manifest
    }

    public func listBackups() throws -> [BackupManifest] {
        lock.lock()
        defer { lock.unlock() }

        let root = backupsRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var manifests: [BackupManifest] = []
        for directory in directories {
            let url = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? Self.decoder.decode(BackupManifest.self, from: data) else {
                continue
            }
            manifests.append(manifest)
        }
        return manifests.sorted { $0.createdAt > $1.createdAt }
    }

    public func restore(_ backup: BackupManifest) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let directory = try findDirectory(matching: backup) else {
            throw SettingsPersistenceError.backupNotFound
        }

        var verified: [(String, Data)] = []
        for file in backup.includedFiles {
            guard SettingsBackupPolicy.includedRelativePaths.contains(file) else {
                throw SettingsPersistenceError.restoreRejected("\(file) is not allowlisted")
            }
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            let digest = SettingsJSON.sha256Hex(data)
            guard digest == backup.sha256[file] else {
                throw SettingsPersistenceError.checksumMismatch(file: file)
            }
            verified.append((file, data))
        }

        for (file, data) in verified {
            try fileIO.writeAtomically(data, configRoot.appendingPathComponent(file))
        }
    }

    private var backupsRoot: URL {
        configRoot.appendingPathComponent("backups", isDirectory: true)
    }

    private func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date) + "-" + String(UUID().uuidString.prefix(8))
    }

    private func findDirectory(matching backup: BackupManifest) throws -> URL? {
        let root = backupsRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            let url = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url),
                  let disk = try? Self.decoder.decode(BackupManifest.self, from: data),
                  disk == backup else {
                continue
            }
            return directory
        }
        return nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

import Foundation
import Domain

/// Atomic writer used by backups and settings migration.
public struct SettingsFileIO: Sendable {
    public var writeAtomically: @Sendable (Data, URL) throws -> Void
    public var posixPermissions: @Sendable (URL) throws -> Int

    public init(
        writeAtomically: @escaping @Sendable (Data, URL) throws -> Void,
        posixPermissions: @escaping @Sendable (URL) throws -> Int = SettingsFileIO.readPOSIXPermissions
    ) {
        self.writeAtomically = writeAtomically
        self.posixPermissions = posixPermissions
    }

    public static let live = SettingsFileIO(
        writeAtomically: { data, url in
            try performAtomicWrite(data, to: url)
        },
        posixPermissions: readPOSIXPermissions
    )

    public static func readPOSIXPermissions(at url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attrs[.posixPermissions] as? NSNumber else {
            throw SettingsPersistenceError.validationFailed("settings file permissions are missing")
        }
        return Int(number.uint16Value)
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
            try fileManager.setAttributes(
                [.posixPermissions: SettingsSchema.posixFilePermission],
                ofItemAtPath: url.path
            )
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
        return try createPreMutationBackupUnlocked()
    }

    public func inspectBackups() throws -> [BackupInspection] {
        lock.lock()
        defer { lock.unlock() }
        return try listBackupsUnlocked().map { inspectUnlocked($0) }
    }

    private func createPreMutationBackupUnlocked() throws -> BackupManifest {
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
        return try listBackupsUnlocked()
    }

    private func listBackupsUnlocked() throws -> [BackupManifest] {
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

    public func directoryURL(for backup: BackupManifest) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return try? findDirectory(matching: backup)
    }

    public func restore(_ backup: BackupManifest) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let directory = try findDirectory(matching: backup) else {
            throw SettingsPersistenceError.backupNotFound
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var verified: [(String, Data)] = []
        for file in backup.includedFiles {
            guard SettingsBackupPolicy.includedRelativePaths.contains(file) else {
                throw SettingsPersistenceError.restoreRejected("\(file) is not allowlisted")
            }
            let source = directory.appendingPathComponent(file)
            let staged = staging.appendingPathComponent(file)
            do {
                try FileManager.default.copyItem(at: source, to: staged)
            } catch {
                throw SettingsPersistenceError.restoreRejected("could not stage \(file): \(error.localizedDescription)")
            }
            let data = try Data(contentsOf: staged)
            let digest = SettingsJSON.sha256Hex(data)
            guard digest == backup.sha256[file] else {
                throw SettingsPersistenceError.checksumMismatch(file: file)
            }
            if file == "settings.json" {
                do {
                    let json = try JSONSerialization.jsonObject(with: data)
                    guard json is [String: Any] else {
                        throw SettingsPersistenceError.restoreRejected("settings.json is not an object")
                    }
                } catch let error as SettingsPersistenceError {
                    throw error
                } catch {
                    throw SettingsPersistenceError.restoreRejected("settings.json failed validation in the staging directory")
                }
            }
            verified.append((file, data))
        }

        _ = try createPreMutationBackupUnlocked()

        for (file, data) in verified {
            try fileIO.writeAtomically(data, configRoot.appendingPathComponent(file))
        }
    }

    private func inspectUnlocked(_ backup: BackupManifest) -> BackupInspection {
        guard let directory = try? findDirectory(matching: backup) else {
            return BackupInspection(manifest: backup, checksumValid: false, failureReason: SettingsPersistenceError.backupNotFound.code)
        }
        for file in backup.includedFiles {
            if !SettingsBackupPolicy.includedRelativePaths.contains(file) {
                return BackupInspection(
                    manifest: backup,
                    checksumValid: false,
                    failureReason: SettingsPersistenceError.restoreRejected("\(file) is not allowlisted").code
                )
            }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else {
                return BackupInspection(
                    manifest: backup,
                    checksumValid: false,
                    failureReason: SettingsPersistenceError.restoreRejected("missing \(file)").code
                )
            }
            if SettingsJSON.sha256Hex(data) != backup.sha256[file] {
                return BackupInspection(
                    manifest: backup,
                    checksumValid: false,
                    failureReason: SettingsPersistenceError.checksumMismatch(file: file).code
                )
            }
        }
        return BackupInspection(manifest: backup, checksumValid: true, failureReason: nil)
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

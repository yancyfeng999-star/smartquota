import Foundation
import Domain

/// Thread-safe JSON file I/O primitive for settings storage.
/// Supports dot-notation keys for nested access (e.g., "app.themeMode").
/// Preserves unknown keys on write (OCP-compliant).
///
/// File location: `~/.smartquota/settings.json` (default)
public final class JSONSettingsStore: @unchecked Sendable {

    /// Shared instance using the default file path
    public static let shared = JSONSettingsStore()

    public let fileURL: URL
    private let lock = NSLock()
    private var _lastError: SettingsPersistenceError?
    private var _lastCorruptCopyURL: URL?

    /// Creates a store backed by a JSON file.
    /// - Parameter fileURL: Path to settings file. Defaults to `~/.smartquota/settings.json`.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    /// Last load/write rejection. Corrupt JSON sets this and never overwrites the file.
    public var lastError: SettingsPersistenceError? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    /// Sidecar copy of the last unreadable `settings.json` bytes.
    public var lastCorruptCopyURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _lastCorruptCopyURL
    }

    // MARK: - Public API

    /// Reads a value for the given key path (dot-notation supported).
    /// Returns nil if key doesn't exist, file is missing, or type doesn't match.
    public func read<T>(key: String) -> T? {
        let dict = readFile()
        let raw = resolveRead(dict: dict, keyPath: key.split(separator: ".").map(String.init))
        if let value = raw as? T {
            return value
        }
        if T.self == Int.self, let int = SettingsJSON.intValue(raw) {
            return int as? T
        }
        if T.self == Double.self, let number = SettingsJSON.doubleValue(raw) {
            return number as? T
        }
        return nil
    }

    /// Writes a value for the given key path (dot-notation supported).
    /// Pass nil to remove the key. Creates the file and parent directories if needed.
    /// Refuses to write when the existing file is corrupt so original bytes stay intact.
    public func write(value: Any?, key: String) {
        lock.lock()
        defer { lock.unlock() }

        var dict: [String: Any]
        switch loadUnsafe() {
        case .corrupt(let error):
            _lastError = error
            preserveCorruptCopyIfNeeded()
            return
        case .missing, .empty:
            _lastError = nil
            dict = [SettingsSchema.versionKey: SettingsSchema.currentVersion]
        case .loaded(let existing):
            _lastError = nil
            dict = existing
        }

        let parts = key.split(separator: ".").map(String.init)
        resolveWrite(dict: &dict, keyPath: parts, value: value)
        writeFile(dict)
    }

    /// Returns the full settings dictionary (for migration/debugging).
    /// Corrupt files return `[:]` and record `lastError` without writing.
    public func readAll() -> [String: Any] {
        readFile()
    }

    /// Throws when the file exists, is non-empty, and is not valid JSON.
    public func readAllThrowing() throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        switch loadUnsafe() {
        case .missing, .empty:
            _lastError = nil
            return [:]
        case .loaded(let dict):
            _lastError = nil
            return dict
        case .corrupt(let error):
            _lastError = error
            preserveCorruptCopyIfNeeded()
            throw error
        }
    }

    /// Root `schemaVersion`, or `0` when the key is absent.
    public func schemaVersion() -> Int {
        SettingsJSON.intValue(readAll()[SettingsSchema.versionKey]) ?? 0
    }

    /// Atomically replaces the entire document. Used by migration and explicit restore.
    public func replaceAll(_ dict: [String: Any]) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeFileThrowing(dict)
        _lastError = nil
    }

    // MARK: - Default Path

    public static func defaultFileURL() -> URL {
        _ = AppIdentity.ensureConfigDirectoryMigrated()
        return AppIdentity.settingsFileURL
    }

    // MARK: - File I/O

    private enum LoadResult {
        case missing
        case empty
        case loaded([String: Any])
        case corrupt(SettingsPersistenceError)
    }

    private func readFile() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return readFileUnsafe()
    }

    /// Must be called while holding the lock.
    private func readFileUnsafe() -> [String: Any] {
        switch loadUnsafe() {
        case .missing, .empty:
            _lastError = nil
            return [:]
        case .loaded(let dict):
            _lastError = nil
            return dict
        case .corrupt(let error):
            _lastError = error
            preserveCorruptCopyIfNeeded()
            return [:]
        }
    }

    /// Must be called while holding the lock.
    private func loadUnsafe() -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return .corrupt(.corruptJSON(path: fileURL.path))
        }
        if data.isEmpty {
            return .empty
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            guard let dict = json as? [String: Any] else {
                return .corrupt(.corruptJSON(path: fileURL.path))
            }
            return .loaded(dict)
        } catch {
            return .corrupt(.corruptJSON(path: fileURL.path))
        }
    }

    /// Must be called while holding the lock.
    private func writeFile(_ dict: [String: Any]) {
        try? writeFileThrowing(dict)
    }

    /// Must be called while holding the lock.
    private func writeFileThrowing(_ dict: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(dict) else {
            throw SettingsPersistenceError.validationFailed("settings document is not valid JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try SettingsFileIO.performAtomicWrite(data, to: fileURL)
    }

    /// Must be called while holding the lock.
    private func preserveCorruptCopyIfNeeded() {
        if _lastCorruptCopyURL != nil { return }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        let destDir = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(CrashRecoveryMarker.directoryName, isDirectory: true)
            .appendingPathComponent(CrashRecoveryMarker.corruptDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let dest = destDir.appendingPathComponent("settings.json")
            try SettingsFileIO.performAtomicWrite(data, to: dest)
            _lastCorruptCopyURL = dest
        } catch {
            // Original bytes stay in place even if the sidecar copy cannot be written.
        }
    }

    // MARK: - Key Path Resolution

    private func resolveRead(dict: [String: Any], keyPath: [String]) -> Any? {
        guard let first = keyPath.first else { return nil }

        if keyPath.count == 1 {
            return dict[first]
        }

        guard let nested = dict[first] as? [String: Any] else { return nil }
        return resolveRead(dict: nested, keyPath: Array(keyPath.dropFirst()))
    }

    private func resolveWrite(dict: inout [String: Any], keyPath: [String], value: Any?) {
        guard let first = keyPath.first else { return }

        if keyPath.count == 1 {
            if let value = value {
                dict[first] = value
            } else {
                dict.removeValue(forKey: first)
            }
            return
        }

        var nested = (dict[first] as? [String: Any]) ?? [:]
        resolveWrite(dict: &nested, keyPath: Array(keyPath.dropFirst()), value: value)
        dict[first] = nested
    }
}

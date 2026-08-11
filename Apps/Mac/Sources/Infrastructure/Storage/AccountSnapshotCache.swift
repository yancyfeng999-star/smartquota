import Foundation
import Domain

/// File-backed cache for per-account usage snapshots.
///
/// Each account's snapshot is stored as a separate JSON file in the cache directory.
/// File naming: `{accountId}.json` where accountId uses dot notation (e.g., `claude.personal`).
///
/// Design decisions:
/// - Separate files per account: deleting one account doesn't require rewriting others.
/// - Atomic writes via `Data.write(to:, options: .atomic)`.
/// - `0600` file permissions to protect potentially sensitive data.
/// - Graceful degradation: corrupt/missing files return `nil` instead of crashing.
public final class AccountSnapshotCache: @unchecked Sendable {

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    /// Creates a cache backed by the given directory.
    /// - Parameter directory: Directory for snapshot files. Created if it doesn't exist.
    public init(directory: URL) {
        self.directory = directory

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Creates a cache in the default application support directory.
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport
            .appendingPathComponent("SmartQuota", isDirectory: true)
            .appendingPathComponent("SnapshotCache", isDirectory: true)
        self.init(directory: cacheDir)
    }

    // MARK: - Public API

    /// Saves a snapshot for the given account ID.
    /// Creates the cache directory if needed. Uses atomic write and 0600 permissions.
    public func save(_ snapshot: UsageSnapshot, forAccount accountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let persisted = PersistedUsageSnapshotV1.from(snapshot)
        let data = try encoder.encode(persisted)

        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let fileURL = fileURLFor(accountId)
        try data.write(to: fileURL, options: .atomic)

        // Set 0600 permissions (owner read/write only)
        try fm.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    /// Loads the cached snapshot for the given account ID.
    /// Returns `nil` if the file is missing, corrupt, or unreadable.
    public func load(forAccount accountId: String) -> UsageSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = fileURLFor(accountId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let persisted = try? decoder.decode(PersistedUsageSnapshotV1.self, from: data) else { return nil }
        return persisted.toDomain()
    }

    /// Deletes the cached snapshot for the given account ID.
    /// No-op if the file doesn't exist.
    public func delete(forAccount accountId: String) {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = fileURLFor(accountId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    private func fileURLFor(_ accountId: String) -> URL {
        directory.appendingPathComponent("\(accountId).json")
    }
}

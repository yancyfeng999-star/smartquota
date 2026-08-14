import Foundation

public struct BackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let appVersion: String
    public let createdAt: Date
    public let includedFiles: [String]
    public let sha256: [String: String]

    public init(
        schemaVersion: Int,
        appVersion: String,
        createdAt: Date,
        includedFiles: [String],
        sha256: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.includedFiles = includedFiles
        self.sha256 = sha256
    }
}

public protocol BackupManaging: Sendable {
    func createPreMutationBackup() throws -> BackupManifest
    func listBackups() throws -> [BackupManifest]
    func restore(_ backup: BackupManifest) throws
}

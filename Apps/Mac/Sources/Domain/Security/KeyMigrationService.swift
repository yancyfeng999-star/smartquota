import Foundation

/// 迁移结果
public struct MigrationResult: Sendable {
    public let migrated: [String]
    public let failed: [String]
    public let biometricEnabled: Bool
    
    public init(migrated: [String], failed: [String], biometricEnabled: Bool) {
        self.migrated = migrated
        self.failed = failed
        self.biometricEnabled = biometricEnabled
    }
    
    public var successCount: Int { migrated.count }
    public var failureCount: Int { failed.count }
    public var isComplete: Bool { failed.isEmpty }
}

/// 密钥迁移服务
public final class KeyMigrationService {
    private let oldStore: CredentialRepository
    private let newStore: SecureKeyRepository
    private let authManager: BiometricAuthManager
    
    public init(
        oldStore: CredentialRepository,
        newStore: SecureKeyRepository,
        authManager: BiometricAuthManager
    ) {
        self.oldStore = oldStore
        self.newStore = newStore
        self.authManager = authManager
    }
    
    /// 迁移现有密钥到安全存储
    /// - Parameter enableBiometric: 是否启用生物识别保护
    /// - Returns: 迁移结果
    public func migrateExistingKeys(
        enableBiometric: Bool
    ) async throws -> MigrationResult {
        var migrated: [String] = []
        var failed: [String] = []
        
        // 获取所有现有密钥
        let existingKeys = getExistingKeys()
        
        for key in existingKeys {
            do {
                if let value = oldStore.get(forKey: key) {
                    try await newStore.saveSecure(
                        value,
                        forKey: key,
                        requireBiometric: enableBiometric
                    )
                    migrated.append(key)
                }
            } catch {
                failed.append(key)
            }
        }
        
        return MigrationResult(
            migrated: migrated,
            failed: failed,
            biometricEnabled: enableBiometric
        )
    }
    
    /// 检查是否需要迁移
    public func needsMigration() -> Bool {
        let existingKeys = getExistingKeys()
        for key in existingKeys {
            if oldStore.get(forKey: key) != nil && !newStore.exists(forKey: key) {
                return true
            }
        }
        return false
    }
    
    /// 获取现有密钥列表
    private func getExistingKeys() -> [String] {
        return [
            CredentialKey.githubToken,
            CredentialKey.githubUsername,
        ]
    }
}

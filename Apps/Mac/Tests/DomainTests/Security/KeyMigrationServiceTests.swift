import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("KeyMigrationService Tests")
struct KeyMigrationServiceTests {
    @MainActor
    @Test("检查是否需要迁移")
    func testNeedsMigration() throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let oldStore = UserDefaultsCredentialRepository()
        let newStore = SecureKeychainStore(authManager: authManager)
        
        let service = KeyMigrationService(
            oldStore: oldStore,
            newStore: newStore,
            authManager: authManager
        )
        
        // 清理测试数据
        oldStore.delete(forKey: CredentialKey.githubToken)
        newStore.delete(forKey: CredentialKey.githubToken)
        
        // 没有旧数据时不需要迁移
        #expect(service.needsMigration() == false)
        
        // 有旧数据时需要迁移
        oldStore.save("test-token", forKey: CredentialKey.githubToken)
        #expect(service.needsMigration() == true)
        
        // 清理
        oldStore.delete(forKey: CredentialKey.githubToken)
    }
    
    @MainActor
    @Test("迁移现有密钥")
    func testMigrateExistingKeys() async throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let oldStore = UserDefaultsCredentialRepository()
        let newStore = SecureKeychainStore(authManager: authManager)
        
        let service = KeyMigrationService(
            oldStore: oldStore,
            newStore: newStore,
            authManager: authManager
        )
        
        // 清理测试数据
        oldStore.delete(forKey: CredentialKey.githubToken)
        oldStore.delete(forKey: CredentialKey.githubUsername)
        newStore.delete(forKey: CredentialKey.githubToken)
        newStore.delete(forKey: CredentialKey.githubUsername)
        
        // 准备旧数据
        oldStore.save("test-token", forKey: CredentialKey.githubToken)
        oldStore.save("test-user", forKey: CredentialKey.githubUsername)
        
        // 执行迁移
        let result = try await service.migrateExistingKeys(enableBiometric: false)
        
        // 验证迁移结果
        #expect(result.successCount == 2)
        #expect(result.failureCount == 0)
        #expect(result.isComplete == true)
        #expect(result.biometricEnabled == false)
        
        // 验证数据已迁移
        #expect(newStore.get(forKey: CredentialKey.githubToken) == "test-token")
        #expect(newStore.get(forKey: CredentialKey.githubUsername) == "test-user")
        
        // 清理
        oldStore.delete(forKey: CredentialKey.githubToken)
        oldStore.delete(forKey: CredentialKey.githubUsername)
        newStore.delete(forKey: CredentialKey.githubToken)
        newStore.delete(forKey: CredentialKey.githubUsername)
    }
    
    @MainActor
    @Test("迁移结果统计正确")
    func testMigrationResult() throws {
        let migrated = ["key1", "key2"]
        let failed = ["key3"]
        
        let result = MigrationResult(
            migrated: migrated,
            failed: failed,
            biometricEnabled: true
        )
        
        #expect(result.successCount == 2)
        #expect(result.failureCount == 1)
        #expect(result.isComplete == false)
        #expect(result.biometricEnabled == true)
    }
}

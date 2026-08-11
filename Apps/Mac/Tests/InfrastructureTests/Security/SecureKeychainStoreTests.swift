import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("SecureKeychainStore Tests")
struct SecureKeychainStoreTests {
    @MainActor
    @Test("保存和获取普通密钥")
    func testSaveAndGetNormalKey() throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let store = SecureKeychainStore(authManager: authManager)
        
        let key = "test-normal-key-\(UUID().uuidString)"
        let value = "test-value"
        
        // 保存普通密钥
        store.save(value, forKey: key)
        
        // 获取密钥
        let retrieved = store.get(forKey: key)
        #expect(retrieved == value)
        
        // 清理
        store.delete(forKey: key)
    }
    
    @MainActor
    @Test("检查密钥是否存在")
    func testExists() throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let store = SecureKeychainStore(authManager: authManager)
        
        let key = "test-exists-key-\(UUID().uuidString)"
        
        // 不存在
        #expect(store.exists(forKey: key) == false)
        
        // 保存后存在
        store.save("value", forKey: key)
        #expect(store.exists(forKey: key) == true)
        
        // 删除后不存在
        store.delete(forKey: key)
        #expect(store.exists(forKey: key) == false)
    }
    
    @MainActor
    @Test("设置和检查生物识别要求")
    func testBiometricRequirement() throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let store = SecureKeychainStore(authManager: authManager)
        
        let key = "test-bio-key-\(UUID().uuidString)"
        
        // 默认不需要生物识别
        #expect(store.requiresBiometric(forKey: key) == false)
        
        // 设置需要生物识别
        store.setBiometricRequirement(true, forKey: key)
        #expect(store.requiresBiometric(forKey: key) == true)
        
        // 设置不需要生物识别
        store.setBiometricRequirement(false, forKey: key)
        #expect(store.requiresBiometric(forKey: key) == false)
    }
    
    @MainActor
    @Test("安全保存密钥")
    func testSaveSecure() async throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let store = SecureKeychainStore(authManager: authManager)
        
        let key = "test-secure-key-\(UUID().uuidString)"
        let value = "secure-value"
        
        // 安全保存（不需要生物识别）
        try await store.saveSecure(value, forKey: key, requireBiometric: false)
        
        // 获取密钥
        let retrieved = store.get(forKey: key)
        #expect(retrieved == value)
        
        // 清理
        store.delete(forKey: key)
    }
    
    @MainActor
    @Test("安全获取密钥")
    func testGetSecure() async throws {
        let authService = LocalAuthenticationService.shared
        let authManager = BiometricAuthManager(authService: authService)
        let store = SecureKeychainStore(authManager: authManager)
        
        let key = "test-secure-get-key-\(UUID().uuidString)"
        let value = "secure-get-value"
        
        // 先保存
        store.save(value, forKey: key)
        
        // 安全获取（不需要生物识别）
        let retrieved = try await store.getSecure(forKey: key, requireBiometric: false)
        #expect(retrieved == value)
        
        // 清理
        store.delete(forKey: key)
    }
}

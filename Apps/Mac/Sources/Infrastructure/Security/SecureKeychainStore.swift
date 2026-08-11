import Foundation
import Security
import Domain

/// 安全错误类型
public enum SecurityError: LocalizedError {
    case authenticationFailed
    case encodingFailed
    case accessControlCreationFailed
    case keychainError(OSStatus)
    case notAuthenticated
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "身份验证失败"
        case .encodingFailed:
            return "数据编码失败"
        case .accessControlCreationFailed:
            return "无法创建访问控制"
        case .keychainError(let status):
            return "Keychain 错误: \(status)"
        case .notAuthenticated:
            return "未认证"
        }
    }
}

/// 安全密钥存储实现
public final class SecureKeychainStore: SecureKeyRepository, @unchecked Sendable {
    private let keychain: KeychainSecretStore.Type
    private let authManager: BiometricAuthManager
    private var biometricRequirements: [String: Bool] = [:]
    
    public init(
        keychain: KeychainSecretStore.Type = KeychainSecretStore.self,
        authManager: BiometricAuthManager
    ) {
        self.keychain = keychain
        self.authManager = authManager
    }
    
    // MARK: - CredentialRepository
    
    public func save(_ value: String, forKey key: String) {
        keychain.set(value, account: key)
    }
    
    public func get(forKey key: String) -> String? {
        keychain.get(account: key)
    }
    
    public func delete(forKey key: String) {
        keychain.delete(account: key)
        biometricRequirements.removeValue(forKey: key)
    }
    
    public func exists(forKey key: String) -> Bool {
        keychain.get(account: key) != nil
    }
    
    // MARK: - SecureKeyRepository
    
    public func saveSecure(
        _ value: String,
        forKey key: String,
        requireBiometric: Bool
    ) async throws {
        if requireBiometric {
            // 需要生物识别验证
            guard try await authManager.authenticate(reason: "验证身份以保存密钥") else {
                throw SecurityError.authenticationFailed
            }
        }
        
        if requireBiometric {
            // 使用带访问控制的 Keychain
            try saveWithAccessControl(value, forKey: key)
        } else {
            // 使用普通 Keychain
            keychain.set(value, account: key)
        }
        
        // 记录生物识别要求
        biometricRequirements[key] = requireBiometric
    }
    
    public func getSecure(
        forKey key: String,
        requireBiometric: Bool
    ) async throws -> String? {
        if requireBiometric {
            guard try await authManager.authenticate(reason: "验证身份以访问密钥") else {
                throw SecurityError.authenticationFailed
            }
        }
        
        return keychain.get(account: key)
    }
    
    public func requiresBiometric(forKey key: String) -> Bool {
        biometricRequirements[key] ?? false
    }
    
    public func setBiometricRequirement(_ required: Bool, forKey key: String) {
        biometricRequirements[key] = required
    }
    
    // MARK: - Private
    
    private func saveWithAccessControl(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecurityError.encodingFailed
        }
        
        // 创建访问控制
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.biometryCurrentSet, .userPresence],
            nil
        ) else {
            throw SecurityError.accessControlCreationFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.smartquota.app",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]
        
        // 删除旧条目
        SecItemDelete(query as CFDictionary)
        
        // 添加新条目
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status)
        }
    }
}

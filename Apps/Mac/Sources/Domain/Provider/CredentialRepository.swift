import Foundation
import Mockable

/// Protocol for storing and retrieving credentials.
/// Allows different implementations (UserDefaults, Keychain, etc.) and easy testing.
@Mockable
public protocol CredentialRepository: Sendable {
    /// Saves a credential value for the given key.
    func save(_ value: String, forKey key: String)

    /// Retrieves a credential value for the given key.
    func get(forKey key: String) -> String?

    /// Deletes the credential for the given key.
    func delete(forKey key: String)

    /// Checks if a credential exists for the given key.
    func exists(forKey key: String) -> Bool
}

/// Well-known credential keys
public enum CredentialKey {
    public static let githubToken = "github-copilot-token"
    public static let githubUsername = "github-username"
}

/// 安全凭证仓库协议，支持生物识别保护
public protocol SecureCredentialRepository: CredentialRepository {
    /// 保存需要生物识别的密钥
    func saveSecure(_ value: String, forKey key: String, requireBiometric: Bool) async throws
    
    /// 获取需要生物识别的密钥
    func getSecure(forKey key: String, requireBiometric: Bool) async throws -> String?
    
    /// 检查密钥是否需要生物识别
    func requiresBiometric(forKey key: String) -> Bool
    
    /// 设置密钥的生物识别要求
    func setBiometricRequirement(_ required: Bool, forKey key: String)
}

/// 安全密钥仓库协议（别名）
public typealias SecureKeyRepository = SecureCredentialRepository

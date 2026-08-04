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

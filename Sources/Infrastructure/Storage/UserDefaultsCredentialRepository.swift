import Foundation
import Domain

/// A credential repository that uses UserDefaults for persistence.
/// Simple and suitable for non-sensitive data or when Keychain is not required.
public final class UserDefaultsCredentialRepository: CredentialRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    /// Creates a credential repository with the specified UserDefaults instance.
    /// - Parameters:
    ///   - defaults: The UserDefaults instance to use (defaults to .standard)
    ///   - keyPrefix: A prefix for all keys to avoid collisions (defaults to "com.smartquota.credentials.")
    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "com.smartquota.credentials."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// The shared instance using standard UserDefaults.
    public static let shared = UserDefaultsCredentialRepository()

    // MARK: - CredentialRepository

    public func save(_ value: String, forKey key: String) {
        defaults.set(value, forKey: prefixedKey(key))
    }

    public func get(forKey key: String) -> String? {
        defaults.string(forKey: prefixedKey(key))
    }

    public func delete(forKey key: String) {
        defaults.removeObject(forKey: prefixedKey(key))
    }

    public func exists(forKey key: String) -> Bool {
        defaults.object(forKey: prefixedKey(key)) != nil
    }

    // MARK: - Private

    private func prefixedKey(_ key: String) -> String {
        keyPrefix + key
    }
}

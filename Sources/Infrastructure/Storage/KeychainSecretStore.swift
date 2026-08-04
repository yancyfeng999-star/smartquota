import Foundation
import Security

/// Minimal Keychain wrapper for app secrets (API tokens, cookies).
/// Values are stored per-account under the app bundle service name.
public enum KeychainSecretStore {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.smartquota.app"
    }

    /// Saves a secret, replacing any existing value for the account.
    public static func set(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.credentials.error("Keychain set failed for \(account): \(status)")
        }
    }

    public static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Read Keychain first; if empty, migrate from UserDefaults and clear UD.
    public static func getMigratingFromUserDefaults(
        account: String,
        userDefaults: UserDefaults,
        defaultsKey: String
    ) -> String? {
        if let existing = get(account: account), !existing.isEmpty {
            return existing
        }
        guard let legacy = userDefaults.string(forKey: defaultsKey), !legacy.isEmpty else {
            return nil
        }
        set(legacy, account: account)
        userDefaults.removeObject(forKey: defaultsKey)
        AppLog.credentials.info("Migrated secret \(account) from UserDefaults to Keychain")
        return legacy
    }
}

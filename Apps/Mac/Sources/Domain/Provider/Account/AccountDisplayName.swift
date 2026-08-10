import Foundation

/// Shared display-name resolution used by both `ProviderAccount` and
/// `ProviderAccountState` to avoid duplicating the fallback logic.
enum AccountDisplayName {
    /// Returns the best available display name: label → email → fallbackId.
    static func displayName(label: String, email: String?, fallbackId: String) -> String {
        if !label.isEmpty {
            return label
        }
        return email ?? fallbackId
    }
}

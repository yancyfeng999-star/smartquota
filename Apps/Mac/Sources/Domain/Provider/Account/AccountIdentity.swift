import Foundation

/// Represents the stable identity of an account within a provider.
///
/// The account ID is derived from the provider ID and label (not email),
/// ensuring it remains stable even when the user changes their email.
/// This is the primary key for tracking accounts across sessions.
public struct AccountIdentity: Sendable, Equatable, Hashable {
    /// The provider this account belongs to (e.g., "claude", "codex")
    public let providerId: String

    /// The normalized email (lowercased, trimmed) if available
    public let normalizedEmail: String?

    /// The human-readable label for this account
    public let label: String

    /// A stable account identifier derived from providerId and label.
    ///
    /// The ID is deterministic: given the same providerId and label,
    /// the same accountId is always produced. Email changes do NOT
    /// affect the account ID, ensuring stability across email updates.
    public let accountId: String

    // MARK: - Initialization

    /// Creates an account identity.
    ///
    /// - Parameters:
    ///   - providerId: The provider type (e.g., "claude")
    ///   - email: The email address (will be normalized: lowercased and trimmed)
    ///   - label: Human-readable label for the account (used for stable ID generation)
    public init(
        providerId: String,
        email: String? = nil,
        label: String
    ) {
        self.providerId = providerId
        self.normalizedEmail = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label

        // Generate stable account ID from provider + label
        // Email is NOT used for ID generation to ensure stability
        self.accountId = AccountIdentity.generateAccountId(
            providerId: providerId,
            label: label
        )
    }

    // MARK: - Account ID Generation

    /// Generates a stable account ID from provider and label.
    ///
    /// Uses a hash to produce a fixed-length identifier that is:
    /// - Deterministic: same inputs always produce the same output
    /// - Stable: unaffected by email changes
    /// - Unique: different providers + labels produce different IDs
    private static func generateAccountId(providerId: String, label: String) -> String {
        let input = "\(providerId):\(label)"
        let hash = input.sha256Prefix(16)
        return "\(providerId).\(hash)"
    }
}

// MARK: - String SHA256 Helper

private extension String {
    /// Returns the first 16 hex characters of the SHA-256 hash.
    func sha256Prefix(_ length: Int) -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.prefix(length / 2).map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto

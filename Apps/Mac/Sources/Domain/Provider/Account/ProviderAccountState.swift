import Foundation

/// Represents the complete state of a provider account, combining
/// identity, connection state, and display information.
///
/// This is the aggregate root for account state management,
/// used by the multi-account coordinator to track all accounts.
public struct ProviderAccountState: Sendable, Equatable, Identifiable {
    /// The stable identity of this account
    public let identity: AccountIdentity

    /// The current connection state
    public var connectionState: AccountConnectionState

    /// Human-readable label for display
    public var label: String

    /// Optional email for display
    public var email: String?

    /// Optional organization for display
    public var organization: String?

    /// The last usage snapshot captured for this account
    public var lastSnapshot: UsageSnapshot?

    /// When the last snapshot was captured
    public var lastSnapshotTime: Date?

    // MARK: - Identifiable

    /// The unique identifier, matching `identity.accountId` (format: `{providerId}.{hash}`).
    public var id: String {
        identity.accountId
    }

    // MARK: - Initialization

    /// Creates a provider account state.
    ///
    /// - Parameters:
    ///   - identity: The stable account identity
    ///   - connectionState: Current connection state
    ///   - label: Human-readable label
    ///   - email: Optional email
    ///   - organization: Optional organization
    ///   - lastSnapshot: Optional last usage snapshot
    ///   - lastSnapshotTime: Optional timestamp for last snapshot
    public init(
        identity: AccountIdentity,
        connectionState: AccountConnectionState,
        label: String,
        email: String? = nil,
        organization: String? = nil,
        lastSnapshot: UsageSnapshot? = nil,
        lastSnapshotTime: Date? = nil
    ) {
        self.identity = identity
        self.connectionState = connectionState
        self.label = label
        self.email = email
        self.organization = organization
        self.lastSnapshot = lastSnapshot
        self.lastSnapshotTime = lastSnapshotTime
    }

    // MARK: - Display

    /// Best available display name: label first, then email, then account ID.
    /// Delegates to the same logic used by `ProviderAccount` for consistency.
    public var displayName: String {
        AccountDisplayName.displayName(label: label, email: email, fallbackId: identity.accountId)
    }

    /// The uppercased first character of the display name, for avatar circles.
    public var initialLetter: String {
        String(displayName.prefix(1)).uppercased()
    }

    // MARK: - State Transitions

    /// Transitions to connected state.
    public mutating func connect() {
        connectionState = .connected
    }

    /// Transitions to disconnected state.
    public mutating func disconnect() {
        connectionState = .disconnected
    }

    /// Transitions to pending confirmation state.
    public mutating func pendConfirmation() {
        connectionState = .pendingConfirmation
    }
}

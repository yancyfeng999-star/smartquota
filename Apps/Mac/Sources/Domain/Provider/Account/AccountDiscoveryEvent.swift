import Foundation

/// Events that drive the account discovery state machine.
///
/// The coordinator processes these events to transition accounts
/// between connection states (connected, disconnected, pendingConfirmation).
public enum AccountDiscoveryEvent: Sendable {
    /// A new snapshot arrived from a provider refresh.
    /// - snapshot: The usage snapshot containing account information
    /// - kind: Whether this is an interactive or background refresh
    case ingest(snapshot: UsageSnapshot, kind: RefreshKind)

    /// User confirms a pending account, promoting it to connected.
    /// - accountId: The account to confirm
    case confirm(accountId: String)

    /// User ignores a pending account, transitioning it to disconnected.
    /// - accountId: The account to ignore
    case ignore(accountId: String)

    /// User selects an account as the active account for the provider.
    /// - accountId: The account to select as active
    case select(accountId: String)

    /// User deletes an account from the provider.
    /// - accountId: The account to delete
    case delete(accountId: String)
}

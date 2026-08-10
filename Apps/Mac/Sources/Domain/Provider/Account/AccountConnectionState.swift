import Foundation

/// Represents the connection state of an account within a provider.
///
/// This tracks whether the account is actively connected, disconnected,
/// or pending user confirmation (e.g., after discovery via CLI).
public enum AccountConnectionState: Sendable, Equatable {
    /// The account is actively connected and participating in monitoring.
    case connected

    /// The account was previously connected but is now disconnected.
    /// Retains last snapshot for historical reference.
    case disconnected

    /// Discovered during interactive refresh; awaiting user confirmation.
    case pendingConfirmation

    /// Whether the account is in an active state (connected or pending).
    public var isActive: Bool {
        switch self {
        case .connected, .pendingConfirmation:
            return true
        case .disconnected:
            return false
        }
    }
}

import Foundation

/// Represents the connection state of an account within a provider.
///
/// This tracks whether the account is actively connected, disconnected,
/// or pending user confirmation (e.g., after discovery via CLI).
public enum AccountConnectionState: Sendable, Equatable, Codable {
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

// MARK: - Display Helpers (L10n keys)

extension AccountConnectionState {
    /// The localization key for the display label of this state.
    public var l10nKey: String {
        switch self {
        case .connected: return "account.connected"
        case .disconnected: return "account.disconnected"
        case .pendingConfirmation: return "account.pending"
        }
    }
}

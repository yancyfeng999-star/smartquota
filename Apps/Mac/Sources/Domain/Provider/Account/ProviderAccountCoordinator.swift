import Foundation

/// Coordinates account discovery and state management for a multi-account provider.
///
/// The coordinator implements a state machine that processes `AccountDiscoveryEvent`s
/// to manage the lifecycle of provider accounts:
/// - **Discovery**: New accounts are identified from snapshot metadata
/// - **Confirmation**: Users confirm or ignore newly discovered accounts
/// - **Selection**: Users choose which account is active
/// - **Deletion**: Users remove accounts and clean up associated data
///
/// The coordinator ensures:
/// - Email normalization prevents duplicate accounts (case/whitespace variants)
/// - First interactive refresh auto-creates the account as connected
/// - Background refreshes never auto-add accounts
/// - Signed-out accounts retain their last snapshot
@MainActor
public final class ProviderAccountCoordinator {
    // MARK: - State

    /// All tracked accounts for the provider, keyed by account ID.
    private var accountStates: [String: ProviderAccountState] = [:]

    /// The currently active account ID.
    private(set) var activeAccountId: String?

    /// Accounts awaiting user confirmation.
    private(set) var pendingConfirmations: [ProviderAccountState] = []

    /// The provider ID this coordinator manages.
    public let providerId: String

    /// Repository for persisting account configurations.
    private let settingsRepository: any MultiAccountSettingsRepository

    // MARK: - Computed Properties

    /// All accounts tracked by this coordinator.
    public var accounts: [ProviderAccountState] {
        Array(accountStates.values)
    }

    /// The currently active account (if any).
    public var activeAccount: ProviderAccountState? {
        guard let activeAccountId else { return nil }
        return accountStates[activeAccountId]
    }

    // MARK: - Initialization

    /// Creates a coordinator for the specified provider.
    /// - Parameters:
    ///   - providerId: The provider this coordinator manages (e.g., "claude", "codex")
    ///   - settingsRepository: Repository for persisting account configurations
    public init(providerId: String, settingsRepository: any MultiAccountSettingsRepository) {
        self.providerId = providerId
        self.settingsRepository = settingsRepository

        // Load persisted accounts from settings
        let configs = settingsRepository.accounts(forProvider: providerId)
        for config in configs {
            let identity = AccountIdentity(
                providerId: providerId,
                email: config.email,
                label: config.label
            )
            let state = ProviderAccountState(
                identity: identity,
                connectionState: .connected,
                label: config.label,
                email: config.email,
                organization: config.organization
            )
            accountStates[identity.accountId] = state
        }

        // Restore active account selection
        if let savedActiveId = settingsRepository.activeAccountId(forProvider: providerId),
           accountStates[savedActiveId] != nil {
            activeAccountId = savedActiveId
        } else if let firstAccount = accountStates.values.first {
            activeAccountId = firstAccount.id
        }
    }

    // MARK: - Event Processing

    /// Processes an account discovery event and returns the resulting state.
    /// - Parameter event: The event to process
    /// - Returns: The affected account state (if any) after processing
    @discardableResult
    public func process(_ event: AccountDiscoveryEvent) -> ProviderAccountState? {
        switch event {
        case let .ingest(snapshot, kind):
            return handleIngest(snapshot: snapshot, kind: kind)
        case let .confirm(accountId):
            return handleConfirm(accountId: accountId)
        case let .ignore(accountId):
            return handleIgnore(accountId: accountId)
        case let .select(accountId):
            return handleSelect(accountId: accountId)
        case let .delete(accountId):
            return handleDelete(accountId: accountId)
        }
    }

    // MARK: - Ingest Handler

    /// Handles an incoming snapshot from a provider refresh.
    private func handleIngest(snapshot: UsageSnapshot, kind: RefreshKind) -> ProviderAccountState? {
        // Derive identity from snapshot metadata
        let email = snapshot.accountEmail
        let label = deriveLabel(from: snapshot)

        let identity = AccountIdentity(
            providerId: providerId,
            email: email,
            label: label
        )

        // Check if this is a known account (by identity)
        if let existing = findExistingAccount(with: identity) {
            return handleKnownAccount(existing: existing, snapshot: snapshot, kind: kind)
        }

        // Check if this is a known email (different identity, same normalized email)
        if let normalizedEmail = identity.normalizedEmail,
           let existingByEmail = findExistingAccount(byEmail: normalizedEmail) {
            // Update email if it changed, but don't create duplicate
            return handleEmailVariant(existing: existingByEmail, snapshot: snapshot)
        }

        // New account discovered
        return handleNewAccountDiscovery(identity: identity, snapshot: snapshot, kind: kind)
    }

    /// Handles a snapshot for a known account (same identity).
    private func handleKnownAccount(
        existing: ProviderAccountState,
        snapshot: UsageSnapshot,
        kind: RefreshKind
    ) -> ProviderAccountState? {
        var updated = existing
        updated.lastSnapshot = snapshot
        updated.lastSnapshotTime = snapshot.capturedAt

        // Update email/org if snapshot provides them
        if let email = snapshot.accountEmail {
            updated.email = email
        }
        if let org = snapshot.accountOrganization {
            updated.organization = org
        }

        accountStates[updated.id] = updated
        return updated
    }

    /// Handles a snapshot with a known email variant (case/whitespace difference).
    private func handleEmailVariant(
        existing: ProviderAccountState,
        snapshot: UsageSnapshot
    ) -> ProviderAccountState? {
        // Don't create duplicate - just update the existing account
        var updated = existing
        updated.lastSnapshot = snapshot
        updated.lastSnapshotTime = snapshot.capturedAt
        accountStates[updated.id] = updated
        return updated
    }

    /// Handles discovery of a new account.
    private func handleNewAccountDiscovery(
        identity: AccountIdentity,
        snapshot: UsageSnapshot,
        kind: RefreshKind
    ) -> ProviderAccountState? {
        // Background refreshes never auto-add accounts
        guard kind == .interactive else {
            // Still track as pending if not already
            if !pendingContains(identity: identity) {
                let pending = ProviderAccountState(
                    identity: identity,
                    connectionState: .pendingConfirmation,
                    label: identity.label,
                    email: snapshot.accountEmail,
                    organization: snapshot.accountOrganization,
                    lastSnapshot: snapshot,
                    lastSnapshotTime: snapshot.capturedAt
                )
                pendingConfirmations.append(pending)
            }
            return nil
        }

        // Interactive refresh: if this is the first account, auto-create as connected
        if accountStates.isEmpty {
            let state = createConnectedAccount(
                identity: identity,
                snapshot: snapshot
            )
            accountStates[state.id] = state
            activeAccountId = state.id
            persistAccount(state)
            return state
        }

        // Subsequent accounts: add to pending confirmation
        if !pendingContains(identity: identity) {
            let pending = ProviderAccountState(
                identity: identity,
                connectionState: .pendingConfirmation,
                label: identity.label,
                email: snapshot.accountEmail,
                organization: snapshot.accountOrganization,
                lastSnapshot: snapshot,
                lastSnapshotTime: snapshot.capturedAt
            )
            pendingConfirmations.append(pending)
        }
        return nil
    }

    // MARK: - Confirm Handler

    /// Confirms a pending account, promoting it to connected.
    private func handleConfirm(accountId: String) -> ProviderAccountState? {
        guard let index = pendingConfirmations.firstIndex(where: { $0.id == accountId }) else {
            return nil
        }

        var confirmed = pendingConfirmations.remove(at: index)
        confirmed.connect()
        accountStates[confirmed.id] = confirmed
        persistAccount(confirmed)

        // If no active account, set this as active
        if activeAccountId == nil {
            activeAccountId = confirmed.id
        }

        return confirmed
    }

    // MARK: - Ignore Handler

    /// Ignores a pending account, transitioning it to disconnected.
    private func handleIgnore(accountId: String) -> ProviderAccountState? {
        guard let index = pendingConfirmations.firstIndex(where: { $0.id == accountId }) else {
            return nil
        }

        var ignored = pendingConfirmations.remove(at: index)
        ignored.disconnect()
        // Store as disconnected account (retains snapshot for history)
        accountStates[ignored.id] = ignored
        return ignored
    }

    // MARK: - Select Handler

    /// Selects an account as the active account.
    private func handleSelect(accountId: String) -> ProviderAccountState? {
        guard accountStates[accountId] != nil else {
            return nil
        }

        activeAccountId = accountId
        settingsRepository.setActiveAccountId(accountId, forProvider: providerId)
        return accountStates[accountId]
    }

    // MARK: - Delete Handler

    /// Deletes an account and cleans up associated data.
    private func handleDelete(accountId: String) -> ProviderAccountState? {
        guard let removed = accountStates.removeValue(forKey: accountId) else {
            // Also check pending confirmations
            if let index = pendingConfirmations.firstIndex(where: { $0.id == accountId }) {
                return pendingConfirmations.remove(at: index)
            }
            return nil
        }

        // Clean up persisted config
        settingsRepository.removeAccount(accountId: accountId, forProvider: providerId)

        // If we deleted the active account, switch to another
        if activeAccountId == accountId {
            activeAccountId = accountStates.keys.first
            settingsRepository.setActiveAccountId(activeAccountId, forProvider: providerId)
        }

        return removed
    }

    // MARK: - Helpers

    /// Derives a label from a snapshot's metadata.
    private func deriveLabel(from snapshot: UsageSnapshot) -> String {
        if let email = snapshot.accountEmail {
            return email
        }
        if let externalId = snapshot.accountExternalId {
            return externalId
        }
        return "Account"
    }

    /// Finds an existing account by identity match.
    private func findExistingAccount(with identity: AccountIdentity) -> ProviderAccountState? {
        accountStates.values.first { $0.identity == identity }
    }

    /// Finds an existing account by normalized email.
    private func findExistingAccount(byEmail normalizedEmail: String) -> ProviderAccountState? {
        accountStates.values.first { account in
            guard let accountEmail = account.email else { return false }
            return accountEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedEmail
        }
    }

    /// Checks if an identity is already in pending confirmations.
    private func pendingContains(identity: AccountIdentity) -> Bool {
        pendingConfirmations.contains { $0.identity == identity }
    }

    /// Creates a connected account state from an identity and snapshot.
    private func createConnectedAccount(
        identity: AccountIdentity,
        snapshot: UsageSnapshot
    ) -> ProviderAccountState {
        ProviderAccountState(
            identity: identity,
            connectionState: .connected,
            label: identity.label,
            email: snapshot.accountEmail,
            organization: snapshot.accountOrganization,
            lastSnapshot: snapshot,
            lastSnapshotTime: snapshot.capturedAt
        )
    }

    /// Persists an account configuration to the settings repository.
    private func persistAccount(_ state: ProviderAccountState) {
        let config = ProviderAccountConfig(
            accountId: state.id,
            label: state.label,
            email: state.email,
            organization: state.organization
        )
        settingsRepository.addAccount(config, forProvider: providerId)
    }
}

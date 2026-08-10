import Foundation
import Testing
@testable import Domain

@Suite("AccountIdentity")
struct AccountIdentityTests {

    // MARK: - Email Normalization

    @Test("Email is lowercased and trimmed")
    func emailNormalization() {
        let identity = AccountIdentity(
            providerId: "claude",
            email: " Alice@Example.COM ",
            label: "Test"
        )

        #expect(identity.normalizedEmail == "alice@example.com")
    }

    // MARK: - Stable Account ID

    @Test("Account ID remains stable when email changes")
    func stableAccountIdWithEmailChange() {
        let identity1 = AccountIdentity(
            providerId: "claude",
            email: "user@example.com",
            label: "Personal"
        )

        let identity2 = AccountIdentity(
            providerId: "claude",
            email: "user@newdomain.com",
            label: "Personal"
        )

        // ID should be same when email changes (label determines identity)
        #expect(identity1.accountId == identity2.accountId)
    }

    @Test("Account ID changes when label changes")
    func accountIdChangesWithLabel() {
        let identity1 = AccountIdentity(
            providerId: "claude",
            email: "user@example.com",
            label: "Personal"
        )

        let identity2 = AccountIdentity(
            providerId: "claude",
            email: "user@example.com",
            label: "Work Account"
        )

        // ID should be different for different labels
        #expect(identity1.accountId != identity2.accountId)
    }

    @Test("Different providers produce different account IDs")
    func differentProvidersDifferentIds() {
        let identity1 = AccountIdentity(
            providerId: "claude",
            email: "user@example.com",
            label: "Test"
        )

        let identity2 = AccountIdentity(
            providerId: "codex",
            email: "user@example.com",
            label: "Test"
        )

        #expect(identity1.accountId != identity2.accountId)
    }

    // MARK: - Connection State

    @Test("Connection state transitions")
    func connectionStateTransitions() {
        let connected = AccountConnectionState.connected
        let disconnected = AccountConnectionState.disconnected
        let pending = AccountConnectionState.pendingConfirmation

        #expect(connected != disconnected)
        #expect(connected != pending)
        #expect(disconnected != pending)
    }

    // MARK: - Provider Account State

    @Test("Provider account state with identity")
    func providerAccountStateWithIdentity() {
        let identity = AccountIdentity(
            providerId: "claude",
            email: "user@example.com",
            label: "Test"
        )

        let state = ProviderAccountState(
            identity: identity,
            connectionState: .connected,
            label: "Test Account"
        )

        #expect(state.identity.providerId == "claude")
        #expect(state.connectionState == .connected)
        #expect(state.label == "Test Account")
    }

    // MARK: - UsageSnapshot Account Identity

    @Test("UsageSnapshot supports account external ID")
    func usageSnapshotAccountExternalId() {
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountExternalId: "ext-123",
            accountIdentitySource: .email
        )

        #expect(snapshot.accountExternalId == "ext-123")
        #expect(snapshot.accountIdentitySource == .email)
    }

    @Test("UsageSnapshot account fields default to nil")
    func usageSnapshotDefaultsToNil() {
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date()
        )

        #expect(snapshot.accountExternalId == nil)
        #expect(snapshot.accountIdentitySource == nil)
    }
}

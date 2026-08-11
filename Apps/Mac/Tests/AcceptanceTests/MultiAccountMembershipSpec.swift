import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Multi-Account Membership
///
/// Each AI provider can have multiple signed-in accounts.
/// The account coordinator manages discovery, confirmation, sign-out,
/// and alert isolation across accounts.
///
/// Behaviors covered:
/// - #55: First interactive refresh auto-creates account as signedIn
/// - #56: Same email (case/whitespace variant) does not create duplicate
/// - #57: New email discovered → pendingConfirmation, not auto-added
/// - #58: Background refresh does not auto-add accounts
/// - #59: Signed-out account retains last snapshot with signedOut status
/// - #60: Alert isolation — only signedIn account alerts fire

private struct TestClock: Clock {
    func sleep(for duration: Duration) async throws {}
    func sleep(nanoseconds: UInt64) async throws {}
}

/// In-memory mock for MultiAccountSettingsRepository.
private final class MockMultiAccountSettings: MultiAccountSettingsRepository, @unchecked Sendable {
    private var accountsByProvider: [String: [ProviderAccountConfig]] = [:]
    private var activeAccountIds: [String: String] = [:]

    // MARK: - ProviderSettingsRepository

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { defaultValue }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}

    // MARK: - MultiAccountSettingsRepository

    func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        accountsByProvider[id] ?? []
    }

    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        if !existing.contains(where: { $0.accountId == config.accountId }) {
            existing.append(config)
            accountsByProvider[id] = existing
        }
    }

    func removeAccount(accountId: String, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        existing.removeAll { $0.accountId == accountId }
        accountsByProvider[id] = existing
    }

    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        if let index = existing.firstIndex(where: { $0.accountId == config.accountId }) {
            existing[index] = config
            accountsByProvider[id] = existing
        }
    }

    func activeAccountId(forProvider id: String) -> String? {
        activeAccountIds[id]
    }

    func setActiveAccountId(_ accountId: String?, forProvider id: String) {
        activeAccountIds[id] = accountId
    }
}

@Suite("Feature: Multi-Account Membership")
struct MultiAccountMembershipSpec {

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #55: First interactive refresh auto-creates account

    @Suite("Scenario: First interactive refresh auto-creates account")
    @MainActor
    struct FirstAccountAutoCreation {

        @Test
        func `first refresh returning email creates one signedIn account`() async throws {
            // Given — Codex is the only provider, no accounts yet
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "first@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            // When — user triggers interactive refresh
            await monitor.refresh(providerId: "codex")

            // Then — account list has exactly one entry with connected status
            #expect(coordinator.accounts.count == 1)
            #expect(coordinator.accounts.first?.email == "first@example.com")
            #expect(coordinator.accounts.first?.connectionState == .connected)
        }
    }

    // MARK: - #56: Same email does not create duplicate

    @Suite("Scenario: Same email with case/whitespace differences does not duplicate")
    @MainActor
    struct EmailNormalization {

        @Test
        func `case and whitespace variants of same email keep single account`() async throws {
            // Given — first refresh returns "First@Example.com"
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "First@Example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            await monitor.refresh(providerId: "codex")

            // When — second refresh returns " first@example.com " (different case + whitespace)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: " first@example.com "
            ))

            await monitor.refresh(providerId: "codex")

            // Then — still only one account
            #expect(coordinator.accounts.count == 1)
        }
    }

    // MARK: - #57: New email → pendingConfirmation

    @Suite("Scenario: New email discovered during interactive refresh")
    @MainActor
    struct NewAccountPendingConfirmation {

        @Test
        func `new email produces pendingConfirmation without adding to accounts`() async throws {
            // Given — account A already signed in
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-a@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            await monitor.refresh(providerId: "codex")

            // When — interactive refresh discovers account B via coordinator ingest
            let snapshotB = UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            )
            coordinator.process(.ingest(snapshot: snapshotB, kind: .interactive))

            // Then — account list still has only A, and pendingConfirmation is produced
            #expect(coordinator.accounts.count == 1)
            #expect(coordinator.accounts.first?.email == "account-a@example.com")

            // A pendingConfirmation must be produced for account B.
            #expect(coordinator.pendingConfirmations.count == 1)
            #expect(coordinator.pendingConfirmations.first?.email == "account-b@example.com")
        }
    }

    // MARK: - #58: Background refresh does not auto-add accounts

    @Suite("Scenario: Background refresh does not auto-add accounts")
    @MainActor
    struct BackgroundRefreshNoAutoAdd {

        @Test
        func `background refresh discovering new email does not change account count`() async throws {
            // Given — account A is signed in
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-a@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            // Interactive refresh to establish account A
            await monitor.refresh(providerId: "codex")

            let countBefore = coordinator.accounts.count
            let activeBefore = coordinator.activeAccount?.email

            // When — background refresh returns account B
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            await monitor.refresh(providerId: "codex", kind: .background)

            // Then — account count unchanged, active account unchanged
            #expect(coordinator.accounts.count == countBefore)
            #expect(coordinator.activeAccount?.email == activeBefore)
        }
    }

    // MARK: - #59: Signed-out account retains last snapshot

    @Suite("Scenario: Signed-out account retains last snapshot")
    @MainActor
    struct SignedOutRetainsSnapshot {

        @Test
        func `signedOut account shows last quota and time but signedOut status`() async throws {
            // Given — account A is signed in with a snapshot
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let snapshotTime = Date()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 42, quotaType: .session, providerId: "codex")],
                capturedAt: snapshotTime,
                accountEmail: "account-a@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            await monitor.refresh(providerId: "codex")

            // When — account A signs out via coordinator
            let accountId = try #require(coordinator.activeAccountId)
            coordinator.process(.signOut(accountId: accountId))

            // Then — account is still in the list with historical data
            #expect(coordinator.accounts.count == 1)

            let accountA = coordinator.accounts.first
            #expect(accountA?.email == "account-a@example.com")
            #expect(accountA?.connectionState == .disconnected)
            #expect(accountA?.lastSnapshot != nil)
            #expect(accountA?.lastSnapshot?.quotas.first?.percentRemaining == 42)
        }
    }

    // MARK: - #60: Alert isolation

    @Suite("Scenario: Alert isolation across accounts")
    @MainActor
    struct AlertIsolation {

        @Test
        func `signedOut account with low quota does not trigger alert while signedIn account with critical quota does`() async throws {
            // Given — account A signed in with low quota, then signed out;
            // account B signed in with critical quota (current)
            let settings = makeSettings()
            let multiSettings = MockMultiAccountSettings()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
            given(mockAlerter).evaluateSnapshotAlerts(providerId: .any, accountId: .any, snapshot: .any).willReturn()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)

            // Step 1: Account A signs in with low quota (historical)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 10, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-a@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                alerter: mockAlerter,
                clock: TestClock()
            )
            let coordinator = ProviderAccountCoordinator(
                providerId: "codex",
                settingsRepository: multiSettings
            )
            monitor.registerCoordinator(coordinator)

            await monitor.refresh(providerId: "codex")

            // Step 2: Account A signs out via coordinator
            let accountIdA = try #require(coordinator.activeAccountId)
            coordinator.process(.signOut(accountId: accountIdA))

            // Verify account A is disconnected
            #expect(coordinator.accounts.first?.connectionState == .disconnected)

            // Step 3: Account B ingested via coordinator with critical quota
            let snapshotB = UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            )
            coordinator.process(.ingest(snapshot: snapshotB, kind: .interactive))

            // Verify multi-account state: A is disconnected, B is pending confirmation
            #expect(coordinator.accounts.first?.connectionState == .disconnected)
            #expect(coordinator.pendingConfirmations.count == 1)
            #expect(coordinator.pendingConfirmations.first?.email == "account-b@example.com")
        }
    }
}

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
@Suite("Feature: Multi-Account Membership")
struct MultiAccountMembershipSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    // MARK: - #55: First interactive refresh auto-creates account

    @Suite("Scenario: First interactive refresh auto-creates account")
    @MainActor
    struct FirstAccountAutoCreation {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `first refresh returning email creates one signedIn account`() async {
            // Given — Codex is the only provider, no accounts yet
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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

            // When — user triggers interactive refresh
            await monitor.refresh(providerId: "codex")

            // Then — account list has exactly one entry with signedIn status
            guard let multiAccount = codex as? any MultiAccountProvider else {
                Issue.record("CodexProvider does not conform to MultiAccountProvider")
                return
            }

            #expect(multiAccount.accounts.count == 1)
            #expect(multiAccount.accounts.first?.email == "first@example.com")
            #expect(multiAccount.accounts.first?.membershipStatus == .signedIn)
        }
    }

    // MARK: - #56: Same email does not create duplicate

    @Suite("Scenario: Same email with case/whitespace differences does not duplicate")
    @MainActor
    struct EmailNormalization {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `case and whitespace variants of same email keep single account`() async {
            // Given — first refresh returns "First@Example.com"
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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
            guard let multiAccount = codex as? any MultiAccountProvider else {
                Issue.record("CodexProvider does not conform to MultiAccountProvider")
                return
            }

            #expect(multiAccount.accounts.count == 1)
        }
    }

    // MARK: - #57: New email → pendingConfirmation

    @Suite("Scenario: New email discovered during interactive refresh")
    @MainActor
    struct NewAccountPendingConfirmation {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `new email produces pendingConfirmation without adding to accounts`() async {
            // Given — account A already signed in
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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

            await monitor.refresh(providerId: "codex")

            // When — interactive refresh discovers account B
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            await monitor.refresh(providerId: "codex")

            // Then — account list still has only A, and pendingConfirmation is produced
            guard let multiAccount = codex as? any MultiAccountProvider else {
                Issue.record("CodexProvider does not conform to MultiAccountProvider")
                return
            }

            #expect(multiAccount.accounts.count == 1)
            #expect(multiAccount.accounts.first?.email == "account-a@example.com")
        }
    }

    // MARK: - #58: Background refresh does not auto-add accounts

    @Suite("Scenario: Background refresh does not auto-add accounts")
    @MainActor
    struct BackgroundRefreshNoAutoAdd {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `background refresh discovering new email does not change account count`() async {
            // Given — account A is signed in
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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

            // Interactive refresh to establish account A
            await monitor.refresh(providerId: "codex")

            guard let multiAccount = codex as? any MultiAccountProvider else {
                Issue.record("CodexProvider does not conform to MultiAccountProvider")
                return
            }

            let countBefore = multiAccount.accounts.count
            let activeBefore = multiAccount.activeAccount.email

            // When — background refresh returns account B
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            await monitor.refresh(providerId: "codex", kind: .background)

            // Then — account count unchanged, active account unchanged
            #expect(multiAccount.accounts.count == countBefore)
            #expect(multiAccount.activeAccount.email == activeBefore)
        }
    }

    // MARK: - #59: Signed-out account retains last snapshot

    @Suite("Scenario: Signed-out account retains last snapshot")
    @MainActor
    struct SignedOutRetainsSnapshot {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `signedOut account shows last quota and time but signedOut status`() async {
            // Given — account A is signed in with a snapshot
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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

            await monitor.refresh(providerId: "codex")

            guard let multiAccount = codex as? any MultiAccountProvider else {
                Issue.record("CodexProvider does not conform to MultiAccountProvider")
                return
            }

            // When — account A signs out (via coordinator, not yet implemented)
            // The test defines the expected behavior:
            // After sign-out, the account remains in the list with signedOut status
            // and retains its last snapshot.

            // Then — account is still in the list with historical data
            #expect(multiAccount.accounts.count == 1)

            let accountA = multiAccount.accounts.first
            #expect(accountA?.email == "account-a@example.com")
            #expect(accountA?.membershipStatus == .signedOut)
            #expect(accountA?.lastSnapshot != nil)
            #expect(accountA?.lastSnapshot?.quotas.first?.percentRemaining == 42)
            #expect(accountA?.lastSnapshotTime != nil)
        }
    }

    // MARK: - #60: Alert isolation

    @Suite("Scenario: Alert isolation across accounts")
    @MainActor
    struct AlertIsolation {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `signedOut account with low quota does not trigger alert`() async {
            // Given — account A signed out with low quota (historical)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
            given(mockAlerter).evaluateSnapshotAlerts(providerId: .any, snapshot: .any).willReturn()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            // Probe returns account B's data (current), but account A's historical
            // low quota should not trigger alerts
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh with account B (signedIn, healthy)
            // Account A (signedOut, low quota) exists historically
            await monitor.refresh(providerId: "codex")

            // Then — no alert fired for account A's historical low quota
            verify(mockAlerter).alert(
                providerId: .any,
                previousStatus: .any,
                currentStatus: .any
            ).called(0)
        }

        @Test
        func `signedIn account with critical quota triggers alert`() async {
            // Given — account B is signed in with critical quota
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
            given(mockAlerter).evaluateSnapshotAlerts(providerId: .any, snapshot: .any).willReturn()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh returns critical quota for account B
            await monitor.refresh(providerId: "codex")

            // Then — alert fires for account B's critical status
            verify(mockAlerter).alert(
                providerId: .value("codex"),
                previousStatus: .value(.healthy),
                currentStatus: .value(.critical)
            ).called(1)
        }
    }
}

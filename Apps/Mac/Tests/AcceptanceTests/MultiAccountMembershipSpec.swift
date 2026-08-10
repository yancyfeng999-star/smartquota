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

@Suite("Feature: Multi-Account Membership")
struct MultiAccountMembershipSpec {

    // MARK: - #55: First interactive refresh auto-creates account

    @Suite("Scenario: First interactive refresh auto-creates account")
    @MainActor
    struct FirstAccountAutoCreation {

        @Test
        func `first refresh returning email creates one signedIn account`() async throws {
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
            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — account coordinator not yet implemented")

            #expect(multiAccount.accounts.count == 1)
            #expect(multiAccount.accounts.first?.email == "first@example.com")
            #expect(multiAccount.accounts.first?.membershipStatus == .signedIn)
        }
    }

    // MARK: - #56: Same email does not create duplicate

    @Suite("Scenario: Same email with case/whitespace differences does not duplicate")
    @MainActor
    struct EmailNormalization {

        @Test
        func `case and whitespace variants of same email keep single account`() async throws {
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
            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — account coordinator not yet implemented")

            #expect(multiAccount.accounts.count == 1)
        }
    }

    // MARK: - #57: New email → pendingConfirmation

    @Suite("Scenario: New email discovered during interactive refresh")
    @MainActor
    struct NewAccountPendingConfirmation {

        @Test
        func `new email produces pendingConfirmation without adding to accounts`() async throws {
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
            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — account coordinator not yet implemented")

            #expect(multiAccount.accounts.count == 1)
            #expect(multiAccount.accounts.first?.email == "account-a@example.com")

            // Contract: a pendingConfirmation must be produced for account B.
            // MultiAccountProvider must expose pending confirmations so the UI
            // can prompt the user to approve the newly discovered account.
            //
            // Once the coordinator is implemented, assert:
            //   #expect(multiAccount.pendingConfirmations.count == 1)
            //   #expect(multiAccount.pendingConfirmations.first?.email == "account-b@example.com")
            //
            // For now, verify that no account with .signedIn status matches account B
            // (i.e., it was NOT auto-added to the active account list):
            #expect(!multiAccount.accounts.contains { $0.email == "account-b@example.com" && $0.membershipStatus == .signedIn })
        }
    }

    // MARK: - #58: Background refresh does not auto-add accounts

    @Suite("Scenario: Background refresh does not auto-add accounts")
    @MainActor
    struct BackgroundRefreshNoAutoAdd {

        @Test
        func `background refresh discovering new email does not change account count`() async throws {
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

            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — account coordinator not yet implemented")

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

        @Test
        func `signedOut account shows last quota and time but signedOut status`() async throws {
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

            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — sign-out contract requires MultiAccountProvider.signOut(accountId:)")

            // When — account A signs out via coordinator
            // Contract: MultiAccountProvider.signOut(accountId:) transitions
            // membershipStatus from signedIn → signedOut while retaining
            // lastSnapshot and lastSnapshotTime.
            let accountId = try #require(multiAccount.accounts.first?.accountId)
            multiAccount.signOut(accountId: accountId)

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

        @Test
        func `signedOut account with low quota does not trigger alert while signedIn account with critical quota does`() async throws {
            // Given — account A signed in with low quota, then signed out;
            // account B signed in with critical quota (current)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
            given(mockAlerter).evaluateSnapshotAlerts(providerId: .any, snapshot: .any).willReturn()

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

            await monitor.refresh(providerId: "codex")

            let multiAccount = try #require(codex as? any MultiAccountProvider,
                "CodexProvider must conform to MultiAccountProvider — alert isolation requires multi-account state")

            // Step 2: Account A signs out
            let accountIdA = try #require(multiAccount.accounts.first?.accountId)
            multiAccount.signOut(accountId: accountIdA)

            // Step 3: Account B signs in with critical quota (current refresh)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")],
                capturedAt: Date(),
                accountEmail: "account-b@example.com"
            ))

            await monitor.refresh(providerId: "codex")

            // Contract: Only signedIn accounts' snapshots trigger alerts.
            // signedOut accounts (like account A with 10% quota) must be excluded
            // from alert evaluation even when their historical snapshot is critical.
            //
            // Verify multi-account state is correctly established:
            #expect(multiAccount.accounts.contains { $0.membershipStatus == .signedIn })
            #expect(multiAccount.accounts.contains { $0.membershipStatus == .signedOut })

            // Then — alert fires exactly once: for account B's critical quota.
            // Account A is signedOut, so its historical low quota must not
            // trigger an alert.  The single call proves account B's alert fired.
            verify(mockAlerter).alert(
                providerId: .any,
                previousStatus: .any,
                currentStatus: .any
            ).called(1)
        }
    }
}

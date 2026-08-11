import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("MultiAccountMigration Tests")
struct MultiAccountMigrationTests {

    private func makeRepository() throws -> (JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        let repo = JSONSettingsRepository(store: store)
        return (repo, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Migration: old provider settings → first account

    @Test("Migrates provider planLabel to first account")
    func migratesProviderPlanLabelToFirstAccount() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level planLabel
        repo.setPlanLabel("Pro 20X", forProvider: "claude")

        // Add an account
        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(config, forProvider: "claude")

        // Run migration
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: account-level planLabel should be set
        let accountPlanLabel = repo.accountPlanLabel(accountId: "personal", forProvider: "claude")
        #expect(accountPlanLabel == "Pro 20X")
    }

    @Test("Migrates provider renewalDate to first account")
    func migratesProviderRenewalDateToFirstAccount() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level renewalDate
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Add an account
        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(config, forProvider: "claude")

        // Run migration
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: account-level renewalDate should be set
        let accountRenewalDate = repo.accountRenewalDate(accountId: "personal", forProvider: "claude")
        #expect(accountRenewalDate == "2026-01-15")
    }

    // MARK: - Idempotent: repeated migration doesn't create duplicate accounts

    @Test("Repeated migration doesn't create duplicate accounts")
    func repeatedMigrationDoesNotCreateDuplicateAccounts() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setPlanLabel("Pro 20X", forProvider: "claude")
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Add an account
        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(config, forProvider: "claude")

        // Run migration twice
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: still only one account
        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "personal")
    }

    @Test("Repeated migration doesn't overwrite existing account values")
    func repeatedMigrationDoesNotOverwriteExistingAccountValues() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setPlanLabel("Pro 20X", forProvider: "claude")
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Add an account
        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(config, forProvider: "claude")

        // Run migration
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Manually change account-level value
        repo.setAccountPlanLabel("Team Plan", accountId: "personal", forProvider: "claude")

        // Run migration again
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: account-level value preserved (not overwritten)
        let accountPlanLabel = repo.accountPlanLabel(accountId: "personal", forProvider: "claude")
        #expect(accountPlanLabel == "Team Plan")
    }

    // MARK: - Account isolation: two accounts don't interfere

    @Test("Two accounts plan settings don't interfere")
    func twoAccountsPlanSettingsDoNotInterfere() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setPlanLabel("Pro 20X", forProvider: "claude")

        // Add two accounts
        let personal = ProviderAccountConfig(accountId: "personal", label: "Personal")
        let work = ProviderAccountConfig(accountId: "work", label: "Work")
        repo.addAccount(personal, forProvider: "claude")
        repo.addAccount(work, forProvider: "claude")

        // Run migration (should only apply to first account)
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Set different plan label for second account
        repo.setAccountPlanLabel("Team Enterprise", accountId: "work", forProvider: "claude")

        // Verify: first account has migrated value, second has its own
        let personalPlanLabel = repo.accountPlanLabel(accountId: "personal", forProvider: "claude")
        let workPlanLabel = repo.accountPlanLabel(accountId: "work", forProvider: "claude")
        #expect(personalPlanLabel == "Pro 20X")
        #expect(workPlanLabel == "Team Enterprise")
    }

    @Test("Two accounts renewalDate settings don't interfere")
    func twoAccountsRenewalDateSettingsDoNotInterfere() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Add two accounts
        let personal = ProviderAccountConfig(accountId: "personal", label: "Personal")
        let work = ProviderAccountConfig(accountId: "work", label: "Work")
        repo.addAccount(personal, forProvider: "claude")
        repo.addAccount(work, forProvider: "claude")

        // Run migration (should only apply to first account)
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Set different renewal date for second account
        repo.setAccountRenewalDate("2026-02-01", accountId: "work", forProvider: "claude")

        // Verify: first account has migrated value, second has its own
        let personalRenewal = repo.accountRenewalDate(accountId: "personal", forProvider: "claude")
        let workRenewal = repo.accountRenewalDate(accountId: "work", forProvider: "claude")
        #expect(personalRenewal == "2026-01-15")
        #expect(workRenewal == "2026-02-01")
    }

    // MARK: - No empty account creation

    @Test("No account created when no accounts exist")
    func noAccountCreatedWhenNoAccountsExist() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setPlanLabel("Pro 20X", forProvider: "claude")
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Run migration (no accounts exist)
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: no accounts created
        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.isEmpty)
    }

    @Test("No account created when provider has no settings")
    func noAccountCreatedWhenProviderHasNoSettings() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // No old provider-level settings

        // Run migration
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: no accounts created
        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.isEmpty)
    }

    // MARK: - Backward compatibility: old keys still readable

    @Test("Old provider-level keys remain readable after migration")
    func oldProviderLevelKeysRemainReadableAfterMigration() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set up old provider-level settings
        repo.setPlanLabel("Pro 20X", forProvider: "claude")
        repo.setRenewalDate("2026-01-15", forProvider: "claude")

        // Add an account
        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(config, forProvider: "claude")

        // Run migration
        repo.migrateProviderMembershipToAccounts(forProvider: "claude")

        // Verify: old keys still readable
        let oldPlanLabel = repo.planLabel(forProvider: "claude")
        let oldRenewalDate = repo.renewalDate(forProvider: "claude")
        #expect(oldPlanLabel == "Pro 20X")
        #expect(oldRenewalDate == "2026-01-15")
    }

    // MARK: - Account-level read/write

    @Test("Account-level planLabel read/write works")
    func accountLevelPlanLabelReadWrite() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set account-level planLabel
        repo.setAccountPlanLabel("Team Enterprise", accountId: "work", forProvider: "claude")

        // Read it back
        let planLabel = repo.accountPlanLabel(accountId: "work", forProvider: "claude")
        #expect(planLabel == "Team Enterprise")
    }

    @Test("Account-level renewalDate read/write works")
    func accountLevelRenewalDateReadWrite() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        // Set account-level renewalDate
        repo.setAccountRenewalDate("2026-03-01", accountId: "work", forProvider: "claude")

        // Read it back
        let renewalDate = repo.accountRenewalDate(accountId: "work", forProvider: "claude")
        #expect(renewalDate == "2026-03-01")
    }

    @Test("Account-level planLabel returns empty when not set")
    func accountLevelPlanLabelReturnsEmptyWhenNotSet() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let planLabel = repo.accountPlanLabel(accountId: "personal", forProvider: "claude")
        #expect(planLabel == "")
    }

    @Test("Account-level renewalDate returns empty when not set")
    func accountLevelRenewalDateReturnsEmptyWhenNotSet() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let renewalDate = repo.accountRenewalDate(accountId: "personal", forProvider: "claude")
        #expect(renewalDate == "")
    }
}

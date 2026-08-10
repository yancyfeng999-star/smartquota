import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("ProviderAccountRepository Tests")
struct ProviderAccountRepositoryTests {

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

    // MARK: - Account CRUD

    @Test
    func `accounts returns empty array for unknown provider`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.isEmpty)
    }

    @Test
    func `addAccount persists account config`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let config = ProviderAccountConfig(
            accountId: "personal",
            label: "Personal",
            email: "me@example.com",
            probeConfig: ["profile": "default"]
        )
        repo.addAccount(config, forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "personal")
        #expect(accounts.first?.label == "Personal")
        #expect(accounts.first?.email == "me@example.com")
        #expect(accounts.first?.probeConfig["profile"] == "default")
    }

    @Test
    func `addAccount multiple accounts persists all`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let personal = ProviderAccountConfig(accountId: "personal", label: "Personal")
        let work = ProviderAccountConfig(accountId: "work", label: "Work")
        repo.addAccount(personal, forProvider: "claude")
        repo.addAccount(work, forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 2)
        #expect(accounts.map(\.accountId).sorted() == ["personal", "work"])
    }

    @Test
    func `removeAccount removes the correct account`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let personal = ProviderAccountConfig(accountId: "personal", label: "Personal")
        let work = ProviderAccountConfig(accountId: "work", label: "Work")
        repo.addAccount(personal, forProvider: "claude")
        repo.addAccount(work, forProvider: "claude")

        repo.removeAccount(accountId: "personal", forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "work")
    }

    @Test
    func `removeAccount does nothing when accountId not found`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let personal = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(personal, forProvider: "claude")

        repo.removeAccount(accountId: "nonexistent", forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
    }

    @Test
    func `updateAccount modifies existing account`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let original = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(original, forProvider: "claude")

        let updated = ProviderAccountConfig(
            accountId: "personal",
            label: "Personal Pro",
            email: "pro@example.com",
            probeConfig: ["profile": "pro"]
        )
        repo.updateAccount(updated, forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "Personal Pro")
        #expect(accounts.first?.email == "pro@example.com")
        #expect(accounts.first?.probeConfig["profile"] == "pro")
    }

    @Test
    func `updateAccount does nothing when accountId not found`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let original = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo.addAccount(original, forProvider: "claude")

        let nonexistent = ProviderAccountConfig(accountId: "ghost", label: "Ghost")
        repo.updateAccount(nonexistent, forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "Personal")
    }

    // MARK: - Per-Provider Isolation

    @Test
    func `accounts are isolated per provider`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let claudeAcc = ProviderAccountConfig(accountId: "a1", label: "Claude Account")
        let codexAcc = ProviderAccountConfig(accountId: "b1", label: "Codex Account")
        repo.addAccount(claudeAcc, forProvider: "claude")
        repo.addAccount(codexAcc, forProvider: "codex")

        #expect(repo.accounts(forProvider: "claude").count == 1)
        #expect(repo.accounts(forProvider: "codex").count == 1)
        #expect(repo.accounts(forProvider: "gemini").isEmpty)
    }

    // MARK: - Active Account Selection

    @Test
    func `activeAccountId returns nil by default`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        #expect(repo.activeAccountId(forProvider: "claude") == nil)
    }

    @Test
    func `setActiveAccountId persists selection`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("personal", forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == "personal")
    }

    @Test
    func `setActiveAccountId nil clears selection`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("personal", forProvider: "claude")
        repo.setActiveAccountId(nil, forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == nil)
    }

    @Test
    func `activeAccountId is isolated per provider`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("personal", forProvider: "claude")
        repo.setActiveAccountId("work", forProvider: "codex")

        #expect(repo.activeAccountId(forProvider: "claude") == "personal")
        #expect(repo.activeAccountId(forProvider: "codex") == "work")
        #expect(repo.activeAccountId(forProvider: "gemini") == nil)
    }

    // MARK: - Persistence Across Instances

    @Test
    func `accounts persist across store instances`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanup(tempDir) }

        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store1 = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store1)

        let config = ProviderAccountConfig(accountId: "personal", label: "Personal")
        repo1.addAccount(config, forProvider: "claude")
        repo1.setActiveAccountId("personal", forProvider: "claude")

        let store2 = JSONSettingsStore(fileURL: fileURL)
        let repo2 = JSONSettingsRepository(store: store2)

        let accounts = repo2.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "personal")
        #expect(repo2.activeAccountId(forProvider: "claude") == "personal")
    }

    // MARK: - ProbeConfig Dictionary

    @Test
    func `probeConfig dictionary round-trips correctly`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let config = ProviderAccountConfig(
            accountId: "work",
            label: "Work",
            probeConfig: ["cliProfile": "work-profile", "envVar": "CLAUDE_TOKEN_WORK"]
        )
        repo.addAccount(config, forProvider: "claude")

        let loaded = repo.accounts(forProvider: "claude").first
        #expect(loaded?.probeConfig["cliProfile"] == "work-profile")
        #expect(loaded?.probeConfig["envVar"] == "CLAUDE_TOKEN_WORK")
    }

    // MARK: - No Secrets in Settings File

    @Test
    func `settings file does not contain secret fields`() throws {
        let (repo, dir) = try makeRepository()
        defer { cleanup(dir) }

        let config = ProviderAccountConfig(
            accountId: "personal",
            label: "Personal",
            email: "me@example.com",
            probeConfig: ["profile": "default"]
        )
        repo.addAccount(config, forProvider: "claude")

        let fileURL = dir.appendingPathComponent("settings.json")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!content.contains("secret"))
        #expect(!content.contains("password"))
        #expect(!content.contains("token"))
    }
}

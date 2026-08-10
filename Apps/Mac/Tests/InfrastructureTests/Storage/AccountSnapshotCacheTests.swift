import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("AccountSnapshotCache Tests")
struct AccountSnapshotCacheTests {

    private func makeCache() throws -> (AccountSnapshotCache, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-snapshot-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let cache = AccountSnapshotCache(directory: tempDir)
        return (cache, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Round-Trip Encoding

    @Test
    func `save and load snapshot round-trips basic fields`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 75.5,
                    quotaType: .session,
                    providerId: "claude",
                    resetsAt: Date().addingTimeInterval(3600),
                    resetText: "Resets in 1h"
                ),
            ],
            capturedAt: Date(),
            accountEmail: "test@example.com",
            accountOrganization: "Acme",
            loginMethod: "oauth",
            accountTier: .claudePro
        )

        let accountId = "claude.personal"
        try cache.save(snapshot, forAccount: accountId)

        let loaded = cache.load(forAccount: "claude.personal")
        #expect(loaded != nil)
        #expect(loaded?.providerId == "claude")
        #expect(loaded?.quotas.count == 1)
        #expect(loaded?.quotas.first?.percentRemaining == 75.5)
        #expect(loaded?.quotas.first?.quotaType == .session)
        #expect(loaded?.accountEmail == "test@example.com")
        #expect(loaded?.accountOrganization == "Acme")
        #expect(loaded?.loginMethod == "oauth")
        #expect(loaded?.accountTier == .claudePro)
    }

    @Test
    func `save and load snapshot round-trips model-specific quota`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 50,
                    quotaType: .modelSpecific("opus"),
                    providerId: "claude"
                ),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.work")
        let loaded = cache.load(forAccount: "claude.work")

        #expect(loaded?.quotas.first?.quotaType == .modelSpecific("opus"))
    }

    @Test
    func `save and load snapshot round-trips timeLimit quota`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [
                UsageQuota(
                    percentRemaining: 80,
                    quotaType: .timeLimit("Monthly"),
                    providerId: "copilot"
                ),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "copilot.default")
        let loaded = cache.load(forAccount: "copilot.default")

        #expect(loaded?.quotas.first?.quotaType == .timeLimit("Monthly"))
    }

    @Test
    func `save and load snapshot round-trips costUsage`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let costUsage = CostUsage(
            totalCost: 12.50,
            budget: 50.00,
            apiDuration: 300,
            wallDuration: 600,
            linesAdded: 100,
            linesRemoved: 20,
            providerId: "claude",
            kind: .extraUsage,
            capturedAt: Date(),
            resetsAt: Date().addingTimeInterval(86400),
            resetText: "Resets Jan 1"
        )

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            costUsage: costUsage
        )

        try cache.save(snapshot, forAccount: "claude.api")
        let loaded = cache.load(forAccount: "claude.api")

        #expect(loaded?.costUsage != nil)
        #expect(loaded?.costUsage?.totalCost == 12.50)
        #expect(loaded?.costUsage?.budget == 50.00)
        #expect(loaded?.costUsage?.kind == .extraUsage)
        #expect(loaded?.costUsage?.linesAdded == 100)
    }

    @Test
    func `save and load snapshot round-trips dollar-based quotas`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 100,
                    quotaType: .session,
                    providerId: "claude",
                    dollarRemaining: 50,
                    dollarUsed: 12.50,
                    dollarCap: 200
                ),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.test")
        let loaded = cache.load(forAccount: "claude.test")

        let quota = loaded?.quotas.first
        #expect(quota?.dollarRemaining == 50)
        #expect(quota?.dollarUsed == 12.50)
        #expect(quota?.dollarCap == 200)
    }

    @Test
    func `save and load snapshot round-trips extensionMetrics`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let metric = ExtensionMetric(
            label: "Requests",
            value: "1234",
            unit: "req",
            icon: "chart.bar",
            color: "#FF0000",
            delta: MetricDelta(vs: "yesterday", value: "+100", percent: 8.5),
            progress: 0.75,
            group: "Claude"
        )

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            extensionMetrics: [metric]
        )

        try cache.save(snapshot, forAccount: "claude.ext")
        let loaded = cache.load(forAccount: "claude.ext")

        #expect(loaded?.extensionMetrics?.count == 1)
        #expect(loaded?.extensionMetrics?.first?.label == "Requests")
        #expect(loaded?.extensionMetrics?.first?.value == "1234")
        #expect(loaded?.extensionMetrics?.first?.group == "Claude")
    }

    @Test
    func `save and load snapshot round-trips dailyUsageReport`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let today = DailyUsageStat(
            date: Date(),
            totalCost: 10.50,
            totalTokens: 50000,
            workingTime: 3600,
            sessionCount: 5,
            inputTokens: 30000,
            outputTokens: 20000,
            cacheCreationTokens: 1000,
            cacheReadTokens: 5000,
            cachedSavings: 2.50
        )
        let previous = DailyUsageStat(
            date: Date().addingTimeInterval(-86400),
            totalCost: 8.00,
            totalTokens: 40000,
            workingTime: 2400,
            sessionCount: 3
        )
        let report = DailyUsageReport(today: today, previous: previous)

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            dailyUsageReport: report
        )

        try cache.save(snapshot, forAccount: "claude.daily")
        let loaded = cache.load(forAccount: "claude.daily")

        #expect(loaded?.dailyUsageReport != nil)
        #expect(loaded?.dailyUsageReport?.today.totalCost == 10.50)
        #expect(loaded?.dailyUsageReport?.today.totalTokens == 50000)
        #expect(loaded?.dailyUsageReport?.today.sessionCount == 5)
        #expect(loaded?.dailyUsageReport?.previous.totalCost == 8.00)
    }

    @Test
    func `save and load snapshot preserves accountIdentitySource`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountExternalId: "ext-123",
            accountIdentitySource: .email
        )

        try cache.save(snapshot, forAccount: "claude.id")
        let loaded = cache.load(forAccount: "claude.id")

        #expect(loaded?.accountExternalId == "ext-123")
        #expect(loaded?.accountIdentitySource == .email)
    }

    // MARK: - Corrupt Cache Safety

    @Test
    func `load returns nil when no cache file exists`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let loaded = cache.load(forAccount: "claude.nonexistent")
        #expect(loaded == nil)
    }

    @Test
    func `load returns nil for corrupt cache file`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        // Write corrupt data to the cache file
        let fileURL = dir.appendingPathComponent("claude.corrupt.json")
        try "not valid json {{{".write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = cache.load(forAccount: "claude.corrupt")
        #expect(loaded == nil)
    }

    @Test
    func `load returns nil for empty file`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let fileURL = dir.appendingPathComponent("claude.empty.json")
        try Data().write(to: fileURL)

        let loaded = cache.load(forAccount: "claude.empty")
        #expect(loaded == nil)
    }

    @Test
    func `save overwrites corrupt cache file`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        // Write corrupt data first
        let fileURL = dir.appendingPathComponent("claude.fix.json")
        try "broken".write(to: fileURL, atomically: true, encoding: .utf8)

        // Save should overwrite
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date()
        )
        try cache.save(snapshot, forAccount: "claude.fix")

        let loaded = cache.load(forAccount: "claude.fix")
        #expect(loaded != nil)
        #expect(loaded?.providerId == "claude")
    }

    // MARK: - Per-Account Isolation

    @Test
    func `deleting one account cache does not affect others`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot1 = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 90, quotaType: .session, providerId: "claude"),
            ],
            capturedAt: Date()
        )
        let snapshot2 = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 50, quotaType: .weekly, providerId: "claude"),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot1, forAccount: "claude.personal")
        try cache.save(snapshot2, forAccount: "claude.work")

        cache.delete(forAccount: "claude.personal")

        #expect(cache.load(forAccount: "claude.personal") == nil)
        let workSnapshot = cache.load(forAccount: "claude.work")
        #expect(workSnapshot != nil)
        #expect(workSnapshot?.quotas.first?.percentRemaining == 50)
    }

    @Test
    func `delete does nothing when file does not exist`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        // Should not throw
        cache.delete(forAccount: "claude.nonexistent")
    }

    // MARK: - Cross-Provider Isolation

    @Test
    func `snapshots are isolated across providers`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let claudeSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            ],
            capturedAt: Date()
        )
        let codexSnapshot = UsageSnapshot(
            providerId: "codex",
            quotas: [
                UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "codex"),
            ],
            capturedAt: Date()
        )

        try cache.save(claudeSnapshot, forAccount: "claude.default")
        try cache.save(codexSnapshot, forAccount: "codex.default")

        let loadedClaude = cache.load(forAccount: "claude.default")
        let loadedCodex = cache.load(forAccount: "codex.default")

        #expect(loadedClaude?.providerId == "claude")
        #expect(loadedCodex?.providerId == "codex")
        #expect(loadedClaude?.quotas.first?.percentRemaining == 80)
        #expect(loadedCodex?.quotas.first?.percentRemaining == 60)
    }

    // MARK: - WindowDuration Round-Trip

    @Test
    func `save and load snapshot round-trips windowDuration`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 50,
                    quotaType: .session,
                    providerId: "claude",
                    windowDuration: 18000
                ),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.wd")
        let loaded = cache.load(forAccount: "claude.wd")

        #expect(loaded?.quotas.first?.windowDuration == 18000)
    }

    // MARK: - Group and compactTitle Round-Trip

    @Test
    func `save and load snapshot round-trips group and compactTitle`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 70,
                    quotaType: .session,
                    providerId: "claude",
                    group: "Claude · work",
                    compactTitle: "5h",
                    menuBarTitle: "Claude · work"
                ),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.group")
        let loaded = cache.load(forAccount: "claude.group")

        #expect(loaded?.quotas.first?.group == "Claude · work")
        #expect(loaded?.quotas.first?.compactTitle == "5h")
        #expect(loaded?.quotas.first?.menuBarTitle == "Claude · work")
    }

    // MARK: - Atomic Write Verification

    @Test
    func `cache file is valid JSON after save`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "claude"),
            ],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.atomic")

        let fileURL = dir.appendingPathComponent("claude.atomic.json")
        let data = try Data(contentsOf: fileURL)
        // Should parse as valid JSON
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["providerId"] as? String == "claude")
    }

    // MARK: - File Permissions

    @Test
    func `cache file has 0600 permissions`() throws {
        let (cache, dir) = try makeCache()
        defer { cleanup(dir) }

        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date()
        )

        try cache.save(snapshot, forAccount: "claude.perms")

        let fileURL = dir.appendingPathComponent("claude.perms.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        #expect(perms?.uint16Value == 0o600)
    }
}

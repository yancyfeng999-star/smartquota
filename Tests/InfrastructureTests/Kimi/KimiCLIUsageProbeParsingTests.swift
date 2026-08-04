import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("KimiCLIUsageProbe Parsing Tests")
struct KimiCLIUsageProbeParsingTests {

    // MARK: - Sample Output

    private static let fullOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
    │  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    private static let partialUsageOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━░░░░░░  75% left  (resets in 5d 12h 30m)   │
    │  5h limit      ━━━━━━━░░░░░░░░░░░░░  30% left  (resets in 2h 10m)       │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    private static let weeklyOnlyOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    /// Real CLI output has no progress bar characters — just whitespace
    private static let noProgressBarOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit                        100% left  (resets in 6d 22h 55m)  │
    │  5h limit                            100% left  (resets in 3h 55m)      │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    // MARK: - Full Output Parsing

    @Test
    func `parse full output extracts both quotas`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)

        #expect(snapshot.providerId == "kimi")
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `parse full output extracts weekly quota at 100 percent`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly != nil)
        #expect(weekly?.percentRemaining == 100.0)
    }

    @Test
    func `parse full output extracts session quota at 100 percent`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        let session = snapshot.quota(for: .session)

        #expect(session != nil)
        #expect(session?.percentRemaining == 100.0)
    }

    // MARK: - Partial Usage Parsing

    @Test
    func `parse partial usage extracts 75 percent weekly`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.partialUsageOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly != nil)
        #expect(weekly?.percentRemaining == 75.0)
    }

    @Test
    func `parse partial usage extracts 30 percent session`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.partialUsageOutput)
        let session = snapshot.quota(for: .session)

        #expect(session != nil)
        #expect(session?.percentRemaining == 30.0)
    }

    // MARK: - Weekly Only

    @Test
    func `parse weekly only output returns single quota`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.weeklyOnlyOutput)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quota(for: .weekly) != nil)
        #expect(snapshot.quota(for: .session) == nil)
    }

    // MARK: - No Progress Bar (Real CLI Output)

    @Test
    func `parse output without progress bar extracts both quotas`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.noProgressBarOutput)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 100.0)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 100.0)
    }

    // MARK: - Reset Time Parsing

    @Test
    func `parse extracts weekly reset date from days hours minutes`() throws {
        let now = Date()
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly?.resetsAt != nil)
        if let resetsAt = weekly?.resetsAt {
            let diff = resetsAt.timeIntervalSince(now)
            // 6d 23h 22m = 6*86400 + 23*3600 + 22*60 = 602520s — allow 60s tolerance
            #expect(diff > 602460)
            #expect(diff < 602580)
        }
    }

    @Test
    func `parse extracts session reset date from hours minutes`() throws {
        let now = Date()
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        let session = snapshot.quota(for: .session)

        #expect(session?.resetsAt != nil)
        if let resetsAt = session?.resetsAt {
            let diff = resetsAt.timeIntervalSince(now)
            // 4h 22m ≈ 15720s — allow 60s tolerance
            #expect(diff > 15660)
            #expect(diff < 15780)
        }
    }

    @Test
    func `parse extracts reset text`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly?.resetText == "Resets in 6d 23h 22m")
    }

    // MARK: - Reset Duration Helper

    @Test
    func `parseResetDuration handles days hours minutes`() {
        let now = Date()
        let date = KimiCLIUsageProbe.parseResetDuration("6d 23h 22m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            let expected = 6.0 * 86400 + 23.0 * 3600 + 22.0 * 60
            #expect(abs(diff - expected) < 2)
        }
    }

    @Test
    func `parseResetDuration handles hours and minutes only`() {
        let now = Date()
        let date = KimiCLIUsageProbe.parseResetDuration("4h 22m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            let expected = 4.0 * 3600 + 22.0 * 60
            #expect(abs(diff - expected) < 2)
        }
    }

    @Test
    func `parseResetDuration handles minutes only`() {
        let now = Date()
        let date = KimiCLIUsageProbe.parseResetDuration("30m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            #expect(abs(diff - 1800) < 2)
        }
    }

    @Test
    func `parseResetDuration returns nil for empty string`() {
        let date = KimiCLIUsageProbe.parseResetDuration("")
        #expect(date == nil)
    }

    // MARK: - Error Cases

    @Test
    func `parse throws parseFailed for empty output`() {
        #expect(throws: ProbeError.self) {
            try KimiCLIUsageProbe.parse("")
        }
    }

    @Test
    func `parse throws parseFailed for malformed output`() {
        #expect(throws: ProbeError.self) {
            try KimiCLIUsageProbe.parse("This is not a valid usage output")
        }
    }

    @Test
    func `parse throws parseFailed for output without percentage`() {
        let noPercent = """
        ╭──── API Usage ────╮
        │  Weekly limit  ━━━━━━━━━━━  no data  │
        ╰──────────────────╯
        """

        #expect(throws: ProbeError.self) {
            try KimiCLIUsageProbe.parse(noPercent)
        }
    }

    // MARK: - Provider ID

    @Test
    func `parse sets providerId to kimi`() throws {
        let snapshot = try KimiCLIUsageProbe.parse(Self.fullOutput)
        #expect(snapshot.providerId == "kimi")
    }
}

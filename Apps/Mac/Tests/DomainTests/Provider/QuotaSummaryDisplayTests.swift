import Testing
@testable import Domain

@Suite("Quota summary display")
struct QuotaSummaryDisplayTests {

    @Test
    func `remaining mode shows remaining value and progress`() {
        let quota = UsageQuota(
            percentRemaining: 86,
            quotaType: .weekly,
            providerId: "kimi",
            resetText: "used 14/100 weekly"
        )

        let display = quota.summaryDisplay(mode: .remaining)

        #expect(display.valueText == "86/100")
        #expect(display.progressPercent == 86)
    }

    @Test
    func `used mode shows used value and progress`() {
        let quota = UsageQuota(
            percentRemaining: 86,
            quotaType: .weekly,
            providerId: "kimi",
            resetText: "used 14/100 weekly"
        )

        let display = quota.summaryDisplay(mode: .used)

        #expect(display.valueText == "14/100")
        #expect(display.progressPercent == 14)
    }

    @Test
    func `unlabeled ratio falls back to authoritative remaining percentage`() {
        let quota = UsageQuota(
            percentRemaining: 86,
            quotaType: .weekly,
            providerId: "kimi",
            resetText: "14/100 weekly"
        )

        #expect(quota.summaryDisplay(mode: .remaining).valueText == "86/100")
        #expect(quota.summaryDisplay(mode: .used).valueText == "14/100")
    }

    @Test
    func `explicit remaining count inverts correctly in used mode`() {
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .modelSpecific("Video"),
            providerId: "minimax",
            resetText: "剩余 3/4 条"
        )

        #expect(quota.summaryDisplay(mode: .remaining).valueText == "3/4")
        #expect(quota.summaryDisplay(mode: .used).valueText == "1/4")
    }
}

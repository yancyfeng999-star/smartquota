import Testing
import Foundation
@testable import Domain

@Suite("MonthlyFromWeekly")
struct MonthlyFromWeeklyTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        return cal.date(from: c)!
    }

    @Test
    func `calendar linear remaining for Grok mid-cycle`() {
        // 开通 7/30 → 续费 8/30；今天 8/6
        // cycleDays=31, daysLeft=24 → remaining = 100 * 24/31 ≈ 77.42
        let renew = date(2026, 8, 30)
        let now = date(2026, 8, 6)
        let est = MonthlyFromWeekly.estimate(renewalAt: renew, now: now)

        #expect(abs(est.percentRemaining - (100.0 * 24.0 / 31.0)) < 0.05)
        #expect(cal.isDate(est.resetsAt, inSameDayAs: renew))
    }

    @Test
    func `does not depend on weekly remaining after 7D reset`() {
        let renew = date(2026, 8, 30)
        let now = date(2026, 8, 6)
        // Legacy API still accepts weeklyRemaining but ignores it
        let a = MonthlyFromWeekly.estimate(weeklyRemaining: 100, renewalAt: renew, now: now)
        let b = MonthlyFromWeekly.estimate(weeklyRemaining: 10, renewalAt: renew, now: now)
        #expect(a.percentRemaining == b.percentRemaining)
        #expect(a.percentRemaining != nil)
        #expect(a.percentRemaining! < 100)
        #expect(a.percentRemaining! > 70)
    }

    @Test
    func `full remaining at cycle start`() {
        // 续费 8/30，今天 7/30（周期首日）→ daysLeft=31, remaining=100
        let renew = date(2026, 8, 30)
        let now = date(2026, 7, 30)
        let est = MonthlyFromWeekly.estimate(renewalAt: renew, now: now)
        #expect(est.percentRemaining == 100)
    }

    @Test
    func `zero remaining on renewal day`() {
        let renew = date(2026, 8, 30)
        let now = date(2026, 8, 30)
        let est = MonthlyFromWeekly.estimate(renewalAt: renew, now: now)
        #expect(est.percentRemaining == 0)
    }

    @Test
    func `without renewal uses calendar month end`() {
        let now = date(2026, 8, 6)
        let est = MonthlyFromWeekly.estimateWithoutRenewal(now: now)
        // Aug has 31 days; from 8/6 to 8/31 → daysLeft=25, remaining ≈ 100*25/31
        #expect(abs(est.percentRemaining - (100.0 * 25.0 / 31.0)) < 0.05)
    }
}

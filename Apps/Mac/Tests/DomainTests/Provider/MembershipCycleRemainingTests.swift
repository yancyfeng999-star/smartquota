import Testing
import Foundation
@testable import Domain

@Suite("MembershipCycleRemaining")
struct MembershipCycleRemainingTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        return cal.date(from: c)!
    }

    @Test
    func `calendar linear remaining mid-cycle`() {
        // 开通 7/30 → 续费 8/30；今天 8/6 → 24/31
        let renew = date(2026, 8, 30)
        let now = date(2026, 8, 6)
        let est = MembershipCycleRemaining.estimate(renewalAt: renew, now: now)

        #expect(abs(est.percentRemaining - (100.0 * 24.0 / 31.0)) < 0.05)
        #expect(cal.isDate(est.resetsAt, inSameDayAs: renew))
    }

    @Test
    func `full remaining at cycle start`() {
        let renew = date(2026, 8, 30)
        let now = date(2026, 7, 30)
        let est = MembershipCycleRemaining.estimate(renewalAt: renew, now: now)
        #expect(est.percentRemaining == 100)
    }

    @Test
    func `zero remaining on renewal day`() {
        let renew = date(2026, 8, 30)
        let now = date(2026, 8, 30)
        let est = MembershipCycleRemaining.estimate(renewalAt: renew, now: now)
        #expect(est.percentRemaining == 0)
    }

    @Test
    func `without renewal uses calendar month end`() {
        let now = date(2026, 8, 6)
        let est = MembershipCycleRemaining.estimateWithoutRenewal(now: now)
        #expect(abs(est.percentRemaining - (100.0 * 25.0 / 31.0)) < 0.05)
    }
}

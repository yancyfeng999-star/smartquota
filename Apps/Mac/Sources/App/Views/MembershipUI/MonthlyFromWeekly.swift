import Foundation
import Domain

/// Estimates monthly remaining when the API does not expose a real monthly window.
///
/// Uses **7d remaining** + **membership next-renewal date** (from user-set activation):
/// - Cycle length ≈ days from previous anniversary to next renewal (≈ calendar month)
/// - One full weekly window is `7 / cycleDays` of monthly capacity
/// - `monthlyUsed ≈ weeklyUsed × (7 / cycleDays)` for the latest completed-scale week burn
enum MonthlyFromWeekly {
    /// Estimate monthly remaining from weekly % and membership renewal.
    /// - Parameters:
    ///   - weeklyRemaining: 0...100 on the 7d window
    ///   - renewalAt: next membership renewal (开通日推算的续费日)
    ///   - now: reference time
    /// - Returns: estimated remaining %, reset date (= renewal), no noisy “由7d估算” label under bar
    static func estimate(
        weeklyRemaining: Double,
        renewalAt: Date,
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let renewDay = cal.startOfDay(for: renewalAt)

        // Previous cycle start ≈ one calendar month before next renewal
        let cycleStart = cal.date(byAdding: .month, value: -1, to: renewDay) ?? today
        let cycleDays = max(
            7,
            cal.dateComponents([.day], from: cycleStart, to: renewDay).day ?? 30
        )
        let daysLeft = max(
            0,
            cal.dateComponents([.day], from: today, to: renewDay).day ?? 0
        )
        // If renewal is today or past, treat as end of cycle
        let effectiveLeft = renewDay <= today ? 0 : daysLeft
        let daysElapsed = max(0, cycleDays - effectiveLeft)

        let weeklyUsed = max(0, min(100, 100 - weeklyRemaining))
        // Burn so far scaled by elapsed fraction of cycle (using current week’s pace)
        // Reverse from renewal: remaining ≈ unused fraction of cycle capacity
        // monthlyUsed ≈ weeklyUsed × (daysElapsed / cycleDays)  but weekly is a 7-day bucket,
        // so map one week of burn into cycle: weeklyUsed × (7/cycleDays) as “this week’s share”,
        // then × elapsed weeks ≈ daysElapsed/7:
        //   monthlyUsed = weeklyUsed × (daysElapsed / cycleDays)
        let monthlyUsed: Double
        if daysElapsed <= 0 {
            // Start of cycle — only current week burn counts at 7/cycle scale
            monthlyUsed = weeklyUsed * (7.0 / Double(cycleDays))
        } else {
            monthlyUsed = weeklyUsed * (Double(daysElapsed) / Double(cycleDays))
        }
        // Also blend in “capacity still available this week for rest of cycle”
        // remaining = max(0, 100 - monthlyUsed) with weekly remaining as ceiling when near end
        var remaining = max(0, min(100, 100 - monthlyUsed))
        // Near renewal: don’t show more remaining than what current week implies for leftover days
        if effectiveLeft > 0 && effectiveLeft < 7 {
            let weekShare = weeklyRemaining * (Double(effectiveLeft) / 7.0)
            // Scale weekShare to monthly: weekShare * (cycleDays/7) would overshoot; keep softer cap
            remaining = min(remaining, max(weekShare, remaining * Double(effectiveLeft) / Double(cycleDays)))
        }
        return (remaining, renewDay)
    }

    /// Fallback when no renewal date: classic 7/30 scale, end of calendar month.
    static func estimateWithoutRenewal(
        weeklyRemaining: Double,
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date) {
        let used = max(0, min(100, 100 - weeklyRemaining))
        let monthlyUsed = used * (7.0 / 30.0)
        let remaining = max(0, min(100, 100 - monthlyUsed))
        return (remaining, endOfMonth(containing: now))
    }

    static func endOfMonth(containing date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let start = cal.date(from: comps),
              let next = cal.date(byAdding: .month, value: 1, to: start),
              let end = cal.date(byAdding: .second, value: -1, to: next) else {
            return date.addingTimeInterval(30 * 24 * 3600)
        }
        return end
    }
}

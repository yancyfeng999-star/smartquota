import Foundation
import Domain

/// Estimates a monthly remaining % from a weekly (7d) window.
///
/// Model: weekly capacity is 1/ (30/7) of a month-equivalent budget.
/// This week's used fraction of weekly capacity consumes
/// `weeklyUsed% × 7/30` of the monthly-equivalent capacity.
enum MonthlyFromWeekly {
    /// - Parameters:
    ///   - weeklyRemaining: 0...100 remaining on the 7d window
    ///   - weeklyResetsAt: optional reset of the 7d window (not used for month end)
    /// - Returns: estimated monthly remaining percent and end-of-calendar-month reset
    static func estimate(
        weeklyRemaining: Double,
        weeklyResetsAt: Date? = nil,
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date, note: String) {
        let used = max(0, min(100, 100 - weeklyRemaining))
        // used_month% = used_week% × (7/30)  relative to month-scale capacity
        let monthlyUsed = used * (7.0 / 30.0)
        let remaining = max(0, min(100, 100 - monthlyUsed))
        return (remaining, endOfMonth(containing: now), "由7d估算")
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

    /// Build a display-only monthly quota model from weekly.
    static func quota(from weekly: UsageQuota, providerId: String) -> UsageQuota {
        let est = estimate(
            weeklyRemaining: weekly.percentRemaining,
            weeklyResetsAt: weekly.resetsAt
        )
        return UsageQuota(
            percentRemaining: est.percentRemaining,
            quotaType: .timeLimit("Monthly"),
            providerId: providerId,
            resetsAt: est.resetsAt,
            resetText: est.note,
            compactTitle: "总额"
        )
    }
}

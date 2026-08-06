import Foundation

/// **总额** when the API has no real monthly quota window.
///
/// Policy (product):
/// 1. Prefer a real monthly meter from the probe when present (handled in UI).
/// 2. Otherwise: **calendar linear remaining** to the next membership renewal —
///    `remaining% = daysLeft / cycleDays × 100`, decreasing roughly once per day.
///    Independent of 7D / weekly usage (weekly resets must not fake a full tank).
///
/// Cycle is anchored on next renewal: previous anniversary → renewal (≈ one calendar month).
public enum MonthlyFromWeekly {
    /// Calendar-based remaining until `renewalAt` (next membership renewal day).
    public static func estimate(
        renewalAt: Date,
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let renewDay = cal.startOfDay(for: renewalAt)

        // Previous cycle start ≈ one calendar month before next renewal
        let cycleStart = cal.date(byAdding: .month, value: -1, to: renewDay) ?? today
        let cycleDays = max(
            1,
            cal.dateComponents([.day], from: cycleStart, to: renewDay).day ?? 30
        )

        // Days strictly remaining until renewal (renewal day itself → 0)
        let daysLeft: Int
        if renewDay <= today {
            daysLeft = 0
        } else {
            daysLeft = max(0, cal.dateComponents([.day], from: today, to: renewDay).day ?? 0)
        }

        let remaining = max(0, min(100, 100.0 * Double(daysLeft) / Double(cycleDays)))
        return (remaining, renewDay)
    }

    /// Legacy entry that ignored weekly burn after product change; kept so call sites
    /// can migrate. Prefer `estimate(renewalAt:now:)`.
    public static func estimate(
        weeklyRemaining: Double,
        renewalAt: Date,
        now: Date = Date()
    ) -> (percentRemaining: Double?, resetsAt: Date) {
        let est = estimate(renewalAt: renewalAt, now: now)
        return (est.percentRemaining, est.resetsAt)
    }

    /// No renewal date: linear remaining to end of the current calendar month.
    public static func estimateWithoutRenewal(
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let end = endOfMonth(containing: now)
        let endDay = cal.startOfDay(for: end)

        let daysInMonth = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        let cycleDays = max(1, daysInMonth)
        let daysLeft: Int
        if endDay <= today {
            daysLeft = 0
        } else {
            daysLeft = max(0, cal.dateComponents([.day], from: today, to: endDay).day ?? 0)
        }
        let remaining = max(0, min(100, 100.0 * Double(daysLeft) / Double(cycleDays)))
        return (remaining, end)
    }

    /// Legacy signature (weekly ignored).
    public static func estimateWithoutRenewal(
        weeklyRemaining: Double,
        now: Date = Date()
    ) -> (percentRemaining: Double?, resetsAt: Date) {
        let est = estimateWithoutRenewal(now: now)
        return (est.percentRemaining, est.resetsAt)
    }

    public static func endOfMonth(containing date: Date) -> Date {
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

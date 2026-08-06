import Foundation

/// Calendar remaining for the **总额** column when no real monthly meter exists.
///
/// Product policy (all channels):
/// 1. Prefer a real monthly meter from the probe (UI layer).
/// 2. Else: linear remaining until next membership renewal —
///    `remaining% = daysLeft / cycleDays × 100`.
///    Independent of 5H / 7D usage.
///
/// Cycle: previous anniversary → next renewal (≈ one calendar month).
public enum MembershipCycleRemaining {
    /// Remaining % until `renewalAt` (next membership renewal day).
    public static func estimate(
        renewalAt: Date,
        now: Date = Date()
    ) -> (percentRemaining: Double, resetsAt: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let renewDay = cal.startOfDay(for: renewalAt)

        let cycleStart = cal.date(byAdding: .month, value: -1, to: renewDay) ?? today
        let cycleDays = max(
            1,
            cal.dateComponents([.day], from: cycleStart, to: renewDay).day ?? 30
        )

        let daysLeft: Int
        if renewDay <= today {
            daysLeft = 0
        } else {
            daysLeft = max(0, cal.dateComponents([.day], from: today, to: renewDay).day ?? 0)
        }

        let remaining = max(0, min(100, 100.0 * Double(daysLeft) / Double(cycleDays)))
        return (remaining, renewDay)
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

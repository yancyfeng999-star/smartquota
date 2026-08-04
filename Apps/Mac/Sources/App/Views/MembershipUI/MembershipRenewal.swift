import Foundation

/// Subscription renewal helpers for membership activation dates.
///
/// Most coding plans bill on a **calendar-month** cycle anchored to the activation /
/// subscribe day (not a fixed 30-day window). Weekly usage windows may reset separately
/// from membership dues. Users enter their own activation date in Settings; nothing
/// here encodes a personal account or plan.
enum MembershipRenewal {
    enum Cycle: String, Sendable {
        /// Same day-of-month next month(s), clamped for short months.
        case calendarMonth
    }

    /// All four channels in this app use calendar-month renewal for membership dues.
    static func cycle(forProviderId id: String) -> Cycle {
        switch id {
        case "codex", "kimi", "minimax", "grok":
            return .calendarMonth
        default:
            return .calendarMonth
        }
    }

    static func cycleLabel(forProviderId id: String) -> String {
        "按自然月续费（开通日对月）"
    }

    /// Next renewal after `now`, given activation (开通) date.
    /// Example: open 2026-03-15 → renewals 04-15, 05-15, …; open 01-31 → Feb last day, then 03-31…
    static func nextRenewal(fromActivation activation: Date, now: Date = Date()) -> Date {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: activation)
        let today = cal.startOfDay(for: now)

        if startDay > today {
            return startDay
        }

        var candidate = startDay
        // Advance by whole months until strictly after today (or equal today counts as due today).
        while candidate < today {
            guard let next = cal.date(byAdding: .month, value: 1, to: candidate) else { break }
            candidate = next
        }
        // If activation anniversary is today, that is the renewal day.
        return candidate
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

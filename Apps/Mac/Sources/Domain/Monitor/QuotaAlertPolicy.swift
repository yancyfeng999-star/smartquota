import Foundation

/// Pure rules for threshold / near-reset alerts (no UI, no notifications).
public enum QuotaAlertPolicy: Sendable {
    /// Default: notify when remaining ≤ this % (5h window).
    public static let defaultSessionThreshold: Double = 20
    /// Default: notify when remaining ≤ this % (7d window).
    public static let defaultWeeklyThreshold: Double = 20
    /// Hours before weekly reset to start “underuse / use it” nudges.
    public static let defaultNearResetHours: Double = 24
    /// If remaining ≥ this % when near reset → “快重置了还没用完”.
    public static let defaultUnderuseRemaining: Double = 40

    public enum Kind: String, Sendable, Equatable {
        case sessionLow
        case weeklyLow
        case weeklyUnderuseNearReset
    }

    public struct Evaluation: Sendable, Equatable {
        public let kind: Kind
        public let remaining: Double
        public let threshold: Double
        public let resetsAt: Date?
    }

    /// Returns alerts that should fire for this snapshot given user thresholds.
    public static func evaluate(
        sessionRemaining: Double?,
        weeklyRemaining: Double?,
        weeklyResetsAt: Date?,
        sessionThreshold: Double,
        weeklyThreshold: Double,
        nearResetHours: Double,
        underuseRemaining: Double,
        now: Date = Date()
    ) -> [Evaluation] {
        var out: [Evaluation] = []

        if let s = sessionRemaining, s <= sessionThreshold {
            out.append(Evaluation(
                kind: .sessionLow,
                remaining: s,
                threshold: sessionThreshold,
                resetsAt: nil
            ))
        }

        if let w = weeklyRemaining, w <= weeklyThreshold {
            out.append(Evaluation(
                kind: .weeklyLow,
                remaining: w,
                threshold: weeklyThreshold,
                resetsAt: weeklyResetsAt
            ))
        }

        // Near weekly reset with lots left → remind user to use quota
        if let w = weeklyRemaining,
           let reset = weeklyResetsAt,
           w >= underuseRemaining {
            let hoursLeft = reset.timeIntervalSince(now) / 3600
            if hoursLeft > 0, hoursLeft <= nearResetHours {
                out.append(Evaluation(
                    kind: .weeklyUnderuseNearReset,
                    remaining: w,
                    threshold: underuseRemaining,
                    resetsAt: reset
                ))
            }
        }

        return out
    }

    /// Visual urgency for a reset timestamp (for card text color).
    public enum ResetUrgency: Sendable, Equatable {
        case normal
        case soon      // within nearResetHours
        case imminent  // within 6 hours
    }

    public static func resetUrgency(
        resetsAt: Date?,
        nearResetHours: Double = defaultNearResetHours,
        now: Date = Date()
    ) -> ResetUrgency {
        guard let resetsAt else { return .normal }
        let hours = resetsAt.timeIntervalSince(now) / 3600
        if hours <= 0 { return .imminent }
        if hours <= 6 { return .imminent }
        if hours <= nearResetHours { return .soon }
        return .normal
    }
}

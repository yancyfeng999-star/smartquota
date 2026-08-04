import Testing
import Foundation
@testable import Domain

@Suite("QuotaAlertPolicy")
struct QuotaAlertPolicyTests {
    @Test
    func `session low fires when remaining at or below threshold`() {
        let evals = QuotaAlertPolicy.evaluate(
            sessionRemaining: 15,
            weeklyRemaining: 80,
            weeklyResetsAt: nil,
            sessionThreshold: 20,
            weeklyThreshold: 20,
            nearResetHours: 24,
            underuseRemaining: 40
        )
        #expect(evals.contains { $0.kind == .sessionLow })
        #expect(!evals.contains { $0.kind == .weeklyLow })
    }

    @Test
    func `underuse near reset fires when weekly remaining high and reset soon`() {
        let reset = Date().addingTimeInterval(12 * 3600)
        let evals = QuotaAlertPolicy.evaluate(
            sessionRemaining: 90,
            weeklyRemaining: 55,
            weeklyResetsAt: reset,
            sessionThreshold: 20,
            weeklyThreshold: 20,
            nearResetHours: 24,
            underuseRemaining: 40
        )
        #expect(evals.contains { $0.kind == .weeklyUnderuseNearReset })
    }

    @Test
    func `underuse does not fire when weekly already low`() {
        let reset = Date().addingTimeInterval(12 * 3600)
        let evals = QuotaAlertPolicy.evaluate(
            sessionRemaining: 90,
            weeklyRemaining: 10,
            weeklyResetsAt: reset,
            sessionThreshold: 20,
            weeklyThreshold: 20,
            nearResetHours: 24,
            underuseRemaining: 40
        )
        #expect(evals.contains { $0.kind == .weeklyLow })
        #expect(!evals.contains { $0.kind == .weeklyUnderuseNearReset })
    }

    @Test
    func `reset urgency levels`() {
        let now = Date()
        #expect(QuotaAlertPolicy.resetUrgency(resetsAt: now.addingTimeInterval(48 * 3600), now: now) == .normal)
        #expect(QuotaAlertPolicy.resetUrgency(resetsAt: now.addingTimeInterval(12 * 3600), now: now) == .soon)
        #expect(QuotaAlertPolicy.resetUrgency(resetsAt: now.addingTimeInterval(2 * 3600), now: now) == .imminent)
    }
}

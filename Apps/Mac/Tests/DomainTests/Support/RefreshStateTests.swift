import Testing
import Foundation
@testable import Domain

@Suite("RefreshState Tests")
struct RefreshStateTests {

    @Test
    func `scope and state cases match the shared contract`() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(RefreshScope.provider("codex") == .provider("codex"))
        #expect(RefreshScope.provider("codex") != .provider("claude"))
        #expect(RefreshScope.allEnabledProviders == .allEnabledProviders)
        #expect(RefreshState.idle == .idle)
        #expect(RefreshState.running(scope: .provider("codex"), startedAt: started) == .running(scope: .provider("codex"), startedAt: started))
        #expect(RefreshState.cancelling == .cancelling)
        #expect(RefreshState.completed(successCount: 1, failureCount: 2) == .completed(successCount: 1, failureCount: 2))
        #expect(RefreshState.cancelled(completedCount: 2) == .cancelled(completedCount: 2))
        #expect(RefreshState.failed(message: "timeout") == .failed(message: "timeout"))
    }

    @Test
    func `busy running and cancelling expose completed counts`() {
        #expect(RefreshState.idle.isBusy == false)
        #expect(RefreshState.running(scope: .allEnabledProviders, startedAt: Date()).isBusy)
        #expect(RefreshState.cancelling.isBusy)
        #expect(RefreshState.completed(successCount: 1, failureCount: 1).isBusy == false)
        #expect(RefreshState.cancelled(completedCount: 2).isBusy == false)

        let done = RefreshState.completed(successCount: 1, failureCount: 2)
        #expect(done.successCount == 1)
        #expect(done.failureCount == 2)
        #expect(done.completedCount == 3)
        #expect(RefreshState.cancelled(completedCount: 2).completedCount == 2)
        #expect(RefreshState.idle.completedCount == nil)
    }

    @Test
    func `same provider reuses and a wider all-refresh is rejected while one member runs`() {
        #expect(RefreshScope.provider("codex").shouldReuse(existing: .provider("codex")))
        #expect(RefreshScope.provider("claude").shouldReuse(existing: .provider("codex")) == false)
        #expect(RefreshScope.provider("codex").shouldReuse(existing: .allEnabledProviders))
        #expect(RefreshScope.allEnabledProviders.shouldReuse(existing: .allEnabledProviders))
        #expect(RefreshScope.allEnabledProviders.shouldReuse(existing: .provider("codex")) == false)
        #expect(RefreshScope.provider("codex").overlaps(with: .allEnabledProviders))
    }

    @Test
    func `classifier distinguishes not logged in from connection failed`() {
        #expect(RefreshFailureClassifier.classify(ProbeError.authenticationRequired) == .notLoggedIn)
        #expect(RefreshFailureClassifier.classify(ProbeError.sessionExpired(hint: "relogin")) == .notLoggedIn)
        #expect(RefreshFailureClassifier.classify(ProbeError.timeout) == .connectionFailed)
        #expect(RefreshFailureClassifier.classify(URLError(.timedOut)) == .connectionFailed)
        #expect(RefreshFailureClassifier.classify(URLError(.notConnectedToInternet)) == .connectionFailed)
        #expect(RefreshFailureClassifier.classify(ProbeError.parseFailed("bad")) == .other)
        #expect(RefreshFailureClassifier.excludesFromLiveQuota(ProbeError.timeout))
        #expect(RefreshFailureClassifier.excludesFromLiveQuota(ProbeError.authenticationRequired))
        #expect(RefreshFailureClassifier.excludesFromLiveQuota(nil) == false)
    }

    @Test
    func `sleep pause policy still allows manual refresh`() {
        #expect(RefreshPausePolicy.active.pauseBackgroundRefresh == false)
        #expect(RefreshPausePolicy.active.allowManualRefresh)
        #expect(RefreshPausePolicy.asleep.pauseBackgroundRefresh)
        #expect(RefreshPausePolicy.asleep.allowManualRefresh)
    }

    @Test
    func `lock and low power pause background the same way sleep does`() {
        #expect(RefreshPausePolicy.locked.pauseBackgroundRefresh)
        #expect(RefreshPausePolicy.locked.allowManualRefresh)
        #expect(RefreshPausePolicy.lowPower.pauseBackgroundRefresh)
        #expect(RefreshPausePolicy.lowPower.allowManualRefresh)

        #expect(RefreshPausePolicy.forSystemConditions(
            displayAsleep: false, screenLocked: false, lowPowerMode: false
        ) == .active)
        #expect(RefreshPausePolicy.forSystemConditions(
            displayAsleep: true, screenLocked: false, lowPowerMode: false
        ).pauseBackgroundRefresh)
        #expect(RefreshPausePolicy.forSystemConditions(
            displayAsleep: false, screenLocked: true, lowPowerMode: false
        ).pauseBackgroundRefresh)
        #expect(RefreshPausePolicy.forSystemConditions(
            displayAsleep: false, screenLocked: false, lowPowerMode: true
        ).pauseBackgroundRefresh)
        let paused = RefreshPausePolicy.forSystemConditions(
            displayAsleep: true, screenLocked: true, lowPowerMode: true
        )
        #expect(paused.pauseBackgroundRefresh)
        #expect(paused.allowManualRefresh)
    }

    @Test
    func `retry policy backs off and never retries forever`() {
        #expect(RefreshExecutionPolicy.interactive.maxAttempts == 1)
        #expect(RefreshExecutionPolicy.background.maxAttempts == 3)
        #expect(RefreshExecutionPolicy.background.kind == .background)
        #expect(RefreshExecutionPolicy.background.mergeWindow == 45)

        let policy = RefreshExecutionPolicy.background
        #expect(policy.backoff(forAttempt: 1) == .milliseconds(250))
        #expect(policy.backoff(forAttempt: 2) == .milliseconds(500))
        #expect(policy.backoff(forAttempt: 3) == .milliseconds(1000))
        #expect(policy.maxAttempts < 10)
    }
}

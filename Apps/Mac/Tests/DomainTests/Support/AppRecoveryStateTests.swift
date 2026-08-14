import Testing
@testable import Domain

@Suite("AppRecoveryState Tests")
struct AppRecoveryStateTests {

    @Test
    func `clean signals launch in normal mode`() {
        let state = AppRecoveryState.evaluate(RecoverySignals())
        #expect(state.launchMode == .normal)
        #expect(state.isSafeMode == false)
        #expect(state.shouldLoadUserExtensions)
        #expect(state.shouldStartBackgroundRefresh)
        #expect(state.shouldStartHookService)
        #expect(state.usesReadOnlyDefaultSettings == false)
    }

    @Test
    func `leftover session without clean quit enters previous-launch safe mode`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(leftoverSessionWithoutCleanQuit: true)
        )
        #expect(state.launchMode == .safeMode(reason: .previousLaunchDidNotFinish))
        #expect(state.isSafeMode)
        #expect(state.shouldLoadUserExtensions == false)
        #expect(state.shouldStartBackgroundRefresh == false)
        #expect(state.shouldStartHookService == false)
        #expect(state.usesReadOnlyDefaultSettings == false)
    }

    @Test
    func `settings decode failure uses read-only defaults in safe mode`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: true,
                settingsDecodeFailed: true
            )
        )
        #expect(state.launchMode == .safeMode(reason: .settingsDecodeFailed))
        #expect(state.usesReadOnlyDefaultSettings)
        #expect(state.shouldLoadUserExtensions == false)
        #expect(state.shouldStartBackgroundRefresh == false)
        #expect(state.shouldStartHookService == false)
    }

    @Test
    func `migration failure enters safe mode`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(migrationFailed: true)
        )
        #expect(state.launchMode == .safeMode(reason: .migrationFailed))
        #expect(state.usesReadOnlyDefaultSettings == false)
        #expect(state.shouldStartHookService == false)
    }

    @Test
    func `three unclean launches escalate to repeated startup failure`() {
        let below = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: true,
                consecutiveUncleanLaunches: RecoverySignals.repeatedFailureThreshold - 1
            )
        )
        #expect(below.launchMode == .safeMode(reason: .previousLaunchDidNotFinish))

        let atThreshold = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: true,
                consecutiveUncleanLaunches: RecoverySignals.repeatedFailureThreshold
            )
        )
        #expect(atThreshold.launchMode == .safeMode(reason: .repeatedStartupFailure))
    }

    @Test
    func `settings decode outranks migration repeated and unfinished launch`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: true,
                settingsDecodeFailed: true,
                migrationFailed: true,
                consecutiveUncleanLaunches: RecoverySignals.repeatedFailureThreshold
            )
        )
        #expect(state.launchMode == .safeMode(reason: .settingsDecodeFailed))
    }

    @Test
    func `migration failure outranks repeated and unfinished launch`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: true,
                migrationFailed: true,
                consecutiveUncleanLaunches: RecoverySignals.repeatedFailureThreshold
            )
        )
        #expect(state.launchMode == .safeMode(reason: .migrationFailed))
    }

    @Test
    func `user-initiated clean quit is never treated as a crash`() {
        let state = AppRecoveryState.evaluate(
            RecoverySignals(
                leftoverSessionWithoutCleanQuit: false,
                consecutiveUncleanLaunches: 0
            )
        )
        #expect(state.launchMode == .normal)
        #expect(state.isSafeMode == false)
    }

    @Test
    func `launch mode and reason interfaces match the brief verbatim`() {
        let normal: AppLaunchMode = .normal
        let safe: AppLaunchMode = .safeMode(reason: .previousLaunchDidNotFinish)
        #expect(normal == .normal)
        #expect(safe != .normal)

        #expect(SafeModeReason.previousLaunchDidNotFinish.rawValue == "previousLaunchDidNotFinish")
        #expect(SafeModeReason.settingsDecodeFailed.rawValue == "settingsDecodeFailed")
        #expect(SafeModeReason.migrationFailed.rawValue == "migrationFailed")
        #expect(SafeModeReason.repeatedStartupFailure.rawValue == "repeatedStartupFailure")

        let decoded = SafeModeReason(rawValue: "migrationFailed")
        #expect(decoded == .migrationFailed)
    }
}

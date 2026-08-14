import Foundation

public enum AppLaunchMode: Sendable, Equatable {
    case normal
    case safeMode(reason: SafeModeReason)
}

public enum SafeModeReason: String, Sendable, Codable {
    case previousLaunchDidNotFinish
    case settingsDecodeFailed
    case migrationFailed
    case repeatedStartupFailure
}

/// Inputs collected from session markers and settings/migration probes.
public struct RecoverySignals: Sendable, Equatable {
    public var leftoverSessionWithoutCleanQuit: Bool
    public var settingsDecodeFailed: Bool
    public var migrationFailed: Bool
    public var consecutiveUncleanLaunches: Int

    public static let repeatedFailureThreshold = 3

    public init(
        leftoverSessionWithoutCleanQuit: Bool = false,
        settingsDecodeFailed: Bool = false,
        migrationFailed: Bool = false,
        consecutiveUncleanLaunches: Int = 0
    ) {
        self.leftoverSessionWithoutCleanQuit = leftoverSessionWithoutCleanQuit
        self.settingsDecodeFailed = settingsDecodeFailed
        self.migrationFailed = migrationFailed
        self.consecutiveUncleanLaunches = consecutiveUncleanLaunches
    }
}

/// Launch-mode decision and the side effects Safe Mode must suppress.
public struct AppRecoveryState: Sendable, Equatable {
    public let launchMode: AppLaunchMode

    public init(launchMode: AppLaunchMode) {
        self.launchMode = launchMode
    }

    public static func evaluate(_ signals: RecoverySignals) -> AppRecoveryState {
        let mode: AppLaunchMode
        if signals.settingsDecodeFailed {
            mode = .safeMode(reason: .settingsDecodeFailed)
        } else if signals.migrationFailed {
            mode = .safeMode(reason: .migrationFailed)
        } else if signals.consecutiveUncleanLaunches >= RecoverySignals.repeatedFailureThreshold {
            mode = .safeMode(reason: .repeatedStartupFailure)
        } else if signals.leftoverSessionWithoutCleanQuit {
            mode = .safeMode(reason: .previousLaunchDidNotFinish)
        } else {
            mode = .normal
        }
        return AppRecoveryState(launchMode: mode)
    }

    public var isSafeMode: Bool {
        if case .safeMode = launchMode { return true }
        return false
    }

    public var shouldLoadUserExtensions: Bool { !isSafeMode }
    public var shouldStartBackgroundRefresh: Bool { !isSafeMode }
    public var shouldStartHookService: Bool { !isSafeMode }

    public var usesReadOnlyDefaultSettings: Bool {
        if case .safeMode(let reason) = launchMode {
            return reason == .settingsDecodeFailed
        }
        return false
    }
}

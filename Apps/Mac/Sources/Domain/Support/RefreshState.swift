import Foundation

public enum RefreshState: Sendable, Equatable {
    case idle
    case running(scope: RefreshScope, startedAt: Date)
    case cancelling
    case completed(successCount: Int, failureCount: Int)
    case cancelled(completedCount: Int)
    case failed(message: String)
}

public protocol RefreshCoordinating: Sendable {
    var state: RefreshState { get async }
    func refresh(_ scope: RefreshScope) async
    func cancel() async
}

public enum RefreshFailureKind: Sendable, Equatable {
    case notLoggedIn
    case connectionFailed
    case other
}

public enum RefreshFailureClassifier: Sendable {
    public static func classify(_ error: Error) -> RefreshFailureKind {
        if let probe = error as? ProbeError {
            switch probe {
            case .authenticationRequired, .sessionExpired:
                return .notLoggedIn
            case .timeout:
                return .connectionFailed
            default:
                break
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .connectionFailed
            default:
                break
            }
        }
        return .other
    }

    public static func excludesFromLiveQuota(_ error: Error?) -> Bool {
        error != nil
    }
}

public struct RefreshPausePolicy: Sendable, Equatable {
    public var pauseBackgroundRefresh: Bool
    public var allowManualRefresh: Bool

    public init(pauseBackgroundRefresh: Bool, allowManualRefresh: Bool = true) {
        self.pauseBackgroundRefresh = pauseBackgroundRefresh
        self.allowManualRefresh = allowManualRefresh
    }

    public static let active = RefreshPausePolicy(pauseBackgroundRefresh: false, allowManualRefresh: true)
    public static let asleep = RefreshPausePolicy(pauseBackgroundRefresh: true, allowManualRefresh: true)
    public static let locked = RefreshPausePolicy(pauseBackgroundRefresh: true, allowManualRefresh: true)
    public static let lowPower = RefreshPausePolicy(pauseBackgroundRefresh: true, allowManualRefresh: true)

    /// Sleep, lock, and Low Power Mode all pause non-essential (background) refresh.
    /// Manual refresh stays allowed so a user click is never swallowed.
    public static func forSystemConditions(
        displayAsleep: Bool,
        screenLocked: Bool,
        lowPowerMode: Bool
    ) -> RefreshPausePolicy {
        let pause = displayAsleep || screenLocked || lowPowerMode
        return RefreshPausePolicy(pauseBackgroundRefresh: pause, allowManualRefresh: true)
    }
}

/// Timeouts, merge window, and bounded retry for one refresh run.
public struct RefreshExecutionPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseBackoff: Duration
    public var requestTimeout: Duration?
    public var mergeWindow: TimeInterval?
    public var kind: RefreshKind

    public init(
        maxAttempts: Int,
        baseBackoff: Duration,
        requestTimeout: Duration?,
        mergeWindow: TimeInterval?,
        kind: RefreshKind
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseBackoff = baseBackoff
        self.requestTimeout = requestTimeout
        self.mergeWindow = mergeWindow
        self.kind = kind
    }

    /// User-triggered: one attempt, optional 45s timeout, no auto-retry.
    public static let interactive = RefreshExecutionPolicy(
        maxAttempts: 1,
        baseBackoff: .zero,
        requestTimeout: .seconds(45),
        mergeWindow: nil,
        kind: .interactive
    )

    /// Background: up to 3 attempts with incremental backoff; skip fresh snapshots.
    public static let background = RefreshExecutionPolicy(
        maxAttempts: 3,
        baseBackoff: .milliseconds(250),
        requestTimeout: .seconds(45),
        mergeWindow: 45,
        kind: .background
    )

    /// Incremental backoff for retry `attempt` (1 = first retry after the initial try).
    public func backoff(forAttempt attempt: Int) -> Duration {
        let shift = max(0, attempt - 1)
        let multiplier = 1 << min(shift, 8)
        return baseBackoff * multiplier
    }
}

public extension RefreshState {
    var isBusy: Bool {
        switch self {
        case .running, .cancelling:
            return true
        case .idle, .completed, .cancelled, .failed:
            return false
        }
    }

    var successCount: Int? {
        if case let .completed(success, _) = self { return success }
        return nil
    }

    var failureCount: Int? {
        if case let .completed(_, failure) = self { return failure }
        return nil
    }

    var completedCount: Int? {
        switch self {
        case let .completed(success, failure):
            return success + failure
        case let .cancelled(count):
            return count
        default:
            return nil
        }
    }
}

public extension RefreshScope {
    func overlaps(with other: RefreshScope) -> Bool {
        switch (self, other) {
        case let (.provider(left), .provider(right)):
            return left == right
        case (.allEnabledProviders, .allEnabledProviders):
            return true
        case (.allEnabledProviders, .provider), (.provider, .allEnabledProviders):
            return true
        }
    }

    func shouldReuse(existing: RefreshScope) -> Bool {
        switch (existing, self) {
        case let (.provider(running), .provider(requested)):
            return running == requested
        case (.allEnabledProviders, .allEnabledProviders):
            return true
        case (.allEnabledProviders, .provider):
            return true
        case (.provider, .allEnabledProviders):
            return false
        }
    }
}

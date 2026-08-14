import Foundation
import Domain

/// Counters for one or more refresh runs. Values are safe to log: no URLs,
/// bodies, tokens, cookies, or account identifiers.
public struct RefreshPerformanceSnapshot: Sendable, Equatable {
    public var taskCount: Int
    public var cancelCount: Int
    public var lastDurationMilliseconds: Int
    public var notLoggedInCount: Int
    public var connectionFailedCount: Int
    public var otherFailureCount: Int
    public var inFlightCount: Int

    public init(
        taskCount: Int = 0,
        cancelCount: Int = 0,
        lastDurationMilliseconds: Int = 0,
        notLoggedInCount: Int = 0,
        connectionFailedCount: Int = 0,
        otherFailureCount: Int = 0,
        inFlightCount: Int = 0
    ) {
        self.taskCount = taskCount
        self.cancelCount = cancelCount
        self.lastDurationMilliseconds = lastDurationMilliseconds
        self.notLoggedInCount = notLoggedInCount
        self.connectionFailedCount = connectionFailedCount
        self.otherFailureCount = otherFailureCount
        self.inFlightCount = inFlightCount
    }

    public var logLine: String {
        "refresh metrics duration_ms=\(lastDurationMilliseconds) tasks=\(taskCount) cancels=\(cancelCount) in_flight=\(inFlightCount) failures=notLoggedIn:\(notLoggedInCount),connectionFailed:\(connectionFailedCount),other:\(otherFailureCount)"
    }
}

/// Records refresh duration, failure class, task count, and cancels.
@MainActor
public final class RefreshPerformanceMonitor {
    public private(set) var snapshot = RefreshPerformanceSnapshot()

    public init() {}

    public func recordCancel() {
        snapshot.cancelCount += 1
    }

    public func recordFailure(_ kind: RefreshFailureKind) {
        switch kind {
        case .notLoggedIn:
            snapshot.notLoggedInCount += 1
        case .connectionFailed:
            snapshot.connectionFailedCount += 1
        case .other:
            snapshot.otherFailureCount += 1
        }
    }

    public func setInFlight(_ count: Int) {
        snapshot.inFlightCount = max(0, count)
    }

    public func recordRun(
        duration: Duration,
        taskCount: Int,
        cancelled: Bool,
        failureKinds: [RefreshFailureKind]
    ) {
        snapshot.taskCount += taskCount
        snapshot.lastDurationMilliseconds = Self.milliseconds(from: duration)
        _ = cancelled
        for kind in failureKinds {
            switch kind {
            case .notLoggedIn:
                snapshot.notLoggedInCount += 1
            case .connectionFailed:
                snapshot.connectionFailedCount += 1
            case .other:
                snapshot.otherFailureCount += 1
            }
        }
        snapshot.inFlightCount = 0
        AppLog.refresh.info(snapshot.logLine)
    }

    public static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let fromSeconds = components.seconds * 1_000
        let fromAttoseconds = components.attoseconds / 1_000_000_000_000_000
        return Int(fromSeconds + fromAttoseconds)
    }
}

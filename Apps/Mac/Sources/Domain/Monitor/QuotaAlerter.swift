import Foundation
import Mockable

/// Domain protocol for alerting users about quota changes.
/// Implementations decide how to alert (notifications, sounds, etc.).
@Mockable
public protocol QuotaAlerter: Sendable {
    /// Requests permission to send alerts to the user.
    /// Returns true if permission was granted.
    func requestPermission() async -> Bool

    /// Called when a provider's quota status changes.
    /// Implementations should alert users if the status degraded.
    func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async

    /// Called after each successful refresh so implementations can fire
    /// threshold / near-reset alerts (with their own debouncing).
    /// - Parameters:
    ///   - providerId: The provider that was refreshed
    ///   - accountId: The account identifier for alert key (`providerId.accountId:kind`)
    ///   - snapshot: The usage snapshot from the refresh
    func evaluateSnapshotAlerts(providerId: String, accountId: String, snapshot: UsageSnapshot) async
}

public extension QuotaAlerter {
    func evaluateSnapshotAlerts(providerId: String, accountId: String, snapshot: UsageSnapshot) async {}
}

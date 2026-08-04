import Foundation
import Domain

/// Debounces threshold / underuse notifications so each kind fires at most once
/// per cooldown window (unless remaining recovers above threshold then drops again).
actor ThresholdAlertState {
    private var lastFired: [String: Date] = [:]
    /// Cooldown after a fire for the same provider+kind (avoid spam on every poll).
    private let cooldown: TimeInterval = 4 * 3600

    func shouldFire(key: String, now: Date = Date()) -> Bool {
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastFired[key] = now
        return true
    }

    func clear(keysMatching prefix: String) {
        lastFired = lastFired.filter { !$0.key.hasPrefix(prefix) }
    }
}

import Foundation

/// The user-facing cadence for refreshing the menu-bar number in the background.
///
/// "Off" means no background refresh — the bar updates only when the dropdown
/// opens. Options map to 5 / 10 / 15 / 30 minute polls.
///
/// **Energy:** 1-minute polling was removed from the UI (too hot for a always-on
/// menu-bar agent). Hard floor in `QuotaMonitor` remains 60s for safety if
/// callers pass a short duration. Default when enabling is **15 minutes**.
public enum RefreshInterval: String, Sendable, Equatable, CaseIterable {
    case off
    /// Legacy raw value kept for settings.json migration; maps to five minutes.
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes
    case thirtyMinutes

    /// Options shown in Settings (excludes legacy `oneMinute`).
    public static var pickerCases: [RefreshInterval] {
        [.off, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes]
    }

    /// The poll interval in seconds, or `nil` when refresh is off.
    public var seconds: Int? {
        switch self {
        case .off: nil
        case .oneMinute: 300 // migrate legacy "1 min" → 5 min cadence
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        }
    }

    /// Whether background refresh runs for this option.
    public var isEnabled: Bool { self != .off }

    /// Short label for the settings picker.
    public var label: String {
        switch self {
        case .off: "关闭"
        case .oneMinute: "5 分钟" // legacy
        case .fiveMinutes: "5 分钟"
        case .tenMinutes: "10 分钟"
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        }
    }

    /// Derives the option from the legacy settings pair (`backgroundSyncEnabled`
    /// + `backgroundSyncInterval`), keeping `settings.json` backward compatible.
    public static func migrating(enabled: Bool, storedSeconds: TimeInterval) -> RefreshInterval {
        guard enabled else { return .off }
        let options: [RefreshInterval] = [.fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes]
        return options.min { lhs, rhs in
            abs(Double(lhs.seconds ?? 0) - storedSeconds) < abs(Double(rhs.seconds ?? 0) - storedSeconds)
        } ?? .fifteenMinutes
    }
}

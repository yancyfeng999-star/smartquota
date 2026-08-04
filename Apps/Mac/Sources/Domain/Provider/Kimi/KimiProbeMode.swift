import Foundation

/// The mode used by KimiProvider to fetch usage data.
/// Users can switch between CLI and API modes in Settings.
/// Default is **API** (coding key / browser cookie).
public enum KimiProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use the Kimi CLI (`kimi` with `/usage` command) to fetch usage data.
    case cli

    /// Use the Kimi HTTP API (coding key or browser cookie). Default.
    case api

    /// Human-readable display name for the mode
    public var displayName: String {
        switch self {
        case .cli:
            return "CLI"
        case .api:
            return "API"
        }
    }

    /// Description of what this mode does
    public var description: String {
        switch self {
        case .cli:
            return "Uses kimi /usage command"
        case .api:
            return "Calls Kimi API / local sk-kimi key"
        }
    }
}

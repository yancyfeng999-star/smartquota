import Foundation

/// Cookie source for Xiaomi MiMo Token Plan console authentication.
public enum MiMoCookieSource: String, CaseIterable, Sendable {
    case auto = "auto"
    case manual = "manual"

    public var displayName: String {
        switch self {
        case .auto:
            "Auto (from browser)"
        case .manual:
            "Manual"
        }
    }
}

/// Extracts browser cookies for `platform.xiaomimimo.com`.
public protocol MiMoCookieProviding: Sendable {
    func extractBrowserCookies() -> String?
}

import SwiftUI

// MARK: - Environment injection for AppSettings

/// Optional box so `EnvironmentKey` default is nonisolated (`nil`).
private struct AppSettingsBoxKey: EnvironmentKey {
    static let defaultValue: AppSettings? = nil
}

extension EnvironmentValues {
    /// Shared app settings (theme, language, display, plans…).
    /// Prefer `@Environment(\.appSettings)` in views; falls back to `.shared`.
    @MainActor
    var appSettings: AppSettings {
        get { self[AppSettingsBoxKey.self] ?? AppSettings.shared }
        set { self[AppSettingsBoxKey.self] = newValue }
    }
}

extension View {
    /// Inject app settings into the environment (defaults to `.shared`).
    @MainActor
    func appSettings(_ settings: AppSettings = .shared) -> some View {
        environment(\.appSettings, settings)
    }
}

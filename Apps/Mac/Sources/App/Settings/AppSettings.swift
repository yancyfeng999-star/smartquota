import Foundation
import Domain
import Infrastructure
import ServiceManagement

/// Observable settings manager for 智额 (SmartQuota) preferences.
/// Thin `@Observable` wrapper around `AppSettingsRepository` for SwiftUI reactivity.
/// All persistence is delegated to the repository (`~/.smartquota/settings.json`).
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    /// The underlying repository (internal - views access settings through AppSettings properties/methods)
    private let repository: JSONSettingsRepository

    // MARK: - Language

    /// UI language code (`zh-Hans`, `en`, `ja`, `ko`, `ru`, `ar`, …).
    public var appLanguage: String {
        didSet {
            repository.setAppLanguage(appLanguage)
            L10n.shared.language = AppLanguage.resolve(appLanguage)
        }
    }

    // MARK: - Theme Settings

    /// The current theme mode (light, dark, system, christmas)
    public var themeMode: String {
        didSet {
            repository.setThemeMode(themeMode)
            if !isInitializing {
                userHasChosenTheme = true
            }
        }
    }

    /// Whether the user has explicitly chosen a theme (vs auto-enabled Christmas)
    public var userHasChosenTheme: Bool {
        didSet {
            repository.setUserHasChosenTheme(userHasChosenTheme)
        }
    }

    // MARK: - Display Settings

    /// Whether to show quota as remaining, used, or pace-aware.
    public var usageDisplayMode: UsageDisplayMode {
        didSet {
            repository.setUsageDisplayMode(usageDisplayMode.rawValue)
        }
    }

    /// Whether the menu bar label should show a selected quota percentage instead of the icon.
    public var menuBarPercentageEnabled: Bool {
        didSet {
            repository.setMenuBarPercentageEnabled(menuBarPercentageEnabled)
        }
    }

    /// When true, the menu bar shows quota-status icons (green bars, warning
    /// triangle, etc.). When false (default), shows the brand logo.
    /// Only applies when percentage/duration text is not shown.
    public var menuBarStatusIconEnabled: Bool {
        didSet {
            repository.setMenuBarStatusIconEnabled(menuBarStatusIconEnabled)
        }
    }

    /// Whether the menu bar label should show the compact reset duration for the
    /// selected quota. Independent of `menuBarPercentageEnabled`; both can be on
    /// simultaneously (in which case they are joined by " · ").
    public var menuBarDurationEnabled: Bool {
        didSet {
            repository.setMenuBarDurationEnabled(menuBarDurationEnabled)
        }
    }

    /// Whether a dual-window menu bar label should render as two stacked
    /// smaller lines (one per quota window) instead of one long "A | B" line,
    /// roughly halving the menu bar width it occupies. Opt-in, default off;
    /// has no effect while only a single quota window is shown.
    public var menuBarStackedEnabled: Bool {
        didSet {
            repository.setMenuBarStackedEnabled(menuBarStackedEnabled)
        }
    }

    /// Text size for the stacked menu bar lines. Small is the original 9pt
    /// rendering and the default; Medium (10pt) and Large (11pt) trade some of
    /// the inter-line breathing room for legibility. Only consulted while
    /// `menuBarStackedEnabled` is actually rendering two lines.
    public var menuBarStackedSize: MenuBarStackedSize {
        didSet {
            repository.setMenuBarStackedSize(menuBarStackedSize.rawValue)
        }
    }

    /// Provider used for the menu bar percentage label.
    public var menuBarPercentageProviderId: String {
        didSet {
            repository.setMenuBarPercentageProviderId(menuBarPercentageProviderId)
        }
    }

    /// Quota key used for the menu bar percentage label.
    public var menuBarPercentageQuotaKey: String {
        didSet {
            repository.setMenuBarPercentageQuotaKey(menuBarPercentageQuotaKey)
        }
    }

    /// Optional secondary quota key shown alongside the primary in the menu bar
    /// (e.g. weekly next to session). Empty string means no secondary window.
    public var menuBarSecondaryQuotaKey: String {
        didSet {
            repository.setMenuBarSecondaryQuotaKey(menuBarSecondaryQuotaKey)
        }
    }

    /// Whether to show daily usage report cards (API Cost, Token Usage, Working Time)
    public var showDailyUsageCards: Bool {
        didSet {
            repository.setShowDailyUsageCards(showDailyUsageCards)
        }
    }

    // MARK: - Overview Mode Settings

    /// Whether to show all enabled providers at once instead of one at a time
    public var overviewModeEnabled: Bool {
        didSet {
            repository.setOverviewModeEnabled(overviewModeEnabled)
        }
    }

    // MARK: - Membership plan labels

    /// Manual plan label (e.g. "Pro 20X"). Empty string means auto/default.
    public func planLabel(for providerId: String) -> String {
        repository.planLabel(forProvider: providerId)
    }

    public func setPlanLabel(_ label: String, for providerId: String) {
        repository.setPlanLabel(label, forProvider: providerId)
        // Bump a token so SwiftUI views depending on plan labels refresh.
        planLabelsRevision &+= 1
    }

    /// Membership renewal date string (`yyyy-MM-dd` or free text). Empty = not set.
    public func renewalDate(for providerId: String) -> String {
        repository.renewalDate(forProvider: providerId)
    }

    public func setRenewalDate(_ date: String, for providerId: String) {
        repository.setRenewalDate(date, forProvider: providerId)
        planLabelsRevision &+= 1
    }

    /// Observation token — increment when any plan label / renewal date changes.
    public private(set) var planLabelsRevision: Int = 0

    // MARK: - Membership card order

    /// Provider ids top→bottom on the main menu. Empty → product default order.
    public var membershipOrder: [String] {
        didSet {
            repository.setMembershipOrder(membershipOrder)
            membershipOrderRevision &+= 1
        }
    }

    public private(set) var membershipOrderRevision: Int = 0

    /// Whether the floating always-on-top window is open (not the menu popover).
    public var windowPinned: Bool = false

    // MARK: - Quota threshold alerts (5h / 7d remaining %)

    /// Master switch for custom threshold + near-reset underuse notifications.
    public var quotaThresholdAlertsEnabled: Bool {
        didSet { repository.setQuotaThresholdAlertsEnabled(quotaThresholdAlertsEnabled) }
    }

    /// Alert when 5h remaining % is at or below this value (default 20).
    public var sessionAlertThreshold: Double {
        didSet { repository.setSessionAlertThreshold(sessionAlertThreshold) }
    }

    /// Alert when 7d remaining % is at or below this value (default 20).
    public var weeklyAlertThreshold: Double {
        didSet { repository.setWeeklyAlertThreshold(weeklyAlertThreshold) }
    }

    /// Hours before weekly reset to start underuse reminders (default 24).
    public var nearResetAlertHours: Double {
        didSet { repository.setNearResetAlertHours(nearResetAlertHours) }
    }

    /// If weekly remaining ≥ this % when near reset → “快重置还没用完” (default 40).
    public var underuseAlertRemaining: Double {
        didSet { repository.setUnderuseAlertRemaining(underuseAlertRemaining) }
    }

    // MARK: - Background Sync Settings

    /// Whether background sync is enabled (default: false)
    public var backgroundSyncEnabled: Bool {
        didSet {
            repository.setBackgroundSyncEnabled(backgroundSyncEnabled)
        }
    }

    /// Background sync interval in seconds (default: 60)
    public var backgroundSyncInterval: TimeInterval {
        didSet {
            repository.setBackgroundSyncInterval(backgroundSyncInterval)
        }
    }

    /// The background-refresh cadence (Off / 1 / 5 / 15 min) as a single
    /// picker-friendly value. Computed over the legacy `backgroundSyncEnabled`
    /// + `backgroundSyncInterval` pair so `settings.json` stays backward
    /// compatible — "Off" maps to `backgroundSyncEnabled == false`, the others
    /// to enabled + 60/300/600/900s. Setting it persists both underlying keys.
    public var refreshInterval: RefreshInterval {
        get {
            RefreshInterval.migrating(
                enabled: backgroundSyncEnabled,
                storedSeconds: backgroundSyncInterval
            )
        }
        set {
            // Set the interval before flipping enabled so anything observing the
            // change sees the final cadence in a single pass.
            if let seconds = newValue.seconds {
                backgroundSyncInterval = TimeInterval(seconds)
            }
            backgroundSyncEnabled = newValue.isEnabled
        }
    }

    // MARK: - Claude API Budget Settings

    /// Whether Claude API budget tracking is enabled
    public var claudeApiBudgetEnabled: Bool {
        didSet {
            repository.setClaudeApiBudgetEnabled(claudeApiBudgetEnabled)
        }
    }

    /// The budget threshold for Claude API usage (in dollars)
    public var claudeApiBudget: Decimal {
        didSet {
            repository.setClaudeApiBudget(NSDecimalNumber(decimal: claudeApiBudget).doubleValue)
        }
    }

    // MARK: - Burn Rate Warning Settings

    /// Whether burn rate-based warnings are enabled (default: false, uses absolute thresholds)
    public var burnRateWarningEnabled: Bool {
        didSet {
            repository.setBurnRateWarningEnabled(burnRateWarningEnabled)
        }
    }

    /// The burn rate multiplier threshold above which warnings fire (default: 1.5)
    public var burnRateThreshold: Double {
        didSet {
            repository.setBurnRateThreshold(burnRateThreshold)
        }
    }

    // MARK: - Update Settings

    /// Whether to receive beta updates (default: false)
    public var receiveBetaUpdates: Bool {
        didSet {
            repository.setReceiveBetaUpdates(receiveBetaUpdates)
            NotificationCenter.default.post(name: .betaUpdatesSettingChanged, object: nil)
        }
    }

    // MARK: - Launch at Login Settings

    /// Whether the app should launch at login (backed by SMAppService, not JSON)
    public var launchAtLogin: Bool {
        didSet {
            guard !isInitializing else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Internal

    private var isInitializing = true

    // MARK: - Initialization

    private init(repository: JSONSettingsRepository = .shared) {
        self.repository = repository

        // Load all values from repository
        let languageCode = repository.appLanguage()
        self.appLanguage = languageCode
        self.themeMode = repository.themeMode()
        self.userHasChosenTheme = repository.userHasChosenTheme()
        self.claudeApiBudgetEnabled = repository.claudeApiBudgetEnabled()
        self.claudeApiBudget = Decimal(repository.claudeApiBudget())
        self.receiveBetaUpdates = repository.receiveBetaUpdates()
        self.burnRateWarningEnabled = repository.burnRateWarningEnabled()
        self.burnRateThreshold = repository.burnRateThreshold()
        self.showDailyUsageCards = repository.showDailyUsageCards()
        self.overviewModeEnabled = repository.overviewModeEnabled()
        self.backgroundSyncEnabled = repository.backgroundSyncEnabled()
        self.backgroundSyncInterval = repository.backgroundSyncInterval()
        self.quotaThresholdAlertsEnabled = repository.quotaThresholdAlertsEnabled()
        self.sessionAlertThreshold = repository.sessionAlertThreshold()
        self.weeklyAlertThreshold = repository.weeklyAlertThreshold()
        self.nearResetAlertHours = repository.nearResetAlertHours()
        self.underuseAlertRemaining = repository.underuseAlertRemaining()
        self.menuBarPercentageEnabled = repository.menuBarPercentageEnabled()
        self.menuBarStatusIconEnabled = repository.menuBarStatusIconEnabled()
        self.menuBarDurationEnabled = repository.menuBarDurationEnabled()
        self.menuBarStackedEnabled = repository.menuBarStackedEnabled()
        // The stored size decodes through the Domain fallback so an unknown
        // raw value (from a newer build's settings file) renders small
        // instead of crashing or dropping the label.
        self.menuBarStackedSize = MenuBarStackedSize(storedRawValue: repository.menuBarStackedSize())
        self.menuBarPercentageProviderId = repository.menuBarPercentageProviderId()
        self.menuBarPercentageQuotaKey = repository.menuBarPercentageQuotaKey()
        self.menuBarSecondaryQuotaKey = repository.menuBarSecondaryQuotaKey()
        self.membershipOrder = repository.membershipOrder()

        if let mode = UsageDisplayMode(rawValue: repository.usageDisplayMode()) {
            self.usageDisplayMode = mode
        } else {
            self.usageDisplayMode = .remaining
        }

        // Launch at login - read from SMAppService (system service, not JSON)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        applySeasonalTheme()
        self.isInitializing = false
        // Apply language after full init (didSet is skipped during init).
        L10n.shared.language = AppLanguage.resolve(languageCode)
    }

    // MARK: - Seasonal Theme

    public static func isChristmasPeriod(date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return false }
        return month == 12 && (24...26).contains(day)
    }

    private func applySeasonalTheme() {
        let isChristmas = Self.isChristmasPeriod()

        if isChristmas {
            if !userHasChosenTheme {
                themeMode = "christmas"
            }
        } else {
            if themeMode == "christmas" && !userHasChosenTheme {
                themeMode = "system"
            }
        }
    }

    // MARK: - Provider Settings Access

    /// Access provider-specific settings for reading/writing in Settings UI.
    /// These are non-observable (loaded into @State) - only app-level settings are @Observable.
    public var provider: ProviderSettingsRepository { repository }
    public var claude: ClaudeSettingsRepository { repository }
    public var codex: CodexSettingsRepository { repository }
    public var kimi: KimiSettingsRepository { repository }
    public var copilot: CopilotSettingsRepository { repository }
    public var zai: ZaiSettingsRepository { repository }
    public var bedrock: BedrockSettingsRepository { repository }
    public var minimax: MiniMaxSettingsRepository { repository }
    public var alibaba: AlibabaSettingsRepository { repository }
    public var mimo: MiMoSettingsRepository { repository }
    public var hook: HookSettingsRepository { repository }

    /// Extension config repository for dynamic extension provider settings.
    public let extensionConfig: any ExtensionConfigRepository = JSONExtensionConfigRepository(
        settingsStore: .shared
    )
}

// MARK: - Notification Names

extension Notification.Name {
    static let betaUpdatesSettingChanged = Notification.Name("betaUpdatesSettingChanged")
}

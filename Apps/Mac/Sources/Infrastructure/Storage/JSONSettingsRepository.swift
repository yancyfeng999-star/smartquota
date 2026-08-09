import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols) + HookSettingsRepository.
///
/// Backed by `JSONSettingsStore` reading/writing `~/.smartquota/settings.json`.
/// Credentials (tokens, API keys) use UserDefaults for now (Keychain migration later).
public final class JSONSettingsRepository:
    AppSettingsRepository,
    ZaiSettingsRepository,
    CopilotSettingsRepository,
    BedrockSettingsRepository,
    ClaudeSettingsRepository,
    CodexSettingsRepository,
    KimiSettingsRepository,
    MiniMaxSettingsRepository,
    AlibabaSettingsRepository,
    MiMoSettingsRepository,
    HookSettingsRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let credentials: UserDefaults

    public init(store: JSONSettingsStore, credentials: UserDefaults = .standard) {
        self.store = store
        self.credentials = credentials
    }

    // MARK: - AppSettingsRepository

    public func themeMode() -> String {
        store.read(key: "app.themeMode") ?? "system"
    }

    public func setThemeMode(_ mode: String) {
        store.write(value: mode, key: "app.themeMode")
    }

    /// UI language code (`zh-Hans`, `en`, `ja`, …). Default Simplified Chinese.
    public func appLanguage() -> String {
        store.read(key: "app.language") ?? "zh-Hans"
    }

    public func setAppLanguage(_ code: String) {
        store.write(value: code, key: "app.language")
    }

    public func userHasChosenTheme() -> Bool {
        store.read(key: "app.userHasChosenTheme") ?? false
    }

    public func setUserHasChosenTheme(_ chosen: Bool) {
        store.write(value: chosen, key: "app.userHasChosenTheme")
    }

    public func usageDisplayMode() -> String {
        store.read(key: "app.usageDisplayMode") ?? "remaining"
    }

    public func setUsageDisplayMode(_ mode: String) {
        store.write(value: mode, key: "app.usageDisplayMode")
    }

    public func menuBarPercentageEnabled() -> Bool {
        store.read(key: "app.menuBarPercentageEnabled") ?? false
    }

    public func setMenuBarPercentageEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarPercentageEnabled")
    }

    public func menuBarStatusIconEnabled() -> Bool {
        store.read(key: "app.menuBarStatusIconEnabled") ?? false
    }

    public func setMenuBarStatusIconEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarStatusIconEnabled")
    }

    public func menuBarDurationEnabled() -> Bool {
        store.read(key: "app.menuBarDurationEnabled") ?? false
    }

    public func setMenuBarDurationEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarDurationEnabled")
    }

    public func menuBarStackedEnabled() -> Bool {
        store.read(key: "app.menuBarStackedEnabled") ?? false
    }

    public func setMenuBarStackedEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarStackedEnabled")
    }

    public func menuBarStackedSize() -> String {
        store.read(key: "app.menuBarStackedSize") ?? "small"
    }

    public func setMenuBarStackedSize(_ size: String) {
        store.write(value: size, key: "app.menuBarStackedSize")
    }

    public func menuBarPercentageProviderId() -> String {
        store.read(key: "app.menuBarPercentageProviderId") ?? "claude"
    }

    public func setMenuBarPercentageProviderId(_ providerId: String) {
        store.write(value: providerId, key: "app.menuBarPercentageProviderId")
    }

    public func menuBarPercentageQuotaKey() -> String {
        store.read(key: "app.menuBarPercentageQuotaKey") ?? "session"
    }

    public func setMenuBarPercentageQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarPercentageQuotaKey")
    }

    public func menuBarSecondaryQuotaKey() -> String {
        store.read(key: "app.menuBarSecondaryQuotaKey") ?? ""
    }

    public func setMenuBarSecondaryQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarSecondaryQuotaKey")
    }

    public func showDailyUsageCards() -> Bool {
        store.read(key: "app.showDailyUsageCards") ?? true
    }

    public func setShowDailyUsageCards(_ show: Bool) {
        store.write(value: show, key: "app.showDailyUsageCards")
    }

    public func overviewModeEnabled() -> Bool {
        store.read(key: "app.overviewModeEnabled") ?? false
    }

    public func setOverviewModeEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.overviewModeEnabled")
    }

    // MARK: - Membership plan labels (manual override)

    /// User-entered plan label for a provider (e.g. "Pro 20X"). Empty = use auto/default.
    public func planLabel(forProvider id: String) -> String {
        store.read(key: "providers.\(id).planLabel") ?? ""
    }

    public func setPlanLabel(_ label: String, forProvider id: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.write(value: nil, key: "providers.\(id).planLabel")
        } else {
            store.write(value: trimmed, key: "providers.\(id).planLabel")
        }
    }

    /// Membership renewal date as `yyyy-MM-dd` (manual). Empty = not set.
    public func renewalDate(forProvider id: String) -> String {
        store.read(key: "providers.\(id).renewalDate") ?? ""
    }

    public func setRenewalDate(_ date: String, forProvider id: String) {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.write(value: nil, key: "providers.\(id).renewalDate")
        } else {
            store.write(value: trimmed, key: "providers.\(id).renewalDate")
        }
    }

    /// User-defined membership card order (provider ids). Empty = default ChatGPT→Kimi→MiniMax→Grok.
    public func membershipOrder() -> [String] {
        store.read(key: "app.membershipOrder") ?? []
    }

    public func setMembershipOrder(_ order: [String]) {
        store.write(value: order, key: "app.membershipOrder")
    }

    public func backgroundSyncEnabled() -> Bool {
        store.read(key: "app.backgroundSyncEnabled") ?? false
    }

    public func setBackgroundSyncEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.backgroundSyncEnabled")
    }

    public func backgroundSyncInterval() -> TimeInterval {
        // Default 15 min when enabled: lower CPU/energy for always-on menu bar.
        store.read(key: "app.backgroundSyncInterval") ?? 900
    }

    public func setBackgroundSyncInterval(_ interval: TimeInterval) {
        store.write(value: interval, key: "app.backgroundSyncInterval")
    }

    public func claudeApiBudgetEnabled() -> Bool {
        store.read(key: "app.claudeApiBudgetEnabled") ?? false
    }

    public func setClaudeApiBudgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.claudeApiBudgetEnabled")
    }

    public func claudeApiBudget() -> Double {
        store.read(key: "app.claudeApiBudget") ?? 0
    }

    public func setClaudeApiBudget(_ amount: Double) {
        store.write(value: amount, key: "app.claudeApiBudget")
    }

    // MARK: - Burn Rate Warning

    public func burnRateWarningEnabled() -> Bool {
        store.read(key: "app.burnRateWarningEnabled") ?? false
    }

    public func setBurnRateWarningEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.burnRateWarningEnabled")
    }

    public func burnRateThreshold() -> Double {
        store.read(key: "app.burnRateThreshold") ?? 1.5
    }

    public func setBurnRateThreshold(_ threshold: Double) {
        store.write(value: threshold, key: "app.burnRateThreshold")
    }

    // MARK: - Quota threshold alerts

    public func quotaThresholdAlertsEnabled() -> Bool {
        store.read(key: "app.quotaThresholdAlertsEnabled") ?? true
    }

    public func setQuotaThresholdAlertsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.quotaThresholdAlertsEnabled")
    }

    public func sessionAlertThreshold() -> Double {
        store.read(key: "app.sessionAlertThreshold") ?? 20
    }

    public func setSessionAlertThreshold(_ value: Double) {
        store.write(value: value, key: "app.sessionAlertThreshold")
    }

    public func weeklyAlertThreshold() -> Double {
        store.read(key: "app.weeklyAlertThreshold") ?? 20
    }

    public func setWeeklyAlertThreshold(_ value: Double) {
        store.write(value: value, key: "app.weeklyAlertThreshold")
    }

    public func nearResetAlertHours() -> Double {
        store.read(key: "app.nearResetAlertHours") ?? 24
    }

    public func setNearResetAlertHours(_ value: Double) {
        store.write(value: value, key: "app.nearResetAlertHours")
    }

    public func underuseAlertRemaining() -> Double {
        store.read(key: "app.underuseAlertRemaining") ?? 40
    }

    public func setUnderuseAlertRemaining(_ value: Double) {
        store.write(value: value, key: "app.underuseAlertRemaining")
    }

    public func receiveBetaUpdates() -> Bool {
        store.read(key: "app.receiveBetaUpdates") ?? false
    }

    public func setReceiveBetaUpdates(_ receive: Bool) {
        store.write(value: receive, key: "app.receiveBetaUpdates")
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        store.read(key: "providers.\(id).isEnabled") ?? defaultValue
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        store.write(value: enabled, key: "providers.\(id).isEnabled")
    }

    public func customCardURL(forProvider id: String) -> String? {
        store.read(key: "providers.\(id).customCardURL")
    }

    public func setCustomCardURL(_ url: String?, forProvider id: String) {
        let value: Any? = (url?.isEmpty == false) ? url : nil
        store.write(value: value, key: "providers.\(id).customCardURL")
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let raw: String = store.read(key: "claude.probeMode"),
              let mode = ClaudeProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        store.write(value: mode.rawValue, key: "claude.probeMode")
    }

    public func claudeCliFallbackEnabled() -> Bool {
        store.read(key: "claude.cliFallbackEnabled") ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "claude.cliFallbackEnabled")
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let raw: String = store.read(key: "codex.probeMode"),
              let mode = CodexProbeMode(rawValue: raw) else {
            // API mode uses ~/.codex/auth.json directly (verified working)
            return .api
        }
        return mode
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        store.write(value: mode.rawValue, key: "codex.probeMode")
    }

    // MARK: - KimiSettingsRepository

    public func kimiProbeMode() -> KimiProbeMode {
        guard let raw: String = store.read(key: "kimi.probeMode"),
              let mode = KimiProbeMode(rawValue: raw) else {
            // default to API (sk-kimi / cookie), not CLI
            return .api
        }
        return mode
    }

    public func setKimiProbeMode(_ mode: KimiProbeMode) {
        store.write(value: mode.rawValue, key: "kimi.probeMode")
    }

    // MARK: - ZaiSettingsRepository

    public func zaiConfigPath() -> String {
        store.read(key: "zai.configPath") ?? ""
    }

    public func setZaiConfigPath(_ path: String) {
        store.write(value: path, key: "zai.configPath")
    }

    public func glmAuthEnvVar() -> String {
        store.read(key: "zai.glmAuthEnvVar") ?? ""
    }

    public func setGlmAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "zai.glmAuthEnvVar")
    }

    // MARK: - CopilotSettingsRepository

    public func copilotProbeMode() -> CopilotProbeMode {
        guard let raw: String = store.read(key: "copilot.probeMode"),
              let mode = CopilotProbeMode(rawValue: raw) else {
            return .billing
        }
        return mode
    }

    public func setCopilotProbeMode(_ mode: CopilotProbeMode) {
        store.write(value: mode.rawValue, key: "copilot.probeMode")
    }

    public func copilotAuthEnvVar() -> String {
        store.read(key: "copilot.authEnvVar") ?? ""
    }

    public func setCopilotAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "copilot.authEnvVar")
    }

    public func copilotMonthlyLimit() -> Int? {
        store.read(key: "copilot.monthlyLimit")
    }

    public func setCopilotMonthlyLimit(_ limit: Int?) {
        store.write(value: limit, key: "copilot.monthlyLimit")
    }

    public func copilotManualUsageValue() -> Double? {
        store.read(key: "copilot.manualUsageValue")
    }

    public func setCopilotManualUsageValue(_ value: Double?) {
        store.write(value: value, key: "copilot.manualUsageValue")
    }

    public func copilotManualUsageIsPercent() -> Bool {
        store.read(key: "copilot.manualUsageIsPercent") ?? false
    }

    public func setCopilotManualUsageIsPercent(_ isPercent: Bool) {
        store.write(value: isPercent, key: "copilot.manualUsageIsPercent")
    }

    public func copilotManualOverrideEnabled() -> Bool {
        store.read(key: "copilot.manualOverrideEnabled") ?? false
    }

    public func setCopilotManualOverrideEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "copilot.manualOverrideEnabled")
    }

    public func copilotApiReturnedEmpty() -> Bool {
        store.read(key: "copilot.apiReturnedEmpty") ?? false
    }

    public func setCopilotApiReturnedEmpty(_ empty: Bool) {
        store.write(value: empty, key: "copilot.apiReturnedEmpty")
    }

    public func copilotLastUsagePeriodMonth() -> Int? {
        store.read(key: "copilot.lastUsagePeriodMonth")
    }

    public func copilotLastUsagePeriodYear() -> Int? {
        store.read(key: "copilot.lastUsagePeriodYear")
    }

    public func setCopilotLastUsagePeriod(month: Int, year: Int) {
        store.write(value: month, key: "copilot.lastUsagePeriodMonth")
        store.write(value: year, key: "copilot.lastUsagePeriodYear")
    }

    // Credentials — Keychain (with one-time UserDefaults migration)

    private enum SecretAccount {
        static let githubToken = "github-copilot-token"
        static let githubUsername = "github-username"
        static let minimaxApiKey = "minimax-api-key"
        static let alibabaCookie = "alibaba-manual-cookie"
        static let alibabaApiKey = "alibaba-api-key"
        static let mimoCookie = "mimo-manual-cookie"
    }

    /// UserDefaults keys used only for one-time migration into Keychain.
    private enum DefaultsCredentialKey {
        static let githubToken = "com.smartquota.credentials.github-copilot-token"
        static let githubUsername = "com.smartquota.credentials.github-username"
        static let minimaxApiKey = "com.smartquota.credentials.minimax-api-key"
        static let alibabaCookie = "com.smartquota.credentials.alibaba-manual-cookie"
        static let alibabaApiKey = "com.smartquota.credentials.alibaba-api-key"
        static let mimoCookie = "com.smartquota.credentials.mimo-manual-cookie"
    }

    public func saveGithubToken(_ token: String) {
        KeychainSecretStore.set(token, account: SecretAccount.githubToken)
        credentials.removeObject(forKey: DefaultsCredentialKey.githubToken)
    }

    public func getGithubToken() -> String? {
        secret(account: SecretAccount.githubToken, defaultsKey: DefaultsCredentialKey.githubToken)
    }

    public func deleteGithubToken() {
        KeychainSecretStore.delete(account: SecretAccount.githubToken)
        credentials.removeObject(forKey: DefaultsCredentialKey.githubToken)
    }

    public func hasGithubToken() -> Bool {
        getGithubToken() != nil
    }

    public func saveGithubUsername(_ username: String) {
        KeychainSecretStore.set(username, account: SecretAccount.githubUsername)
        credentials.removeObject(forKey: DefaultsCredentialKey.githubUsername)
    }

    public func getGithubUsername() -> String? {
        secret(account: SecretAccount.githubUsername, defaultsKey: DefaultsCredentialKey.githubUsername)
    }

    public func deleteGithubUsername() {
        KeychainSecretStore.delete(account: SecretAccount.githubUsername)
        credentials.removeObject(forKey: DefaultsCredentialKey.githubUsername)
    }

    private func secret(account: String, defaultsKey: String) -> String? {
        if let value = KeychainSecretStore.getMigratingFromUserDefaults(
            account: account,
            userDefaults: credentials,
            defaultsKey: defaultsKey
        ) {
            return value
        }
        return KeychainSecretStore.get(account: account)
    }

    // MARK: - BedrockSettingsRepository

    public func awsProfileName() -> String {
        store.read(key: "bedrock.awsProfile") ?? ""
    }

    public func setAWSProfileName(_ name: String) {
        store.write(value: name, key: "bedrock.awsProfile")
    }

    public func bedrockRegions() -> [String] {
        store.read(key: "bedrock.regions") ?? ["us-east-1"]
    }

    public func setBedrockRegions(_ regions: [String]) {
        store.write(value: regions, key: "bedrock.regions")
    }

    public func bedrockDailyBudget() -> Decimal? {
        guard let value: Double = store.read(key: "bedrock.dailyBudget") else { return nil }
        return Decimal(value)
    }

    public func setBedrockDailyBudget(_ amount: Decimal?) {
        if let amount = amount {
            store.write(value: NSDecimalNumber(decimal: amount).doubleValue, key: "bedrock.dailyBudget")
        } else {
            store.write(value: nil, key: "bedrock.dailyBudget")
        }
    }

    // MARK: - MiMoSettingsRepository

    public func mimoCookieSource() -> MiMoCookieSource {
        guard let rawValue: String = store.read(key: "mimo.cookieSource") else {
            return .auto
        }
        return MiMoCookieSource(rawValue: rawValue) ?? .auto
    }

    public func setMimoCookieSource(_ source: MiMoCookieSource) {
        store.write(value: source.rawValue, key: "mimo.cookieSource")
    }

    public func saveMimoManualCookie(_ cookie: String) {
        KeychainSecretStore.set(cookie, account: SecretAccount.mimoCookie)
        credentials.removeObject(forKey: DefaultsCredentialKey.mimoCookie)
    }

    public func getMimoManualCookie() -> String? {
        secret(account: SecretAccount.mimoCookie, defaultsKey: DefaultsCredentialKey.mimoCookie)
    }

    public func deleteMimoManualCookie() {
        KeychainSecretStore.delete(account: SecretAccount.mimoCookie)
        credentials.removeObject(forKey: DefaultsCredentialKey.mimoCookie)
    }

    // MARK: - AlibabaSettingsRepository

    public func alibabaRegion() -> AlibabaRegion {
        guard let rawValue: String = store.read(key: "alibaba.region") else {
            return .international
        }
        return AlibabaRegion(rawValue: rawValue) ?? .international
    }

    public func setAlibabaRegion(_ region: AlibabaRegion) {
        store.write(value: region.rawValue, key: "alibaba.region")
    }

    public func alibabaCookieSource() -> AlibabaCookieSource {
        guard let rawValue: String = store.read(key: "alibaba.cookieSource") else {
            return .auto
        }
        return AlibabaCookieSource(rawValue: rawValue) ?? .auto
    }

    public func setAlibabaCookieSource(_ source: AlibabaCookieSource) {
        store.write(value: source.rawValue, key: "alibaba.cookieSource")
    }

    public func saveAlibabaManualCookie(_ cookie: String) {
        KeychainSecretStore.set(cookie, account: SecretAccount.alibabaCookie)
        credentials.removeObject(forKey: DefaultsCredentialKey.alibabaCookie)
    }

    public func getAlibabaManualCookie() -> String? {
        secret(account: SecretAccount.alibabaCookie, defaultsKey: DefaultsCredentialKey.alibabaCookie)
    }

    public func saveAlibabaApiKey(_ key: String) {
        KeychainSecretStore.set(key, account: SecretAccount.alibabaApiKey)
        credentials.removeObject(forKey: DefaultsCredentialKey.alibabaApiKey)
    }

    public func getAlibabaApiKey() -> String? {
        secret(account: SecretAccount.alibabaApiKey, defaultsKey: DefaultsCredentialKey.alibabaApiKey)
    }

    public func deleteAlibabaApiKey() {
        KeychainSecretStore.delete(account: SecretAccount.alibabaApiKey)
        credentials.removeObject(forKey: DefaultsCredentialKey.alibabaApiKey)
    }

    public func hasAlibabaApiKey() -> Bool {
        getAlibabaApiKey() != nil
    }

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        store.read(key: "hook.enabled") ?? false
    }

    public func setHookEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "hook.enabled")
    }

    public func hookPort() -> Int {
        let port: Int = store.read(key: "hook.port") ?? Int(HookConstants.defaultPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        store.write(value: port, key: "hook.port")
    }

    // MARK: - MiniMaxSettingsRepository

    public func minimaxRegion() -> MiniMaxRegion {
        guard let raw: String = store.read(key: "minimax.region"),
              let region = MiniMaxRegion(rawValue: raw) else {
            return .china
        }
        return region
    }

    public func setMinimaxRegion(_ region: MiniMaxRegion) {
        store.write(value: region.rawValue, key: "minimax.region")
    }

    public func minimaxAuthEnvVar() -> String {
        store.read(key: "minimax.authEnvVar") ?? ""
    }

    public func setMinimaxAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "minimax.authEnvVar")
    }

    // MiniMax Credentials (Keychain + UD migration)

    public func saveMinimaxApiKey(_ key: String) {
        KeychainSecretStore.set(key, account: SecretAccount.minimaxApiKey)
        credentials.removeObject(forKey: DefaultsCredentialKey.minimaxApiKey)
    }

    public func getMinimaxApiKey() -> String? {
        secret(account: SecretAccount.minimaxApiKey, defaultsKey: DefaultsCredentialKey.minimaxApiKey)
    }

    public func deleteMinimaxApiKey() {
        KeychainSecretStore.delete(account: SecretAccount.minimaxApiKey)
        credentials.removeObject(forKey: DefaultsCredentialKey.minimaxApiKey)
    }

    public func hasMinimaxApiKey() -> Bool {
        getMinimaxApiKey() != nil
    }

    /// Returns stored enabled flag if the user has ever set it; nil if never configured.
    public func explicitEnabled(forProvider id: String) -> Bool? {
        store.read(key: "providers.\(id).isEnabled")
    }
}

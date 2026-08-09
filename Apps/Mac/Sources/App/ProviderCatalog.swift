import Foundation
import Domain
import Infrastructure

/// Central registry of built-in AI membership providers.
///
/// New providers: implement Domain + Infrastructure probes, then add one entry
/// in `makeAllProviders`. Settings toggles and extension loading stay separate
/// so more memberships can be added without rewriting the app shell.
@MainActor
enum ProviderCatalog {
    /// Core products that remain enabled by default for existing 智额 users.
    static let coreProviderIDs: Set<String> = [
        "codex", "kimi", "minimax", "grok",
    ]

    /// Stable display order for 会员开关 / 额度检测配置 lists.
    static let displayOrder: [String] = [
        "codex", "kimi", "minimax", "grok",
        "claude", "gemini", "copilot", "cursor", "antigravity",
        "zai", "bedrock", "alibaba", "mimo",
        "ampcode", "kiro", "mistral", "opencode-go", "omp",
    ]

    /// Optional fallback plan labels when the user has not set one and the API
    /// tier is unavailable. **Left empty on purpose** in the open-source tree —
    /// do not hardcode personal subscriptions or account tiers here.
    /// Users set plan names in Settings; runtime may also map API tier tokens.
    static let defaultPlanLabels: [String: String] = [:]

    /// Builds every built-in provider.
    /// Order is stable for first-run display; user reorder is persisted elsewhere.
    static func makeAllProviders(
        settingsRepository: JSONSettingsRepository
    ) -> [any AIProvider] {
        var list: [any AIProvider] = []

        // --- Core 4 (product focus) ---
        list.append(
            CodexProvider(
                rpcProbe: CodexUsageProbe(),
                apiProbe: CodexAPIUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            KimiProvider(
                cliProbe: KimiCLIUsageProbe(),
                apiProbe: KimiUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            MiniMaxProvider(
                probe: MiniMaxUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            GrokProvider(
                probe: GrokUsageProbe(),
                settingsRepository: settingsRepository
            )
        )

        // --- Common open-source / quota providers ---
        list.append(
            ClaudeProvider(
                cliProbe: ClaudeUsageProbe(),
                apiProbe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settingsRepository,
                dailyUsageAnalyzer: ClaudeDailyUsageAnalyzer()
            )
        )
        list.append(
            GeminiProvider(
                probe: GeminiUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            CopilotProvider(
                billingProbe: CopilotUsageProbe(settingsRepository: settingsRepository),
                internalProbe: CopilotInternalAPIProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            CursorProvider(
                probe: CursorUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            AntigravityProvider(
                probe: AntigravityUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            ZaiProvider(
                probe: ZaiUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            BedrockProvider(
                probe: BedrockUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            AlibabaProvider(
                probe: AlibabaUsageProbe(
                    settingsRepository: settingsRepository,
                    cookieProvider: AlibabaBrowserCookieProvider()
                ),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            MiMoProvider(
                probe: MiMoUsageProbe(
                    settingsRepository: settingsRepository,
                    cookieProvider: MiMoBrowserCookieProvider()
                ),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            AmpCodeProvider(
                probe: AmpCodeUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            KiroProvider(
                probe: KiroUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            MistralProvider(
                probe: MistralUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            OpenCodeProvider(
                probe: OpenCodeUsageProbe(),
                settingsRepository: settingsRepository
            )
        )
        list.append(
            OmpProvider(
                probe: OmpUsageProbe(),
                settingsRepository: settingsRepository
            )
        )

        // Leave core four as-is; non-core default off only if never configured.
        applyExpandedProviderDefaults(list, settingsRepository: settingsRepository)

        return list
    }

    private static let expandedDefaultsKey = "smartquota.multiProvider.v2.optInDefaults"

    /// Non-core providers default to **disabled only when never configured**.
    /// Explicit user prefs in settings.json are never overwritten.
    private static func applyExpandedProviderDefaults(
        _ providers: [any AIProvider],
        settingsRepository: JSONSettingsRepository
    ) {
        let defaults = UserDefaults.standard
        // One-time log marker only (idempotent body based on explicit keys).
        var changed = 0
        for provider in providers where !coreProviderIDs.contains(provider.id) {
            if settingsRepository.explicitEnabled(forProvider: provider.id) == nil {
                provider.isEnabled = false
                changed += 1
            }
        }
        if !defaults.bool(forKey: expandedDefaultsKey) {
            defaults.set(true, forKey: expandedDefaultsKey)
            AppLog.providers.info(
                "Multi-provider opt-in defaults: disabled \(changed) never-configured non-core providers"
            )
        }
    }
}

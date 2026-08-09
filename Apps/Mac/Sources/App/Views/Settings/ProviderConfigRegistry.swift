import SwiftUI
import Domain
import Infrastructure

/// Maps provider id → settings configuration UI.
/// Keep in sync with `ProviderCatalog.displayOrder` (all catalog ids should resolve).
@MainActor
enum ProviderConfigRegistry {
    @ViewBuilder
    static func configCard(
        for provider: any AIProvider,
        monitor: QuotaMonitor,
        extensionConfig: any ExtensionConfigRepository
    ) -> some View {
        if let ext = provider as? ExtensionProvider, ext.manifest.hasConfig {
            ExtensionConfigCard(provider: ext, configRepository: extensionConfig)
        } else {
            switch provider.id {
            case "codex":
                CodexConfigCard(monitor: monitor)
            case "kimi":
                KimiConfigCard(monitor: monitor)
            case "minimax":
                MiniMaxConfigCard(monitor: monitor)
            case "grok":
                GrokConfigCard(monitor: monitor)
            case "claude":
                ClaudeConfigCard(monitor: monitor)
            case "copilot":
                CopilotConfigCard(monitor: monitor)
            case "zai":
                ZaiConfigCard(monitor: monitor)
            case "bedrock":
                BedrockConfigCard(monitor: monitor)
            case "alibaba":
                AlibabaConfigCard(monitor: monitor)
            case "mimo":
                MiMoConfigCard(monitor: monitor)
            default:
                // gemini, cursor, antigravity, ampcode, kiro, mistral, opencode-go, omp, future
                GenericProbeConfigCard(monitor: monitor, providerId: provider.id)
            }
        }
    }

    /// Provider ids that have a specialized config form (not only GenericProbe).
    static let specializedConfigIDs: Set<String> = [
        "codex", "kimi", "minimax", "grok",
        "claude", "copilot", "zai", "bedrock", "alibaba", "mimo",
    ]
}

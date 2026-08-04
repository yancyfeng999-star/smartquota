import SwiftUI
import Domain
import Infrastructure

/// 额度检测配置：默认收起，点击展开后再配置各会员探测方式。
/// 仅展示「会员开关」已启用的会员。
struct QuotaDetectionConfigSection: View {
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @Environment(\.appSettings) private var settings
    private var l10n: L10n { L10n.shared }

    /// Default collapsed so settings list stays short.
    @State private var isExpanded = false

    /// Enabled providers in catalog display order.
    private var enabledProviders: [any AIProvider] {
        let enabled = monitor.allProviders.filter(\.isEnabled)
        let order = ProviderCatalog.displayOrder
        return enabled.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? Int.max
            let ib = order.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        let _ = l10n.revision
        SettingsExpandableCard(isExpanded: $isExpanded) {
            header
        } content: {
            content
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.55, blue: 0.95),
                                Color(red: 0.35, green: 0.40, blue: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("settings.probe"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var subtitle: String {
        let n = enabledProviders.count
        if n == 0 {
            return l10n.t("settings.probe_empty")
        }
        // When collapsed, emphasize “tap to configure”
        if !isExpanded {
            return l10n.tf("settings.probe_sub", "\(n)")
        }
        return l10n.tf("settings.probe_sub", "\(n)")
    }

    @ViewBuilder
    private var content: some View {
        if enabledProviders.isEmpty {
            Text(l10n.t("settings.probe_empty_body"))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                ForEach(enabledProviders, id: \.id) { provider in
                    ProviderConfigRegistry.configCard(
                        for: provider,
                        monitor: monitor,
                        extensionConfig: settings.extensionConfig
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: enabledProviders.map(\.id))
        }
    }
}

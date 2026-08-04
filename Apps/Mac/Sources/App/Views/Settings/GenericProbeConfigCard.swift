import SwiftUI
import Domain
import Infrastructure

/// Standard probe config for memberships without a specialized settings form.
/// Shows how detection works, status, and a test button.
struct GenericProbeConfigCard: View {
    let monitor: QuotaMonitor
    let providerId: String

    @Environment(\.appTheme) private var theme

    @State private var isExpanded = false
    @State private var isChecking = false
    @State private var statusKind: ConfigStatusBadge.Kind = .neutral
    @State private var statusText = L10n.shared.t("common.not_tested")

    private var guide: ProviderProbeGuide {
        ProviderProbeGuide.guide(for: providerId)
    }

    private var providerName: String {
        monitor.provider(for: providerId)?.name ?? providerId
    }

    var body: some View {
        SettingsExpandableCard(isExpanded: $isExpanded) {
            header
        } content: {
            form
        }
        .task {
            await refreshAvailabilityStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderIconView(providerId: providerId, size: 28, showGlow: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(guide.summary)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L10n.shared.t("common.probe_status"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                ConfigStatusBadge(kind: statusKind, text: statusText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("common.how_to_probe"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.accentPrimary)
                            .frame(width: 16, alignment: .leading)
                        Text(step)
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let hint = guide.credentialHint {
                Text(hint)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await testConnection() }
                } label: {
                    Text(isChecking ? L10n.shared.t("common.checking") : L10n.shared.t("common.test_config"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isChecking)

                if let url = guide.dashboardURL {
                    Link(destination: url) {
                        HStack(spacing: 3) {
                            Text(L10n.shared.t("common.open_site"))
                                .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(theme.accentPrimary)
                    }
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func refreshAvailabilityStatus() async {
        guard let provider = monitor.provider(for: providerId) else {
            statusKind = .failure
            statusText = L10n.shared.t("config.fail_prefix") + L10n.shared.t("menu.unavailable")
            return
        }
        let available = await provider.isAvailable()
        if available {
            statusKind = .success
            statusText = L10n.shared.t("config.probe_available")
        } else {
            statusKind = .warning
            statusText = L10n.shared.t("config.probe_pending")
        }
    }

    @MainActor
    private func testConnection() async {
        isChecking = true
        statusKind = .checking
        statusText = "检测中…"
        await monitor.refresh(providerId: providerId)
        if let error = monitor.provider(for: providerId)?.lastError {
            statusKind = .failure
            statusText = L10n.shared.t("config.fail_prefix") + error.localizedDescription
        } else if monitor.provider(for: providerId)?.snapshot != nil {
            statusKind = .success
            statusText = L10n.shared.t("config.success_ok")
        } else {
            await refreshAvailabilityStatus()
        }
        isChecking = false
    }
}

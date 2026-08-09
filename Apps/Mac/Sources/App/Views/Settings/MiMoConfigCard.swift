import SwiftUI
import Domain
import Infrastructure

/// Xiaomi MiMo Token Plan configuration (console cookie only — no cash balance).
struct MiMoConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    @State private var expanded = false
    @State private var cookieSource: MiMoCookieSource = .auto
    @State private var manualCookie = ""
    @State private var isTesting = false
    @State private var testResult: String?

    private var dashboardURL: URL? {
        URL(string: "https://platform.xiaomimimo.com/console/plan-manage")
    }

    var body: some View {
        SettingsExpandableCard(isExpanded: $expanded) {
            header
        } content: {
            form
        }
        .onAppear {
            cookieSource = settings.mimo.mimoCookieSource()
            manualCookie = settings.mimo.getMimoManualCookie() ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderIconView(providerId: "mimo", size: 28, showGlow: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.mimo.title"))
                    .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Text(L10n.shared.t("config.mimo.sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.mimo.cookie_source"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $cookieSource) {
                    ForEach(MiMoCookieSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: cookieSource) { _, newValue in
                    settings.mimo.setMimoCookieSource(newValue)
                }
            }

            if cookieSource == .manual {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.mimo.cookie"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField(
                        "",
                        text: $manualCookie,
                        prompt: Text(L10n.shared.t("config.mimo.cookie_prompt"))
                            .foregroundStyle(theme.textTertiary)
                    )
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: 1)
                            )
                    )
                    .onChange(of: manualCookie) { _, newValue in
                        if !newValue.isEmpty {
                            settings.mimo.saveMimoManualCookie(newValue)
                        }
                    }

                    Text(L10n.shared.t("config.mimo.cookie_help"))
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            if isTesting {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text(L10n.shared.t("config.testing"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task { await testConnection() }
                } label: {
                    Text(L10n.shared.t("config.save_test"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }

            if let testResult {
                Text(testResult)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(
                        testResult.contains("✓")
                            ? AppTheme.statusHealthy
                            : AppTheme.statusCritical
                    )
            }

            if let dashboardURL {
                Link(destination: dashboardURL) {
                    Text(L10n.shared.t("config.mimo.open"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                }
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        if cookieSource == .manual, !manualCookie.isEmpty {
            settings.mimo.saveMimoManualCookie(manualCookie)
        }

        await monitor.refresh(providerId: "mimo")

        if let error = monitor.provider(for: "mimo")?.lastError {
            testResult = "✗ \(error.localizedDescription)"
            return
        }
        if let snap = monitor.provider(for: "mimo")?.snapshot,
           let q = snap.quotas.first {
            let rem = Int(q.percentRemaining.rounded())
            let plan = snap.accountTier?.badgeText ?? "Token Plan"
            testResult = "✓ \(plan) · 剩余 \(rem)%"
        } else {
            testResult = "✓ OK"
        }
    }
}

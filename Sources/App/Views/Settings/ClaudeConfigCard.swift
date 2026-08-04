import SwiftUI
import Domain
import Infrastructure

/// Claude provider configuration card for SettingsView.
struct ClaudeConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var claudeConfigExpanded: Bool = false
    @State private var claudeBudgetExpanded: Bool = false
    @State private var claudeProbeMode: ClaudeProbeMode = .cli
    @State private var claudeCliFallbackEnabled: Bool = true
    @State private var budgetInput: String = ""

    var body: some View {
        VStack(spacing: 12) {
            configCard
            budgetCard
        }
        .onAppear {
            claudeProbeMode = settings.claude.claudeProbeMode()
            claudeCliFallbackEnabled = settings.claude.claudeCliFallbackEnabled()
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
        }
    }

    // MARK: - Config Card

    private var configCard: some View {
        SettingsExpandableCard(isExpanded: $claudeConfigExpanded) {
            configHeader
        } content: {
            configForm
        }
    }

    private var configHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.claude"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.subtitle.data_source"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.probe_mode"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $claudeProbeMode) {
                    ForEach(ClaudeProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: claudeProbeMode) { _, newValue in
                    settings.claude.setClaudeProbeMode(newValue)
                    // In API mode the app caches usage data for 15 min to stay
                    // under Anthropic's API rate limits, so a faster background
                    // cadence is wasted (calls just return the cache). Snap an
                    // enabled sub-15-min interval up to 15 min (issue #204); leave
                    // "Off" alone so switching mode never turns on sync the user
                    // disabled.
                    if newValue == .api,
                       let seconds = settings.refreshInterval.seconds,
                       seconds < 900 {
                        settings.refreshInterval = .fifteenMinutes
                    }
                    Task {
                        await monitor.refresh(providerId: "claude")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(claudeProbeMode == .cli ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.shared.t("config.cli_mode"))
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(claudeProbeMode == .cli ? theme.textPrimary : theme.textSecondary)

                        Text(L10n.shared.t("config.cli_desc.claude"))
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundStyle(claudeProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.shared.t("config.api_mode"))
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(claudeProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text(L10n.shared.t("config.api_desc.claude"))
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            if claudeProbeMode == .api {
                let credentialLoader = ClaudeCredentialLoader()
                let hasCredentials = credentialLoader.loadCredentials() != nil

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 16)

                    Text(L10n.shared.t("config.claude.cache_note"))
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: hasCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)

                    Text(hasCredentials ? "OAuth credentials found" : "No OAuth credentials found")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)
                }

                if !hasCredentials {
                    Text(L10n.shared.t("config.claude.auth_hint"))
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Toggle(isOn: $claudeCliFallbackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.shared.t("config.claude.cli_fallback"))
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                        Text(L10n.shared.t("config.claude.cli_fallback_desc"))
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .onChange(of: claudeCliFallbackEnabled) { _, newValue in
                    settings.claude.setClaudeCliFallbackEnabled(newValue)
                }
            }
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        SettingsExpandableCard(isExpanded: $claudeBudgetExpanded) {
            budgetHeader
        } content: {
            budgetForm
                .disabled(!settings.claudeApiBudgetEnabled)
                .opacity(settings.claudeApiBudgetEnabled ? 1 : 0.6)
        }
    }

    private var budgetHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.claude.budget"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.claude.budget_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Toggle("", isOn: $settings.claudeApiBudgetEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    private var budgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.claude.budget_label"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: budgetInput) { _, newValue in
                            if let value = Decimal(string: newValue) {
                                settings.claudeApiBudget = value
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.shared.t("config.claude.budget_help"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

import SwiftUI
import Domain
import Infrastructure

/// Grok (xAI) provider configuration card for SettingsView.
struct GrokConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme

    @State private var grokConfigExpanded: Bool = false
    @State private var isChecking = false
    @State private var statusKind: ConfigStatusBadge.Kind = .neutral
    @State private var statusText: String = "未检测"
    @State private var credentialEmail: String?

    var body: some View {
        SettingsExpandableCard(isExpanded: $grokConfigExpanded) {
            grokConfigHeader
        } content: {
            grokConfigForm
        }
        .task {
            await checkStatus()
        }
    }

    private var grokConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.18),
                                Color(red: 0.35, green: 0.35, blue: 0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "line.diagonal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.grok"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.subtitle.xai"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var grokConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProbeHowToBlock(providerId: "grok")

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.credentials"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                ConfigStatusBadge(kind: statusKind, text: statusText)

                if let email = credentialEmail {
                    Text(email)
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("凭证来源")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("读取本机 ~/.grok/auth.json（Grok / xAI CLI 登录后生成）")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    Task { await checkStatus(refresh: true) }
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

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func checkStatus(refresh: Bool = false) async {
        isChecking = true
        statusKind = .checking
        statusText = "检测中…"

        let loader = GrokCredentialLoader()
        if let creds = loader.loadCredentials() {
            credentialEmail = creds.email
            if refresh {
                await monitor.refresh(providerId: "grok")
                if let error = monitor.provider(for: "grok")?.lastError {
                    statusKind = .failure
                    statusText = "失败：\(error.localizedDescription)"
                } else {
                    statusKind = .success
                    statusText = "成功：凭证可用"
                }
            } else {
                statusKind = .success
                statusText = "成功：已找到凭证"
            }
        } else {
            credentialEmail = nil
            statusKind = .failure
            statusText = "失败：未找到 ~/.grok/auth.json"
        }

        isChecking = false
    }
}

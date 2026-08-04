import SwiftUI
import Domain
import Infrastructure

/// Kimi provider configuration card for SettingsView.
struct KimiConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    @State private var kimiConfigExpanded: Bool = false
    @State private var kimiProbeMode: KimiProbeMode = .cli
    @State private var isChecking = false
    @State private var statusKind: ConfigStatusBadge.Kind = .neutral
    @State private var statusText: String = "未检测"

    var body: some View {
        SettingsExpandableCard(isExpanded: $kimiConfigExpanded) {
            kimiConfigHeader
        } content: {
            kimiConfigForm
        }
        .onAppear {
            kimiProbeMode = settings.kimi.kimiProbeMode()
            updateCredentialStatus()
        }
    }

    private var kimiConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accentPrimary.opacity(0.2), theme.accentSecondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.kimi"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.chatgpt_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var kimiConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProbeHowToBlock(providerId: "kimi")

            HStack(spacing: 8) {
                Text(L10n.shared.t("config.current"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)
                ConfigStatusBadge(kind: statusKind, text: statusText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.probe_mode"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $kimiProbeMode) {
                    ForEach(KimiProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: kimiProbeMode) { _, newValue in
                    settings.kimi.setKimiProbeMode(newValue)
                    updateCredentialStatus()
                    Task {
                        await monitor.refresh(providerId: "kimi")
                        await applyRefreshResult()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                modeRow(
                    icon: "terminal",
                    title: "CLI 模式",
                    detail: "使用 kimi 命令行 /usage（需已安装 kimi）",
                    selected: kimiProbeMode == .cli
                )
                modeRow(
                    icon: "network",
                    title: "API 模式",
                    detail: "直接请求 Kimi 接口（本机 sk-kimi 或 Cookie）",
                    selected: kimiProbeMode == .api
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeRow(icon: String, title: String, detail: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(selected ? theme.accentPrimary : theme.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)

                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateCredentialStatus() {
        if kimiProbeMode == .api {
            do {
                let cred = try KimiCookieTokenProvider().resolveCredential()
                statusKind = .success
                statusText = cred.kind == .codingAPIKey ? "成功：已找到 Coding API Key" : "成功：已找到会话凭证"
            } catch {
                statusKind = .failure
                statusText = "失败：未找到 sk-kimi 或 Cookie"
            }
        } else {
            statusKind = .neutral
            statusText = "CLI：需本机 kimi 命令"
        }
    }

    @MainActor
    private func testConnection() async {
        isChecking = true
        statusKind = .checking
        statusText = "检测中…"
        updateCredentialStatus()
        if statusKind == .failure {
            isChecking = false
            return
        }
        await monitor.refresh(providerId: "kimi")
        await applyRefreshResult()
        isChecking = false
    }

    @MainActor
    private func applyRefreshResult() async {
        if let error = monitor.provider(for: "kimi")?.lastError {
            statusKind = .failure
            statusText = "失败：\(error.localizedDescription)"
        } else if monitor.provider(for: "kimi")?.snapshot != nil {
            statusKind = .success
            statusText = "成功：连接正常"
        } else {
            updateCredentialStatus()
        }
    }
}

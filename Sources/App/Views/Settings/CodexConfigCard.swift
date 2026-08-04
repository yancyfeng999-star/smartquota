import SwiftUI
import Domain
import Infrastructure

/// Codex / ChatGPT provider configuration card for SettingsView.
struct CodexConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    @State private var codexConfigExpanded: Bool = false
    @State private var codexProbeMode: CodexProbeMode = .rpc
    @State private var isChecking = false
    @State private var statusKind: ConfigStatusBadge.Kind = .neutral
    @State private var statusText: String = "未检测"

    var body: some View {
        SettingsExpandableCard(isExpanded: $codexConfigExpanded) {
            codexConfigHeader
        } content: {
            codexConfigForm
        }
        .onAppear {
            codexProbeMode = settings.codex.codexProbeMode()
            updateCredentialStatus()
        }
    }

    private var codexConfigHeader: some View {
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
                Text(L10n.shared.t("config.chatgpt"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.chatgpt_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var codexConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProbeHowToBlock(providerId: "codex")

            // Status for selected config
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

                Picker("", selection: $codexProbeMode) {
                    ForEach(CodexProbeMode.allCases, id: \.self) { mode in
                        Text(mode == .api ? "API" : "RPC").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: codexProbeMode) { _, newValue in
                    settings.codex.setCodexProbeMode(newValue)
                    updateCredentialStatus()
                    Task {
                        await monitor.refresh(providerId: "codex")
                        await applyRefreshResult()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                modeRow(
                    icon: "terminal",
                    title: "RPC 模式",
                    detail: "通过 codex app-server 获取额度（本机 CLI）",
                    selected: codexProbeMode == .rpc
                )
                modeRow(
                    icon: "network",
                    title: "API 模式",
                    detail: "直接请求 ChatGPT 接口（推荐，读 ~/.codex/auth.json）",
                    selected: codexProbeMode == .api
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
        if codexProbeMode == .api {
            let hasCredentials = CodexCredentialLoader().loadCredentials() != nil
            if hasCredentials {
                statusKind = .success
                statusText = "成功：已找到 OAuth 凭证"
            } else {
                statusKind = .failure
                statusText = "失败：未找到 ~/.codex/auth.json"
            }
        } else {
            statusKind = .neutral
            statusText = "RPC：需本机 codex CLI"
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
        await monitor.refresh(providerId: "codex")
        await applyRefreshResult()
        isChecking = false
    }

    @MainActor
    private func applyRefreshResult() async {
        if let error = monitor.provider(for: "codex")?.lastError {
            statusKind = .failure
            statusText = "失败：\(error.localizedDescription)"
        } else if monitor.provider(for: "codex")?.snapshot != nil {
            statusKind = .success
            statusText = "成功：连接正常"
        } else {
            updateCredentialStatus()
        }
    }
}

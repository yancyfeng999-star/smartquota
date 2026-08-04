import SwiftUI
import Domain
import Infrastructure

/// MiniMax provider configuration card for SettingsView.
struct MiniMaxConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var miniMaxConfigExpanded: Bool = false
    @State private var miniMaxApiKeyInput: String = ""
    @State private var miniMaxAuthEnvVarInput: String = ""
    @State private var miniMaxRegion: MiniMaxRegion = .china
    @State private var showMiniMaxApiKey: Bool = false
    @State private var isTestingMiniMax = false
    @State private var miniMaxTestResult: String?

    var body: some View {
        SettingsExpandableCard(isExpanded: $miniMaxConfigExpanded) {
            miniMaxConfigHeader
        } content: {
            miniMaxConfigForm
        }
        .onAppear {
            miniMaxRegion = settings.minimax.minimaxRegion()
            miniMaxAuthEnvVarInput = settings.minimax.minimaxAuthEnvVar()
        }
    }

    private var miniMaxConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.91, green: 0.27, blue: 0.42),
                                Color(red: 0.96, green: 0.53, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.minimax"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.subtitle.coding_plan"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

        }
    }

    private var miniMaxConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProbeHowToBlock(providerId: "minimax")

            // Region selector (short labels so popover width stays 380)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.region"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $miniMaxRegion) {
                    ForEach(MiniMaxRegion.allCases, id: \.self) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: miniMaxRegion) { _, newValue in
                    settings.minimax.setMinimaxRegion(newValue)
                    Task {
                        await monitor.refresh(providerId: "minimax")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // API Key input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.shared.t("config.api_key"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer()

                    if settings.minimax.hasMinimaxApiKey() {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text(L10n.shared.t("config.configured"))
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.statusHealthy)
                    }
                }

                HStack(spacing: 6) {
                    Group {
                        if showMiniMaxApiKey {
                            TextField("", text: $miniMaxApiKeyInput, prompt: Text("sk-…").foregroundStyle(theme.textTertiary))
                        } else {
                            SecureField("", text: $miniMaxApiKeyInput, prompt: Text("sk-…").foregroundStyle(theme.textTertiary))
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 0, maxWidth: .infinity)
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

                    Button {
                        showMiniMaxApiKey.toggle()
                    } label: {
                        Image(systemName: showMiniMaxApiKey ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(theme.glassBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Environment Variable
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.shared.t("config.env_alt"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $miniMaxAuthEnvVarInput, prompt: Text("MINIMAX_API_KEY").foregroundStyle(theme.textTertiary))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 0, maxWidth: .infinity)
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
                    .onChange(of: miniMaxAuthEnvVarInput) { _, newValue in
                        settings.minimax.setMinimaxAuthEnvVar(newValue)
                    }
            }

            // Token lookup order
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.shared.t("config.key_order"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("1. 环境变量（默认 MINIMAX_API_KEY）")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("2. 上方填写的 API 密钥")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("3. 本机 ~/.minimax/config.yaml")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Save & Test button
            if isTestingMiniMax {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(L10n.shared.t("config.testing"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testMiniMaxConnection()
                    }
                } label: {
                    Text(L10n.shared.t("config.save_test"))
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
            }

            if let result = miniMaxTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(result.contains("成功") || result.localizedCaseInsensitiveContains("success") ? theme.statusHealthy : theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Help link
            VStack(alignment: .leading, spacing: 4) {
                Text("从 MiniMax 平台获取 API 密钥")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Link(destination: miniMaxRegion.apiKeysURL) {
                    HStack(spacing: 3) {
                        Text("打开 MiniMax API 密钥页")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }

            // Delete API key
            if settings.minimax.hasMinimaxApiKey() {
                Button {
                    settings.minimax.deleteMinimaxApiKey()
                    miniMaxApiKeyInput = ""
                    miniMaxTestResult = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text(L10n.shared.t("config.remove_key"))
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusCritical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func testMiniMaxConnection() async {
        isTestingMiniMax = true
        miniMaxTestResult = nil

        settings.minimax.setMinimaxAuthEnvVar(miniMaxAuthEnvVarInput)
        if !miniMaxApiKeyInput.isEmpty {
            AppLog.credentials.info("Saving MiniMax API key for connection test")
            settings.minimax.saveMinimaxApiKey(miniMaxApiKeyInput)
            miniMaxApiKeyInput = ""
        }

        AppLog.credentials.info("Testing MiniMax connection via provider refresh")
        await monitor.refresh(providerId: "minimax")

        if let error = monitor.provider(for: "minimax")?.lastError {
            AppLog.credentials.error("MiniMax connection test failed: \(error.localizedDescription)")
            miniMaxTestResult = "Failed: \(error.localizedDescription)"
        } else {
            AppLog.credentials.info("MiniMax connection test succeeded")
            miniMaxTestResult = "Success: Connection verified"
        }

        isTestingMiniMax = false
    }
}

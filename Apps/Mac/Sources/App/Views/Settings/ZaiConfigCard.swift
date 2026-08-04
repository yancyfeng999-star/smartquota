import SwiftUI
import Domain
import Infrastructure

/// Z.ai / GLM provider configuration card for SettingsView.
struct ZaiConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    @State private var zaiConfigExpanded: Bool = false
    @State private var zaiConfigPathInput: String = ""
    @State private var glmAuthEnvVarInput: String = ""

    var body: some View {
        SettingsExpandableCard(isExpanded: $zaiConfigExpanded) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.9),
                                    Color(red: 0.15, green: 0.45, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shared.t("config.zai.title"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(L10n.shared.t("config.subtitle.auth_fallback"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                // Explanation text
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.zai.lookup"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Text(L10n.shared.t("config.zai.lookup1"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    Text(L10n.shared.t("config.zai.lookup2"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.zai.path"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $zaiConfigPathInput, prompt: Text("~/.claude/settings.json").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: zaiConfigPathInput) { _, newValue in
                            settings.zai.setZaiConfigPath(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.zai.env"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $glmAuthEnvVarInput, prompt: Text("GLM_AUTH_TOKEN").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: glmAuthEnvVarInput) { _, newValue in
                            settings.zai.setGlmAuthEnvVar(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.shared.t("config.zai.empty_hint"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .onAppear {
            zaiConfigPathInput = settings.zai.zaiConfigPath()
            glmAuthEnvVarInput = settings.zai.glmAuthEnvVar()
        }
    }
}

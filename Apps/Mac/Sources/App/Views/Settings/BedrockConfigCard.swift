import SwiftUI
import Domain
import Infrastructure

/// AWS Bedrock provider configuration card for SettingsView.
struct BedrockConfigCard: View {
    let monitor: QuotaMonitor

    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    @State private var bedrockConfigExpanded: Bool = false
    @State private var awsProfileNameInput: String = ""
    @State private var bedrockRegionsInput: String = ""
    @State private var bedrockDailyBudgetInput: String = ""

    var body: some View {
        SettingsExpandableCard(isExpanded: $bedrockConfigExpanded) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                    Color(red: 0.9, green: 0.45, blue: 0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.shared.t("config.bedrock.title"))
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(L10n.shared.t("config.subtitle.cloudwatch"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                // AWS Profile Name
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.bedrock.profile"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $awsProfileNameInput, prompt: Text("default").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: awsProfileNameInput) { _, newValue in
                            settings.bedrock.setAWSProfileName(newValue)
                        }
                }

                // Regions
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.bedrock.regions"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $bedrockRegionsInput, prompt: Text("us-east-1, us-west-2").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: bedrockRegionsInput) { _, newValue in
                            let regions = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            settings.bedrock.setBedrockRegions(regions)
                        }
                }

                // Daily Budget
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.shared.t("config.bedrock.budget"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)

                        TextField("", text: $bedrockDailyBudgetInput, prompt: Text("50.00").foregroundStyle(theme.textTertiary))
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
                            .onChange(of: bedrockDailyBudgetInput) { _, newValue in
                                if newValue.isEmpty {
                                    settings.bedrock.setBedrockDailyBudget(nil)
                                } else if let value = Decimal(string: newValue) {
                                    settings.bedrock.setBedrockDailyBudget(value)
                                }
                            }
                    }
                }

                // Help text
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.shared.t("config.bedrock.cred_help"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)

                    Text(L10n.shared.t("config.bedrock.configure_help"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                // Link to AWS console
                Link(destination: URL(string: "https://console.aws.amazon.com/bedrock/home") ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 3) {
                        Text(L10n.shared.t("config.bedrock.open_console"))
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }
        }
        .onAppear {
            awsProfileNameInput = settings.bedrock.awsProfileName()
            bedrockRegionsInput = settings.bedrock.bedrockRegions().joined(separator: ", ")
            if let budget = settings.bedrock.bedrockDailyBudget() {
                bedrockDailyBudgetInput = String(describing: budget)
            }
        }
    }
}

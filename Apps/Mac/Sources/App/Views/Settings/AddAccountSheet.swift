import SwiftUI
import Domain

/// Sheet for adding a new account to a multi-account provider.
///
/// Shows provider-specific instructions explaining how to sign in
/// with a new account. The actual account creation happens automatically
/// when the user refreshes after signing in to the provider's service.
struct AddAccountSheet: View {
    let provider: any MultiAccountProvider
    let monitor: QuotaMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private var l10n: L10n { L10n.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("account.add_sheet_title"))
                        .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(provider.name)
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            Divider()
                .background(theme.glassBorder)

            // Instructions
            VStack(alignment: .leading, spacing: 10) {
                instructionRow(
                    icon: "1.circle.fill",
                    text: l10n.t("account.add_sheet_body")
                )

                instructionRow(
                    icon: "2.circle.fill",
                    text: l10n.t("account.refresh_to_discover")
                )

                // Provider-specific probe guide
                ProbeHowToBlock(providerId: provider.id)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text(l10n.t("common.done"))
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360, height: 420)
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import SwiftUI
import Domain

/// Banner shown in the menu when a multi-account provider has discovered
/// a new account that is pending user confirmation.
///
/// Displays the account email/label and offers two actions:
/// - "Add as new account" (confirm)
/// - "Don't add for now" (ignore/dismiss)
struct PendingAccountBanner: View {
    let providerId: String
    let pendingAccounts: [ProviderAccountState]
    let onConfirm: (String) -> Void
    let onIgnore: (String) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        if pendingAccounts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pendingAccounts) { account in
                    pendingRow(account)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MembershipPalette.accentPrimary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(MembershipPalette.accentPrimary.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }

    private func pendingRow(_ account: ProviderAccountState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MembershipPalette.accentPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.shared.t("account.pending_title"))
                        .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(L10n.shared.tf("account.pending_body_fmt", account.displayName))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Button {
                    onConfirm(account.id)
                } label: {
                    Text(L10n.shared.t("account.add_new"))
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MembershipPalette.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.shared.t("account.add_new"))

                Button {
                    onIgnore(account.id)
                } label: {
                    Text(L10n.shared.t("account.skip"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.shared.t("account.skip"))

                Spacer()
            }
        }
    }
}

import SwiftUI
import Domain

/// First-run privacy screen: local-only, no cloud account, no uploaded keys or usage.
struct PrivacyBoundaryView: View {
    @Environment(\.appTheme) private var theme
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("onboard.privacy.title"))
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Text(l10n.t("onboard.privacy.intro"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            bullet("lock.laptopcomputer", l10n.t("onboard.privacy.local"))
            bullet("cloud.slash", l10n.t("onboard.privacy.no_cloud"))
            bullet("key.slash", l10n.t("onboard.privacy.no_keys"))
            bullet("chart.bar.doc.horizontal", l10n.t("onboard.privacy.no_usage"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingHelpSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("onboard.help.title"))
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("onboard.help.body"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(l10n.t("onboard.help.cli"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(l10n.t("onboard.help.key"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(l10n.t("onboard.help.permission"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button(l10n.t("common.done")) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.accentPrimary)
        }
        .padding(20)
        .frame(minWidth: 360, alignment: .leading)
    }
}

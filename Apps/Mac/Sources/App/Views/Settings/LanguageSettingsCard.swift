import SwiftUI

/// Language card — same expand motion as every other settings card (`SettingsExpandableCard` + `AppMotion`).
struct LanguageSettingsCard: View {
    @Environment(\.appSettings) private var settings
    @Environment(\.appTheme) private var theme

    private var l10n: L10n { L10n.shared }

    @State private var isExpanded = false

    private var selected: AppLanguage {
        AppLanguage.resolve(settings.appLanguage)
    }

    var body: some View {
        let _ = l10n.revision

        SettingsExpandableCard(isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.55, blue: 0.95),
                                    Color(red: 0.55, green: 0.35, blue: 0.90)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("settings.language"))
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(l10n.t("settings.language_sub"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        } trailing: {
            // Current language — left of the shared chevron
            Text(selected.nativeName)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.glassBackground)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                )
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, lang in
                        languageChip(lang, index: index)
                    }
                }

                Text(l10n.t("settings.language_hint"))
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func languageChip(_ lang: AppLanguage, index: Int) -> some View {
        let isOn = selected == lang
        return Button {
            AppMotion.withSelection {
                settings.appLanguage = lang.rawValue
            }
            // Collapse with the same expand curve after a short beat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                AppMotion.withExpand {
                    isExpanded = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(lang.shortName)
                    .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(isOn ? theme.accentPrimary : theme.textTertiary)
                    .frame(width: 28, alignment: .leading)

                Text(lang.nativeName)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? theme.accentPrimary.opacity(0.12) : theme.glassBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isOn ? theme.accentPrimary : theme.glassBorder,
                                lineWidth: isOn ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .transition(AppMotion.chipIn)
        .animation(AppMotion.expand.delay(Double(index) * 0.022), value: isExpanded)
    }
}

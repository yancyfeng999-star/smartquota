import SwiftUI
import AppKit
import Domain
import Infrastructure

struct HelpSettingsCard: View {
    let monitor: QuotaMonitor
    var store: JSONSettingsStore = .shared

    @Environment(\.appTheme) private var theme
    @State private var showingCenter = false
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            .decorativeGlyph()

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.help"))
                    .font(AppTypeScale.headline(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                Text(l10n.t("settings.help_sub"))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .untruncatedSupportText()
            }
            Spacer(minLength: 8)
            Button(l10n.t("common.open")) {
                showingCenter = true
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.accentGradient))
            .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsOpenHelp)
            .keyboardShortcut("?", modifiers: [.command])
            .help(l10n.t("a11y.help.hint"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingCenter) {
            HelpCenterView(monitor: monitor, store: store)
        }
    }
}

struct HelpCenterView: View {
    let monitor: QuotaMonitor
    var store: JSONSettingsStore = .shared
    var onOpenDiagnostics: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDiagnostics = false
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            header
            actions
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.t("help.section.topics"))
                        .font(AppTypeScale.headline(theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .untruncatedSupportText()
                    ForEach(HelpCenterCatalog.topics) { topic in
                        topicCard(topic)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 520)
        .environment(\.layoutDirection, l10n.language.layoutDirection)
        .environment(\.locale, l10n.language.locale)
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsCenterView(monitor: monitor, store: store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.t("help.title"))
                    .font(AppTypeScale.title(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                Spacer()
                Button(l10n.t("common.done")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(AppTypeScale.callout(theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
                    .supportKeyboardIdentifier(AccessibilityChrome.ID.helpBack)
            }
            Text(l10n.t("help.subtitle"))
                .font(AppTypeScale.body(theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .untruncatedSupportText()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("help.section.actions"))
                .font(AppTypeScale.headline(theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .untruncatedSupportText()
            ForEach(HelpCenterCatalog.destinations, id: \.self) { destination in
                Button {
                    perform(destination)
                } label: {
                    Text(l10n.t(destination.titleKey))
                        .font(AppTypeScale.callout(theme.fontDesign))
                        .foregroundStyle(theme.accentPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .supportKeyboardIdentifier(destination.accessibilityIdentifier)
            }
        }
    }

    private func topicCard(_ topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t(topic.titleKey))
                .font(AppTypeScale.headline(theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .untruncatedSupportText()
            Text(l10n.t(topic.bodyKey))
                .font(AppTypeScale.body(theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .untruncatedSupportText()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
        .animation(reduceMotion ? nil : AppMotion.appear, value: topic.id)
    }

    private func perform(_ destination: HelpDestination) {
        switch destination {
        case .logs:
            FileLogger.shared.openCurrentLogFile()
        case .diagnostics:
            if let onOpenDiagnostics {
                onOpenDiagnostics()
            } else {
                showingDiagnostics = true
            }
        case .githubReleases:
            NSWorkspace.shared.open(HelpCenterCatalog.githubReleasesURL)
        case .userGuide:
            if let url = HelpCenterCatalog.userGuideURL() {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(HelpCenterCatalog.githubReleasesURL)
            }
        }
    }
}

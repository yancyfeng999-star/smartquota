import SwiftUI
import AppKit
import Domain
import Infrastructure

struct DiagnosticsSettingsCard: View {
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
                Image(systemName: "stethoscope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            .decorativeGlyph()
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.diagnostics"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Text(l10n.t("settings.diagnostics_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(l10n.t("diag.open")) {
                showingCenter = true
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.accentGradient))
            .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsOpenDiagnostics)
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
            DiagnosticsCenterView(monitor: monitor, store: store)
        }
    }
}

struct DiagnosticsCenterView: View {
    let monitor: QuotaMonitor
    var store: JSONSettingsStore = .shared

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false
    @State private var copied = false
    @State private var helpProviderId: String?
    @State private var configProviderId: String?
    @State private var showingSystemHelp = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            header
            actionBar
            if results.isEmpty && !isRunning {
                Text(l10n.t("diag.empty"))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { item in
                            resultRow(item)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 520)
        .task { await runAll() }
        .sheet(isPresented: $showingSystemHelp) {
            HelpCenterView(monitor: monitor, store: store) {
                showingSystemHelp = false
            }
        }
        .sheet(item: helpGuide) { guide in
            DiagnosticGuideSheet(guide: guide, titleKey: "diag.action.open_help")
        }
        .sheet(item: configGuide) { guide in
            DiagnosticGuideSheet(guide: guide, titleKey: "diag.action.open_config")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.t("diag.title"))
                    .font(AppTypeScale.title(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                Spacer()
                Button(l10n.t("common.done")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(l10n.t("diag.subtitle"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await runAll() }
            } label: {
                Text(isRunning ? l10n.t("diag.running") : l10n.t("diag.run"))
                    .untruncatedSupportText()
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.diagRun)

            Button {
                copySummary()
            } label: {
                Text(copied ? l10n.t("diag.copied") : l10n.t("diag.copy_summary"))
                    .untruncatedSupportText()
            }
            .buttonStyle(.plain)
            .disabled(results.isEmpty)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.diagCopy)

            Spacer()
        }
        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
        .foregroundStyle(theme.accentPrimary)
    }

    private func resultRow(_ item: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(localizedTitle(item))
                            .font(AppTypeScale.body(theme.fontDesign, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .untruncatedSupportText()
                        SemanticStatusLabel(
                            kind: SemanticStatusKind.from(severity: item.severity),
                            theme: theme,
                            highContrast: colorSchemeContrast == .increased
                        )
                    }
                    Text(localizedDetail(item))
                        .font(AppTypeScale.caption(theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .untruncatedSupportText()
                    if !item.code.isEmpty {
                        Text(item.code)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .untruncatedSupportText()
                    }
                }
            } icon: {
                Image(systemName: icon(for: item.severity))
                    .foregroundStyle(color(for: item.severity))
                    .accessibilityHidden(true)
            }

            if !item.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.actions, id: \.rawValue) { action in
                        Button(l10n.t(action.l10nKey)) {
                            perform(action, for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.accentPrimary)
            }
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
    }

    private func localizedTitle(_ item: DiagnosticResult) -> String {
        let title = item.title.hasPrefix("diag.") ? l10n.t(item.title) : item.title
        if let providerId = item.providerId {
            return "\(title) · \(providerId)"
        }
        return title
    }

    private func localizedDetail(_ item: DiagnosticResult) -> String {
        let parts = item.detail.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return item.detail }
        let key = String(first)
        if key.hasPrefix("diag.") {
            let localized = l10n.t(key)
            if parts.count == 2 {
                return localized + " " + String(parts[1])
            }
            return localized
        }
        return item.detail
    }

    private func icon(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func color(for severity: DiagnosticSeverity) -> Color {
        SemanticStatusStyle.color(
            SemanticStatusKind.from(severity: severity),
            theme: theme,
            highContrast: colorSchemeContrast == .increased
        )
    }

    private func perform(_ action: DiagnosticAction, for item: DiagnosticResult) {
        switch action {
        case .none:
            break
        case .openConfiguration:
            if let providerId = item.providerId {
                configProviderId = providerId
            }
        case .openHelp:
            if let providerId = item.providerId {
                helpProviderId = providerId
            } else {
                showingSystemHelp = true
            }
        case .openDashboard:
            if let providerId = item.providerId {
                ProviderProbeGuide.guide(for: providerId).openDashboard()
            }
        case .retry:
            Task { await retry(item) }
        case .openLogs:
            FileLogger.shared.openCurrentLogFile()
        case .openSystemSettings:
            openSystemSettings(for: item.kind)
        }
    }

    private func openSystemSettings(for kind: DiagnosticCheckKind) {
        let pane: String
        switch kind {
        case .notificationPermission:
            pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        default:
            pane = "x-apple.systempreferences:com.apple.preference.security?Privacy"
        }
        guard let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copySummary() {
        let service = DiagnosticsService.live(monitor: monitor, store: store)
        let text = service.summary(for: results).text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func runAll() async {
        isRunning = true
        defer { isRunning = false }
        copied = false
        let service = DiagnosticsService.live(monitor: monitor, store: store)
        results = await service.runAll()
    }

    private func retry(_ item: DiagnosticResult) async {
        let service = DiagnosticsService.live(monitor: monitor, store: store)
        let next = await service.retry(item)
        if let index = results.firstIndex(where: { $0.id == item.id }) {
            results[index] = next
        }
    }

    private var helpGuide: Binding<ProviderProbeGuide?> {
        Binding(
            get: { helpProviderId.map { ProviderProbeGuide.guide(for: $0) } },
            set: { helpProviderId = $0?.id }
        )
    }

    private var configGuide: Binding<ProviderProbeGuide?> {
        Binding(
            get: { configProviderId.map { ProviderProbeGuide.guide(for: $0) } },
            set: { configProviderId = $0?.id }
        )
    }
}

private struct DiagnosticGuideSheet: View {
    let guide: ProviderProbeGuide
    let titleKey: String

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t(titleKey))
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(guide.title)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(guide.summary)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint = guide.credentialHint {
                Text(hint)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if guide.dashboardURL != nil {
                    Button(l10n.t("diag.action.open_dashboard")) {
                        guide.openDashboard()
                    }
                    .buttonStyle(.plain)
                }
                Button(l10n.t("common.done")) { dismiss() }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(theme.accentPrimary)
        }
        .padding(20)
        .frame(minWidth: 360, alignment: .leading)
    }
}

private extension DiagnosticAction {
    var l10nKey: String {
        switch self {
        case .none: "common.done"
        case .openConfiguration: "diag.action.open_config"
        case .openHelp: "diag.action.open_help"
        case .openDashboard: "diag.action.open_dashboard"
        case .retry: "diag.action.retry"
        case .openLogs: "diag.action.open_logs"
        case .openSystemSettings: "diag.action.open_settings"
        }
    }
}

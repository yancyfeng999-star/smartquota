import SwiftUI
import AppKit
import Domain

enum AppTypeScale {
    static func title(_ design: Font.Design) -> Font {
        .system(.title3, design: design).weight(.bold)
    }

    static func headline(_ design: Font.Design) -> Font {
        .system(.headline, design: design)
    }

    static func body(_ design: Font.Design, weight: Font.Weight = .medium) -> Font {
        .system(.subheadline, design: design).weight(weight)
    }

    static func callout(_ design: Font.Design, weight: Font.Weight = .semibold) -> Font {
        .system(.callout, design: design).weight(weight)
    }

    static func caption(_ design: Font.Design) -> Font {
        .system(.caption, design: design)
    }
}

enum SemanticStatusKind: String, Sendable {
    case success
    case warning
    case failure
    case info

    var labelKey: String {
        switch self {
        case .success: "common.success"
        case .warning: "status.warning"
        case .failure: "common.failure"
        case .info: "status.info"
        }
    }

    static func from(severity: DiagnosticSeverity) -> SemanticStatusKind {
        switch severity {
        case .ok: .success
        case .info: .info
        case .warning: .warning
        case .error: .failure
        }
    }
}

enum SemanticStatusStyle {
    static func color(
        _ kind: SemanticStatusKind,
        theme: any AppThemeProvider,
        highContrast: Bool
    ) -> Color {
        if highContrast {
            switch kind {
            case .success: return Color.green
            case .warning: return Color.orange
            case .failure: return Color.red
            case .info: return Color.blue
            }
        }
        switch kind {
        case .success: return theme.statusHealthy
        case .warning: return theme.statusWarning
        case .failure: return theme.statusCritical
        case .info: return theme.accentPrimary
        }
    }

    static func quotaColor(
        _ status: QuotaStatus,
        theme: any AppThemeProvider,
        highContrast: Bool
    ) -> Color {
        if highContrast {
            switch status {
            case .healthy: return Color.green
            case .warning: return Color.orange
            case .critical, .depleted: return Color.red
            }
        }
        return theme.statusColor(for: status)
    }
}

struct SemanticStatusLabel: View {
    let kind: SemanticStatusKind
    var theme: any AppThemeProvider
    var highContrast: Bool

    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        Text(l10n.t(kind.labelKey))
            .font(AppTypeScale.caption(theme.fontDesign).weight(.bold))
            .foregroundStyle(SemanticStatusStyle.color(kind, theme: theme, highContrast: highContrast))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(l10n.t(kind.labelKey))
    }
}

struct UnifiedErrorBlock: View {
    let kind: SupportErrorKind
    var theme: any AppThemeProvider

    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        let copy = SupportErrorCatalog.copy(for: kind, language: l10n.supportLanguage)
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.whatHappened)
                .font(AppTypeScale.body(theme.fontDesign, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(copy.dataRetention)
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            Text(copy.nextStep)
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension L10n {
    var supportLanguage: SupportLanguage {
        language == .zhHans ? .zhHans : .en
    }
}

extension View {
    func supportIconAccessibility(id: String, valueKey: String) -> some View {
        modifier(SupportIconAccessibilityModifier(id: id, valueKey: valueKey))
    }

    func supportKeyboardIdentifier(_ id: String) -> some View {
        accessibilityIdentifier(id)
    }

    func untruncatedSupportText() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }

    func decorativeGlyph() -> some View {
        accessibilityHidden(true)
            .accessibilityIdentifier(AccessibilityChrome.ID.decorativeCardIcon)
    }
}

private struct SupportIconAccessibilityModifier: ViewModifier {
    let id: String
    let valueKey: String
    private var l10n: L10n { L10n.shared }

    func body(content: Content) -> some View {
        let _ = l10n.revision
        let spec = AccessibilityChrome.spec(id: id)
        content
            .accessibilityLabel(l10n.t(spec?.labelKey ?? id))
            .accessibilityHint(l10n.t(spec?.hintKey ?? id))
            .accessibilityValue(l10n.t(valueKey))
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(.isButton)
            .focusable()
    }
}

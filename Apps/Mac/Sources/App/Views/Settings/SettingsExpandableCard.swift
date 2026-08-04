import SwiftUI

/// Expandable settings card — **one** expand motion for the whole app.
/// Content always unfolds from **below the header** (card bottom when collapsed),
/// starting soft-blurred then clearing (see `AppMotion.expandContent`).
struct SettingsExpandableCard<Header: View, Trailing: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isExpanded = isExpanded
        self.header = header
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header — content expands only under this row
            Button {
                AppMotion.toggleExpand($isExpanded)
            } label: {
                HStack(spacing: 10) {
                    header()
                    Spacer(minLength: 8)
                    trailing()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(AppMotion.chevron, value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .zIndex(1)

            // Unfolds from the header bottom edge only
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .background(theme.glassBorder)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // Anchor expansion to top of this block (= bottom of header)
                .transition(AppMotion.expandContent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
        // Clip so growing content never paints above the header
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
        .animation(AppMotion.expand, value: isExpanded)
    }
}

extension SettingsExpandableCard where Trailing == EmptyView {
    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(isExpanded: isExpanded, header: header, trailing: { EmptyView() }, content: content)
    }
}

/// Left-aligned numbered steps: how a membership probes quota.
struct ProbeHowToBlock: View {
    let providerId: String
    @Environment(\.appTheme) private var theme

    private var guide: ProviderProbeGuide {
        ProviderProbeGuide.guide(for: providerId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.shared.t("common.how_to_probe"))
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.accentPrimary)
                        .frame(width: 16, alignment: .leading)
                    Text(step)
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let hint = guide.credentialHint {
                Text(hint)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact success / failure pill for config probe status.
struct ConfigStatusBadge: View {
    enum Kind {
        case success
        case failure
        case warning
        case neutral
        case checking
    }

    let kind: Kind
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if kind == .checking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(foreground.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(foreground.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var iconName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .neutral: return "circle"
        case .checking: return "circle"
        }
    }

    private var foreground: Color {
        switch kind {
        case .success: return theme.statusHealthy
        case .failure: return theme.statusCritical
        case .warning: return theme.statusWarning
        case .neutral, .checking: return theme.textSecondary
        }
    }
}

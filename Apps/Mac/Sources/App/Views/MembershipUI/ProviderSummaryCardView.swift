import SwiftUI
import Domain

/// Membership card: compact quota rows (label left / % right above bar).
struct ProviderSummaryCardView: View {
    let provider: any AIProvider
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appSettings) private var settings
    private var l10n: L10n { L10n.shared }
    @State private var isHovering = false

    var body: some View {
        let _ = l10n.revision
        // Not a Button — so long-press + drag reorder gestures can win.
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            metricsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .shadow(
            color: MembershipPalette.accentPrimary.opacity(isHovering ? 0.18 : 0),
            radius: isHovering ? 10 : 0,
            y: isHovering ? 3 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppMotion.hover) {
                isHovering = hovering
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected
                    ? MembershipPalette.selectionFill(colorScheme)
                    : (isHovering
                        ? MembershipPalette.cardFill(colorScheme, elevated: true)
                        : MembershipPalette.cardFill(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? MembershipPalette.selectionStroke(colorScheme)
                            : (isHovering
                                ? MembershipPalette.accentPrimary.opacity(0.45)
                                : MembershipPalette.cardStroke(colorScheme)),
                        lineWidth: isHovering || isSelected ? 1.2 : 0.9
                    )
            )
    }

    // MARK: - Header

    private var planLabel: String {
        _ = settings.planLabelsRevision
        return MembershipPlanStore.displayPlan(for: provider)
    }

    private var renewalLabel: String? {
        _ = settings.planLabelsRevision
        return MembershipPlanStore.displayRenewal(for: provider.id)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 24, showGlow: false)

            // Name · plan · renewal (wrap if needed)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(planLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MembershipPalette.accentPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MembershipPalette.accentPrimary.opacity(0.12))
                        )
                        .lineLimit(1)
                }

                if let renewalLabel {
                    Text(renewalLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            statusPill
        }
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(statusTint.opacity(0.16))
            )
            .foregroundStyle(statusTint)
    }

    // MARK: - Metrics (compact)

    private var metricsRow: some View {
        let items = displayColumns
        if items.isEmpty {
            return AnyView(
                Text(provider.isSyncing ? l10n.t("common.refreshing") : l10n.t("common.no_quota"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }
        return AnyView(
            HStack(spacing: 10) {
                ForEach(items) { item in
                    quotaColumn(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    /// Progress bar with label left + percent right above the bar.
    private func quotaColumn(_ item: SummaryQuotaItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let value = item.percentRemaining {
                    Text("\(Int(value.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(MembershipPalette.surfaceTrack)
                    if let value = item.percentRemaining {
                        Capsule(style: .continuous)
                            .fill(MembershipPalette.progressColor(percentRemaining: value).opacity(0.88))
                            .frame(width: proxy.size.width * CGFloat(max(0, min(100, value)) / 100))
                    }
                }
            }
            .frame(height: 4)

            Text(item.resetText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: - Columns

    private var snapshot: UsageSnapshot? { provider.snapshot }

    private var estimatesMonthlyFromWeekly: Bool {
        ["codex", "minimax", "grok"].contains(provider.id)
    }

    private var displayColumns: [SummaryQuotaItem] {
        guard let snapshot else { return [] }
        var cols: [SummaryQuotaItem] = []

        if let session = snapshot.sessionQuota {
            cols.append(SummaryQuotaItem(from: session, title: l10n.t("quota.5h")))
        }
        if let weekly = snapshot.weeklyQuota {
            cols.append(SummaryQuotaItem(from: weekly, title: l10n.t("quota.weekly")))
        }
        if let monthly = realMonthly(in: snapshot) {
            cols.append(SummaryQuotaItem(from: monthly, title: l10n.t("quota.monthly")))
        } else if estimatesMonthlyFromWeekly, let weekly = snapshot.weeklyQuota {
            let est = MonthlyFromWeekly.estimate(weeklyRemaining: weekly.percentRemaining)
            cols.append(SummaryQuotaItem(
                title: l10n.t("quota.monthly"),
                percentRemaining: est.percentRemaining,
                resetText: "\(est.note) · \(Self.shortDate(est.resetsAt))",
                isEstimated: true
            ))
        }
        return cols
    }

    private func realMonthly(in snapshot: UsageSnapshot) -> UsageQuota? {
        snapshot.quotas.first { quota in
            if case .timeLimit(let name) = quota.quotaType {
                let n = name.lowercased()
                return n.contains("month") || n.contains("月")
            }
            return false
        }
    }

    // MARK: - Status

    private var effectiveStatus: QuotaStatus {
        if provider.isSyncing { return .healthy }
        if let snapshot { return snapshot.overallStatus }
        return .depleted
    }

    private var statusTint: Color {
        if provider.isSyncing { return MembershipPalette.statusInfo }
        if provider.snapshot == nil {
            return provider.lastError != nil
                ? MembershipPalette.statusDanger
                : MembershipPalette.statusWarning
        }
        switch effectiveStatus {
        case .healthy: return MembershipPalette.statusSuccess
        case .warning: return MembershipPalette.statusWarning
        case .critical, .depleted: return MembershipPalette.statusDanger
        }
    }

    private var statusLabel: String {
        if provider.isSyncing { return l10n.t("status.syncing") }
        if provider.snapshot == nil {
            return provider.lastError != nil ? l10n.t("menu.unavailable") : l10n.t("common.no_quota")
        }
        switch effectiveStatus {
        case .healthy: return l10n.t("status.healthy")
        case .warning: return l10n.t("status.warning")
        case .critical: return l10n.t("status.critical")
        case .depleted: return l10n.t("status.depleted")
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.shared.language.locale
        f.dateFormat = "MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Summary item

private struct SummaryQuotaItem: Identifiable {
    let id: String
    let title: String
    let percentRemaining: Double?
    let resetText: String
    let isEstimated: Bool

    init(from quota: UsageQuota, title: String) {
        self.id = quota.quotaType.quotaKey + title
        self.title = title
        self.percentRemaining = quota.isDollarBased ? nil : quota.percentRemaining
        self.resetText = Self.formatReset(quota)
        self.isEstimated = false
    }

    init(title: String, percentRemaining: Double?, resetText: String, isEstimated: Bool) {
        self.id = title + (isEstimated ? "-est" : "")
        self.title = title
        self.percentRemaining = percentRemaining
        self.resetText = resetText
        self.isEstimated = isEstimated
    }

    private static func formatReset(_ quota: UsageQuota) -> String {
        if let resetsAt = quota.resetsAt {
            let cal = Calendar.current
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            if cal.isDateInToday(resetsAt) {
                formatter.dateFormat = "HH:mm"
                return "重置 \(formatter.string(from: resetsAt))"
            }
            if cal.isDateInTomorrow(resetsAt) {
                formatter.dateFormat = "HH:mm"
                return "明天 \(formatter.string(from: resetsAt))"
            }
            formatter.dateFormat = "MM-dd HH:mm"
            return "重置 \(formatter.string(from: resetsAt))"
        }
        if let text = quota.resetText, !text.isEmpty {
            return text
                .replacingOccurrences(of: "Resets in ", with: "")
                .replacingOccurrences(of: "Resets ", with: "重置 ")
        }
        return "重置时间未知"
    }
}

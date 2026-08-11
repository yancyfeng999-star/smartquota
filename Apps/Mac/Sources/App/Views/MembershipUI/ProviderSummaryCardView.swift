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
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            metricsBlock
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
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
                        .foregroundStyle(renewalTint)
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

    // MARK: - Metrics (primary row + optional second row)

    private var metricsBlock: some View {
        let primary = primaryColumns
        let secondary = secondaryColumns
        if primary.isEmpty && secondary.isEmpty {
            return AnyView(
                Text(provider.isSyncing ? l10n.t("common.refreshing") : l10n.t("common.no_quota"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                if !primary.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(primary) { item in
                            quotaColumn(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // Second row: Spark weekly / MiniMax video only
                if !secondary.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(secondary) { item in
                            quotaColumn(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        )
    }

    /// Progress bar with label left + mode-aware value right above the bar.
    private func quotaColumn(_ item: SummaryQuotaItem) -> some View {
        let displayMode = settings.usageDisplayMode
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(item.displayValue(mode: displayMode))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // Same style as 5h / 7d / 总额 — no accent/highlight color
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(MembershipPalette.surfaceTrack)
                    if let value = item.progressPercent(mode: displayMode) {
                        Capsule(style: .continuous)
                            .fill(MembershipPalette.progressColor(percentRemaining: value).opacity(0.88))
                            .frame(width: proxy.size.width * CGFloat(max(0, min(100, value)) / 100))
                    }
                }
            }
            .frame(height: 5)

            Text(item.resetText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(resetTint(for: item))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

    private func resetTint(for item: SummaryQuotaItem) -> Color {
        switch item.resetUrgency {
        case .imminent: return MembershipPalette.statusDanger
        case .soon: return MembershipPalette.statusWarning
        case .normal: return .secondary
        }
    }

    private var renewalTint: Color {
        // Only color by **membership** next renewal date — not by 5H/7D quota reset.
        // (Previously wrongly used weekly window, so Grok 续费 turned yellow when 7D was “明天”.)
        _ = settings.planLabelsRevision
        let raw = settings.renewalDate(for: provider.id)
        guard let activation = MembershipRenewal.parse(raw) else {
            return .secondary
        }
        let next = MembershipRenewal.nextRenewal(fromActivation: activation)
        // Membership is calendar-month; warn only when renewal is within ~3 days
        switch QuotaAlertPolicy.resetUrgency(
            resetsAt: next,
            nearResetHours: 72
        ) {
        case .imminent: return MembershipPalette.statusDanger
        case .soon: return MembershipPalette.statusWarning
        case .normal: return .secondary
        }
    }

    // MARK: - Columns

    private var snapshot: UsageSnapshot? { provider.snapshot }

    private var isCodex: Bool { provider.id == "codex" }

    /// First row always: 5H · 7D · 总额（**所有渠道**同一规则）
    /// - 5H / 7D：读到用真值，否则 `—`
    /// - 总额：读到真实月额度用真值；否则按续费日日历线性递减（与 7D 脱钩）
    private var primaryColumns: [SummaryQuotaItem] {
        let snapshot = self.snapshot

        let session: SummaryQuotaItem = {
            if let q = snapshot?.sessionQuota {
                return SummaryQuotaItem(from: q, title: l10n.t("quota.5h"))
            }
            return SummaryQuotaItem.placeholder(title: l10n.t("quota.5h"))
        }()

        let weekly: SummaryQuotaItem = {
            if let q = snapshot?.weeklyQuota {
                return SummaryQuotaItem(from: q, title: l10n.t("quota.weekly"))
            }
            return SummaryQuotaItem.placeholder(title: l10n.t("quota.weekly"))
        }()

        // 总额：全渠道统一 — 真月额度优先，否则续费日递减（无 snapshot 也估）
        let monthly: SummaryQuotaItem = {
            if let snapshot, let q = realMonthly(in: snapshot) {
                return SummaryQuotaItem(from: q, title: l10n.t("quota.monthly"))
            }
            return estimatedMonthlyItem(providerId: provider.id)
        }()

        return [session, weekly, monthly]
    }

    /// 全渠道总额回退：开通日 → 下一续费日，`remaining% = 剩余天数/周期天数×100`。
    /// 未填续费日时退回到本自然月末线性（仍保证「总额」列有数，不跟 7D 挂钩）。
    private func estimatedMonthlyItem(providerId: String) -> SummaryQuotaItem {
        _ = settings.planLabelsRevision // refresh when 开通/续费日 changes
        let raw = AppSettings.shared.renewalDate(for: providerId)
        let title = l10n.t("quota.monthly")
        if let activation = MembershipRenewal.parse(raw) {
            let renew = MembershipRenewal.nextRenewal(fromActivation: activation)
            let est = MembershipCycleRemaining.estimate(renewalAt: renew)
            return SummaryQuotaItem(
                title: title,
                percentRemaining: est.percentRemaining,
                resetText: SummaryQuotaItem.formatTimeOnly(est.resetsAt),
                isEstimated: true
            )
        }
        let est = MembershipCycleRemaining.estimateWithoutRenewal()
        return SummaryQuotaItem(
            title: title,
            percentRemaining: est.percentRemaining,
            resetText: SummaryQuotaItem.formatTimeOnly(est.resetsAt),
            isEstimated: true
        )
    }

    /// Second row:
    /// - Codex: GPT-5.3-Codex-Spark 周限额 + 积分
    /// - MiniMax: 视频 only
    private var secondaryColumns: [SummaryQuotaItem] {
        guard let snapshot else { return [] }
        var cols: [SummaryQuotaItem] = []

        if isCodex {
            if let spark = snapshot.quotas.first(where: { q in
                if case .modelSpecific(let name) = q.quotaType {
                    return name.lowercased().contains("spark")
                        || (q.compactTitle?.contains("Spark") == true)
                }
                return q.compactTitle?.contains("Spark") == true
            }) {
                cols.append(SummaryQuotaItem(
                    from: spark,
                    title: "GPT-5.3 周额度",
                    highlight: false
                ))
            }
            if let credits = snapshot.quotas.first(where: { q in
                if case .timeLimit(let name) = q.quotaType {
                    return name.lowercased().contains("credit")
                }
                return q.compactTitle == "积分"
            }) {
                cols.append(SummaryQuotaItem(
                    from: credits,
                    title: credits.compactTitle ?? "积分",
                    highlight: false
                ))
            }
            return cols
        }

        // MiniMax: one video row
        for quota in snapshot.quotas {
            if case .modelSpecific(let name) = quota.quotaType {
                let n = name.lowercased()
                let title = quota.compactTitle
                if n.contains("video") || n.contains("t2v") || n.contains("i2v")
                    || n.contains("hailuo") || n.contains("视频") || title == "视频" {
                    cols.append(SummaryQuotaItem(
                        from: quota,
                        title: title ?? "视频",
                        highlight: false
                    ))
                    break
                }
            }
        }
        return cols
    }

    /// Real monthly meter from probe only — explicit month naming (no broad “billing” match).
    private func realMonthly(in snapshot: UsageSnapshot) -> UsageQuota? {
        if let named = snapshot.quotas.first(where: { quota in
            if case .timeLimit(let name) = quota.quotaType {
                return Self.isMonthlyName(name)
            }
            if case .modelSpecific(let name) = quota.quotaType {
                return Self.isMonthlyName(name)
            }
            return false
        }) {
            return named
        }
        // Window length ≈ one calendar month (exclude session / weekly)
        return snapshot.quotas.first { quota in
            if case .session = quota.quotaType { return false }
            if case .weekly = quota.quotaType { return false }
            guard let duration = quota.windowDuration else { return false }
            let day: TimeInterval = 86_400
            return duration >= 25 * day && duration <= 40 * day
        }
    }

    private static func isMonthlyName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("month") || n.contains("月") { return true }
        // Chinese probe labels sometimes use 本月 / 月度 without “month”
        if n.contains("本月") || n.contains("月度") || n.contains("月额度") { return true }
        return false
    }

    // MARK: - Status

    private var effectiveStatus: QuotaStatus {
        if provider.isSyncing { return .healthy }
        if let snapshot { return snapshot.overallStatus }
        // No snapshot: error → critical; not yet configured / empty → warning (not depleted)
        return provider.lastError != nil ? .critical : .warning
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
    let quota: UsageQuota?
    let percentRemaining: Double?
    let resetText: String
    let isEstimated: Bool
    let highlight: Bool
    let resetUrgency: QuotaAlertPolicy.ResetUrgency
    let resetsAt: Date?

    /// Right-side value for the selected global display mode.
    func displayValue(mode: UsageDisplayMode) -> String {
        if let quota {
            return quota.summaryDisplay(mode: mode).valueText
        }
        if let value = percentRemaining {
            let displayed = mode == .used ? 100 - value : value
            return "\(Int(displayed.rounded()))/100"
        }
        return "—"
    }

    /// Progress position for the selected global display mode.
    func progressPercent(mode: UsageDisplayMode) -> Double? {
        if let quota {
            return quota.summaryDisplay(mode: mode).progressPercent
        }
        guard let value = percentRemaining else { return nil }
        return mode == .used ? 100 - value : value
    }

    init(from quota: UsageQuota, title: String, highlight: Bool = false) {
        self.id = quota.quotaType.quotaKey + title
        self.title = title
        self.quota = quota
        self.percentRemaining = quota.percentRemaining
        self.highlight = highlight
        self.resetsAt = quota.resetsAt
        self.resetUrgency = QuotaAlertPolicy.resetUrgency(resetsAt: quota.resetsAt)
        self.resetText = Self.formatReset(quota)
        self.isEstimated = false
    }

    init(title: String, percentRemaining: Double?, resetText: String, isEstimated: Bool) {
        self.id = title + (isEstimated ? "-est" : "")
        self.title = title
        self.quota = nil
        self.percentRemaining = percentRemaining
        self.resetText = resetText
        self.isEstimated = isEstimated
        self.highlight = false
        self.resetUrgency = .normal
        self.resetsAt = nil
    }

    /// Empty slot when 5h / 7d / 总额 data is missing (still show the column).
    static func placeholder(title: String) -> SummaryQuotaItem {
        SummaryQuotaItem(
            title: title,
            percentRemaining: nil,
            resetText: "—",
            isEstimated: false
        )
    }

    /// Public helper for estimated monthly reset line (date only).
    static func formatTimeOnly(_ resetsAt: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(resetsAt) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: resetsAt)
        }
        if cal.isDateInTomorrow(resetsAt) {
            formatter.dateFormat = "HH:mm"
            return "明天 \(formatter.string(from: resetsAt))"
        }
        // Renewal is usually a calendar day — show MM-dd
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: resetsAt)
    }

    /// Time only under the bar — no leading「重置」word.
    private static func formatReset(_ quota: UsageQuota) -> String {
        if let resetsAt = quota.resetsAt {
            return formatTimeOnly(resetsAt)
        }
        if let text = quota.resetText, !text.isEmpty {
            var cleaned = text
                .replacingOccurrences(of: "Resets in ", with: "")
                .replacingOccurrences(of: "Resets ", with: "")
                .replacingOccurrences(of: "重置 ", with: "")
                .replacingOccurrences(of: "重置", with: "")
                .replacingOccurrences(of: " · 共 100%", with: "")
                .replacingOccurrences(of: "共 100%", with: "")
                .replacingOccurrences(of: "由7d估算", with: "")
                .replacingOccurrences(of: "时间未知", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
            // Pure counts are already shown as the main value.
            if quota.summaryDisplay(mode: .remaining).isCountBased {
                return "—"
            }
            // Relative phrases like "2d 3h" / "明天 10:57"
            let looksLikeTime = cleaned.contains("明天")
                || cleaned.contains(":")
                || cleaned.range(of: #"\d+[dhmD]"#, options: .regularExpression) != nil
                || cleaned.range(of: #"\d{1,2}-\d{1,2}"#, options: .regularExpression) != nil
            if cleaned.isEmpty || !looksLikeTime {
                return "—"
            }
            return cleaned
        }
        return "—"
    }
}

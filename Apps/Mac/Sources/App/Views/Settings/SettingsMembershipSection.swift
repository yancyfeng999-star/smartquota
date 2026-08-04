import SwiftUI
import Domain
import Infrastructure

/// 会员开关卡片：启用/关闭会员，并编辑套餐与开通日。
struct SettingsMembershipSection: View {
    let monitor: QuotaMonitor
    @Binding var isExpanded: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.appSettings) private var settings
    private var l10n: L10n { L10n.shared }

    private var orderedProviders: [any AIProvider] {
        let order = ProviderCatalog.displayOrder
        return monitor.allProviders.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? Int.max
            let ib = order.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        let _ = l10n.revision
        SettingsExpandableCard(isExpanded: $isExpanded) {
            providersHeader
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.t("settings.members_hint"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    ForEach(orderedProviders, id: \.id) { provider in
                        providerToggleRow(provider: provider)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providersHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("settings.members"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                let onCount = monitor.allProviders.filter(\.isEnabled).count
                Text(l10n.tf("settings.members_count", "\(monitor.allProviders.count)", "\(onCount)"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func providerToggleRow(provider: any AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Provider icon
                ProviderIconView(providerId: provider.id, size: 20)

                Text(provider.name)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(MembershipPlanStore.displayPlan(for: provider))
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setProviderEnabled(provider.id, enabled: newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
            }

            // Plan + renewal for every built-in membership (manual override)
            planLabelField(providerId: provider.id)
                .padding(.leading, 30)
            renewalDateField(providerId: provider.id)
                .padding(.leading, 30)
        }
        .padding(.vertical, 4)
    }

    private func planLabelField(providerId: String) -> some View {
        HStack(spacing: 8) {
            Text(l10n.t("common.plan"))
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 36, alignment: .leading)

            TextField(
                MembershipPlanStore.defaults[providerId] ?? "例如 Plus / Pro",
                text: Binding(
                    get: { settings.planLabel(for: providerId) },
                    set: { settings.setPlanLabel($0, for: providerId) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.glassBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(theme.glassBorder, lineWidth: 1)
                    )
            )
        }
    }

    private func renewalDateField(providerId: String) -> some View {
        let activationBinding = Binding<Date>(
            get: {
                if let d = MembershipRenewal.parse(settings.renewalDate(for: providerId)) {
                    return d
                }
                return Date()
            },
            set: { newDate in
                settings.setRenewalDate(MembershipRenewal.format(newDate), for: providerId)
            }
        )
        let hasDate = MembershipRenewal.parse(settings.renewalDate(for: providerId)) != nil
        let next = hasDate
            ? MembershipRenewal.nextRenewal(fromActivation: activationBinding.wrappedValue)
            : nil

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(l10n.t("common.activation"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 36, alignment: .leading)

                DatePicker(
                    "",
                    selection: activationBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasDate {
                    Button(l10n.t("config.clear")) {
                        settings.setRenewalDate("", for: providerId)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textTertiary)
                }
            }

            if let next {
                Text("\(l10n.t("quota.next_renewal")) \(MembershipRenewal.format(next)) · \(MembershipRenewal.cycleLabel(forProviderId: providerId))")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 44)
            } else {
                Text(l10n.t("quota.pick_activation"))
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 44)
            }
        }
    }


}

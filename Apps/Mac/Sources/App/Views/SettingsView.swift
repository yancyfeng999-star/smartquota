import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Inline settings content view that fits within the menu bar popup.
struct SettingsContentView: View {
    @Binding var showSettings: Bool
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared
    private var l10n: L10n { L10n.shared }

    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    @State private var providersExpanded: Bool = false
    @State private var backgroundSyncExpanded: Bool = false
    @State private var thresholdAlertsExpanded: Bool = false

    // Manual update: check → download pkg → silent install (no confirm dialogs)
    @State private var isCheckingUpdate = false
    @State private var updateStatusText: String?
    @State private var updateOpenURL: URL?
    @State private var updateDownloadURL: URL?
    @State private var updateIsAvailable = false
    @State private var updateLocalInstallerURL: URL?
    /// 0…1 while downloading; nil when not downloading.
    @State private var updateDownloadProgress: Double?
    /// True while expanding/copying pkg (no system Installer UI).
    @State private var isInstallingUpdate = false

    // Hook settings state
    @State private var hooksExpanded: Bool = false
    @State private var hooksEnabled: Bool = false
    @State private var hooksInstalled: Bool = false
    @State private var hookError: String?

    var body: some View {
        let _ = l10n.revision
        // Fill the shared popover panel (same size as home) — no height jump
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    themeCard
                    LanguageSettingsCard()
                    if settings.canContinueOnboarding {
                        ContinueOnboardingCard {
                            OnboardingWindowController.shared.continueFromSettings()
                        }
                    }
                    simpleDisplayModeCard
                    menuBarStatusIconCard
                    // 1) Toggle memberships on/off
                    SettingsMembershipSection(monitor: monitor, isExpanded: $providersExpanded)
                    QuotaDetectionConfigSection(monitor: monitor)
                    backgroundSyncCard
                    thresholdAlertCard
                    launchAtLoginCard
                    DiagnosticsSettingsCard(monitor: monitor)
                    logsCard
                    updatesCard
                    securityCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Simple display (remaining / used only)

    /// Single compact row: title left, 剩余/已用 chips right.
    private var simpleDisplayModeCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "percent")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.quota_display"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(l10n.t("settings.quota_display_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach([UsageDisplayMode.remaining, .used], id: \.rawValue) { mode in
                    DisplayModeButton(
                        mode: mode,
                        isSelected: settings.usageDisplayMode == mode,
                        compact: true
                    ) {
                        AppMotion.withSelection {
                            settings.usageDisplayMode = mode
                        }
                    }
                }
            }
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
    }

    // MARK: - Menu bar status icon (opt-in)

    /// Default status item shows the brand logo; enable to show quota-status
    /// SF Symbols (green bars / warning triangle / depleted bars).
    private var menuBarStatusIconCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.menu_bar_status_icon"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(l10n.t("settings.menu_bar_status_icon_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { settings.menuBarStatusIconEnabled },
                set: { enabled in
                    AppMotion.withSelection {
                        settings.menuBarStatusIconEnabled = enabled
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
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
    }

    // MARK: - Theme Card

    /// Convert ThemeMode to string for settings storage
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    /// Only Light / Dark / System for this product.
    private static let basicThemeModes: [ThemeMode] = [.light, .dark, .system]

    private func compactThemeChip(mode: ThemeMode, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(mode.displayName)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? theme.accentPrimary : theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.12) : theme.glassBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? theme.accentPrimary : theme.glassBorder, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: currentThemeMode.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("settings.appearance"))
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(l10n.t("settings.choose_theme"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            // Only 3 themes, one row: Light / Dark / System
            HStack(spacing: 8) {
                ForEach(Self.basicThemeModes, id: \.rawValue) { mode in
                    compactThemeChip(
                        mode: mode,
                        isSelected: settings.themeMode == mode.rawValue
                    ) {
                        AppMotion.withSelection {
                            settings.themeMode = mode.rawValue
                            // Drop exotic themes (cli / christmas / imported)
                            settings.userHasChosenTheme = true
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Display Mode Card

    private var displayModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            displayModeHeader
            displayModeToggle
            menuBarPercentageToggle
            menuBarDurationToggle
            if settings.menuBarPercentageEnabled || settings.menuBarDurationEnabled {
                menuBarControls
            }
            dailyUsageCardsToggle
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var displayModeHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("额度显示")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("显示剩余 / 已用 / 节奏")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var displayModeToggle: some View {
        HStack(spacing: 8) {
            ForEach(UsageDisplayMode.allCases, id: \.rawValue) { mode in
                DisplayModeButton(
                    mode: mode,
                    isSelected: settings.usageDisplayMode == mode
                ) {
                    AppMotion.withSelection {
                        settings.usageDisplayMode = mode
                    }
                }
            }
        }
    }

    private var menuBarProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var selectedMenuBarProvider: (any AIProvider)? {
        menuBarProviders.first { $0.id == settings.menuBarPercentageProviderId }
            ?? monitor.selectedProvider
            ?? menuBarProviders.first
    }

    private var menuBarQuotaOptions: [UsageQuota] {
        selectedMenuBarProvider?.snapshot?.quotas ?? []
    }

    private var menuBarPercentageToggle: some View {
        HStack {
            Text("菜单栏显示百分比")
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.menuBarPercentageEnabled },
                set: { enabled in
                    settings.menuBarPercentageEnabled = enabled
                    if enabled {
                        normalizeMenuBarSelection()
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
        }
    }

    private var menuBarDurationToggle: some View {
        HStack {
            Text("菜单栏显示重置倒计时")
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.menuBarDurationEnabled },
                set: { enabled in
                    settings.menuBarDurationEnabled = enabled
                    if enabled {
                        normalizeMenuBarSelection()
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
        }
    }

    /// Opt-in stacked rendering for the dual-window label: the two windows
    /// draw as two smaller lines instead of one long "A | B" line, roughly
    /// halving the menu bar width the label occupies.
    private var menuBarStackedToggle: some View {
        HStack {
            Text("菜单栏堆叠显示")
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.menuBarStackedEnabled },
                set: { enabled in
                    settings.menuBarStackedEnabled = enabled
                }
            ))
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
        }
    }

    /// Size selector for the stacked lines. Small is the original 9pt
    /// rendering; Medium and Large enlarge both lines to 10pt and 11pt while
    /// the renderer keeps their ink inside the menu bar's height limit.
    /// Rendered as a labelled chip row (like PROVIDER and QUOTA above) so the
    /// control speaks the section's choice-button language instead of a
    /// system segmented picker.
    private var menuBarStackedSizePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("堆叠文字大小")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            HStack(spacing: 8) {
                ForEach(MenuBarStackedSize.allCases, id: \.self) { size in
                    MenuBarChoiceButton(
                        iconName: size.choiceIconName,
                        label: size.displayLabel,
                        isSelected: settings.menuBarStackedSize == size
                    ) {
                        settings.menuBarStackedSize = size
                    }
                }
            }
        }
    }

    private var menuBarControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("提供商")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(menuBarProviders, id: \.id) { provider in
                            MenuBarProviderChoiceButton(
                                providerId: provider.id,
                                providerName: provider.name,
                                isSelected: settings.menuBarPercentageProviderId == provider.id
                            ) {
                                settings.menuBarPercentageProviderId = provider.id
                                selectFirstMenuBarQuotaIfNeeded(force: true)
                                normalizeSecondaryMenuBarSelection()
                            }
                        }
                    }
                }
                .disabled(menuBarProviders.isEmpty)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("额度窗口")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                if menuBarQuotaOptions.isEmpty {
                    Text("暂无额度数据")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(menuBarQuotaOptions, id: \.quotaType.quotaKey) { quota in
                                MenuBarQuotaChoiceButton(
                                    title: quota.menuBarTitle ?? quota.quotaType.displayName,
                                    isSelected: settings.menuBarPercentageQuotaKey == quota.quotaType.quotaKey
                                ) {
                                    settings.menuBarPercentageQuotaKey = quota.quotaType.quotaKey
                                    normalizeSecondaryMenuBarSelection()
                                }
                            }
                        }
                    }
                }
            }

            if menuBarQuotaOptions.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("第二额度窗口")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            MenuBarChoiceButton(
                                iconName: "minus.circle",
                                label: "None",
                                isSelected: settings.menuBarSecondaryQuotaKey.isEmpty
                            ) {
                                settings.menuBarSecondaryQuotaKey = ""
                            }

                            ForEach(secondaryMenuBarQuotaOptions, id: \.quotaType.quotaKey) { quota in
                                MenuBarQuotaChoiceButton(
                                    title: quota.menuBarTitle ?? quota.quotaType.displayName,
                                    isSelected: settings.menuBarSecondaryQuotaKey == quota.quotaType.quotaKey
                                ) {
                                    settings.menuBarSecondaryQuotaKey = quota.quotaType.quotaKey
                                }
                            }
                        }
                    }

                    // Stacking only changes how two windows render, so the
                    // toggle appears once a secondary window is selected.
                    if !settings.menuBarSecondaryQuotaKey.isEmpty {
                        menuBarStackedToggle

                        // The size only matters while stacking is actually
                        // rendering, so it appears with the toggle on.
                        if settings.menuBarStackedEnabled {
                            menuBarStackedSizePicker
                        }
                    }
                }
            }
        }
        .onAppear {
            normalizeMenuBarSelection()
            normalizeSecondaryMenuBarSelection()
        }
    }

    /// Quota options offered for the optional secondary menu bar window,
    /// excluding the one already chosen as primary.
    private var secondaryMenuBarQuotaOptions: [UsageQuota] {
        menuBarQuotaOptions.filter {
            $0.quotaType.quotaKey != settings.menuBarPercentageQuotaKey
        }
    }

    /// Clears a stored secondary quota key that is no longer offered — e.g. after it
    /// becomes equal to the primary, or the chosen provider's quotas no longer include it.
    private func normalizeSecondaryMenuBarSelection() {
        guard !settings.menuBarSecondaryQuotaKey.isEmpty else { return }
        // An empty options list means quota data has not loaded yet (cold
        // start, provider still syncing), not that the stored selection is
        // invalid. Clearing here would silently discard the user's secondary
        // window on any settings interaction during a sync.
        let validKeys = Set(secondaryMenuBarQuotaOptions.map(\.quotaType.quotaKey))
        guard !validKeys.isEmpty else { return }
        if !validKeys.contains(settings.menuBarSecondaryQuotaKey) {
            settings.menuBarSecondaryQuotaKey = ""
        }
    }

    private func normalizeMenuBarSelection() {
        if let provider = selectedMenuBarProvider,
           settings.menuBarPercentageProviderId != provider.id {
            settings.menuBarPercentageProviderId = provider.id
        }
        selectFirstMenuBarQuotaIfNeeded(force: false)
    }

    private func selectFirstMenuBarQuotaIfNeeded(force: Bool) {
        guard let firstQuota = menuBarQuotaOptions.first else { return }
        let currentQuotaExists = menuBarQuotaOptions.contains {
            $0.quotaType.quotaKey == settings.menuBarPercentageQuotaKey
        }

        if force || !currentQuotaExists {
            settings.menuBarPercentageQuotaKey = firstQuota.quotaType.quotaKey
        }
    }

    private var dailyUsageCardsToggle: some View {
        HStack {
            Text("每日用量卡片")
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Toggle("", isOn: $settings.showDailyUsageCards)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    // MARK: - Overview Mode Card

    private var overviewModeCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("总览模式")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("一次显示全部会员")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.overviewModeEnabled },
                set: { newValue in
                    AppMotion.withExpand {
                        settings.overviewModeEnabled = newValue
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(theme.accentPrimary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Back button
            Button {
                showSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text(l10n.t("common.back"))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.glassBackground)
                        .overlay(
                            Capsule()
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(l10n.t("settings.title"))
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            // Invisible placeholder to balance the header
            Color.clear
                .frame(width: 60, height: 1)
        }
    }

    // MARK: - Updates Card (manual / free GitHub check only)

    /// Compact: title left, single「检查更新」right; progress bar while downloading.
    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.7, blue: 0.4),
                                    Color(red: 0.2, green: 0.55, blue: 0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t("settings.updates"))
                        .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Text(updateSubtitle)
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(updateIsAvailable ? theme.accentPrimary : theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await runManualUpdateCheck() }
                } label: {
                    HStack(spacing: 4) {
                        if isCheckingUpdate && updateDownloadProgress == nil && !isInstallingUpdate {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        }
                        Text(checkUpdateButtonTitle)
                            .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.3, green: 0.7, blue: 0.4),
                                        Color(red: 0.2, green: 0.55, blue: 0.35)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCheckingUpdate)
                .opacity(isCheckingUpdate ? 0.7 : 1)
            }

            if isInstallingUpdate {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.t("settings.updates_installing"))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            } else if let progress = updateDownloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0.3, green: 0.7, blue: 0.4))
                    Text(l10n.tf("settings.updates_progress_fmt", Int((progress * 100).rounded())))
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var checkUpdateButtonTitle: String {
        if isInstallingUpdate {
            return l10n.t("settings.updates_installing_btn")
        }
        if updateDownloadProgress != nil {
            return l10n.t("settings.updates_downloading_btn")
        }
        if isCheckingUpdate {
            return l10n.t("settings.updates_checking")
        }
        return l10n.t("settings.updates_check")
    }

    /// Compact subtitle under the title (no extra body text below the row).
    private var updateSubtitle: String {
        if let updateStatusText {
            return updateStatusText
        }
        return l10n.tf("settings.updates_version_fmt", appVersion)
    }

    @MainActor
    private func runManualUpdateCheck() async {
        isCheckingUpdate = true
        updateStatusText = nil
        updateOpenURL = nil
        updateDownloadURL = nil
        updateLocalInstallerURL = nil
        updateIsAvailable = false
        updateDownloadProgress = nil
        isInstallingUpdate = false
        defer {
            // If we quit for relaunch, this may not run; otherwise reset busy state.
            isCheckingUpdate = false
            isInstallingUpdate = false
            if let p = updateDownloadProgress, p < 1 {
                updateDownloadProgress = nil
            }
        }

        do {
            let result = try await GitHubReleaseChecker().check(currentVersionString: appVersion)
            switch result {
            case .upToDate(let current):
                updateIsAvailable = false
                updateDownloadProgress = nil
                updateStatusText = l10n.tf("settings.updates_up_to_date", current.description)
            case .updateAvailable(let current, let latest):
                updateIsAvailable = true
                updateOpenURL = latest.openURL
                updateDownloadURL = ReleaseDownloader.installerDownloadURL(from: latest)
                updateStatusText = l10n.tf(
                    "settings.updates_available_fmt",
                    latest.version.description,
                    current.description
                )
                // One tap: download + install. No confirm dialog.
                await downloadAndInstallUpdate()
            }
        } catch let error as ManualUpdateError {
            updateIsAvailable = false
            updateDownloadProgress = nil
            updateStatusText = manualUpdateErrorMessage(error)
        } catch {
            updateIsAvailable = false
            updateDownloadProgress = nil
            updateStatusText = l10n.tf("settings.updates_failed_fmt", error.localizedDescription)
        }
    }

    /// Download preferred installer (pkg first). Silent-install pkg; dmg falls back to open.
    @MainActor
    private func downloadAndInstallUpdate() async {
        if let local = updateLocalInstallerURL, FileManager.default.fileExists(atPath: local.path) {
            await finishWithLocalInstaller(local)
            return
        }

        guard let remote = updateDownloadURL else {
            updateDownloadProgress = nil
            if let page = updateOpenURL {
                NSWorkspace.shared.open(page)
                updateStatusText = l10n.t("settings.updates_open_page")
            } else {
                updateStatusText = l10n.t("settings.updates_failed_none")
            }
            return
        }

        updateStatusText = l10n.t("settings.updates_downloading")
        updateDownloadProgress = 0
        do {
            let file = try await ReleaseDownloader().download(from: remote) { fraction in
                Task { @MainActor in
                    updateDownloadProgress = fraction
                    updateStatusText = l10n.tf(
                        "settings.updates_progress_fmt",
                        Int((fraction * 100).rounded())
                    )
                }
            }
            updateLocalInstallerURL = file
            updateDownloadProgress = 1
            await finishWithLocalInstaller(file)
        } catch let error as ManualUpdateError {
            updateDownloadProgress = nil
            // Stay in settings — show error only (no browser popup / no password).
            updateStatusText = manualUpdateErrorMessage(error)
        } catch {
            updateDownloadProgress = nil
            updateStatusText = l10n.tf("settings.updates_failed_fmt", error.localizedDescription)
        }
    }

    @MainActor
    private func finishWithLocalInstaller(_ file: URL) async {
        if file.pathExtension.lowercased() == "pkg" {
            updateDownloadProgress = nil
            isInstallingUpdate = true
            updateStatusText = l10n.t("settings.updates_installing")
            do {
                // Expand + spawn apply.sh (user-level ditto after quit). Never asks password.
                _ = try await SilentPkgInstaller.installAndRelaunch(pkgURL: file)
                updateStatusText = l10n.t("settings.updates_relaunching")
                try? await Task.sleep(nanoseconds: 250_000_000)
                NSApp.terminate(nil)
            } catch let error as ManualUpdateError {
                isInstallingUpdate = false
                updateStatusText = manualUpdateErrorMessage(error)
            } catch {
                isInstallingUpdate = false
                updateStatusText = l10n.tf("settings.updates_failed_fmt", error.localizedDescription)
            }
            return
        }

        // dmg / zip fallback only: open file (may show system UI). Main path is pkg silent.
        updateStatusText = l10n.t("settings.updates_opening")
        NSWorkspace.shared.open(file)
        updateStatusText = l10n.t("settings.updates_quitting")
        try? await Task.sleep(nanoseconds: 800_000_000)
        NSApp.terminate(nil)
    }

    private func manualUpdateErrorMessage(_ error: ManualUpdateError) -> String {
        switch error {
        case .invalidCurrentVersion:
            return l10n.t("settings.updates_failed_version")
        case .noMacReleaseFound:
            return l10n.t("settings.updates_failed_none")
        case .network(let detail), .decode(let detail), .install(let detail):
            return l10n.tf("settings.updates_failed_fmt", detail)
        }
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Logs Card

    private var logsCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.5, blue: 0.6),
                                Color(red: 0.4, green: 0.4, blue: 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("settings.logs"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(l10n.t("settings.logs_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Button {
                FileLogger.shared.openCurrentLogFile()
            } label: {
                Text(l10n.t("common.open"))
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.5, green: 0.5, blue: 0.6),
                                        Color(red: 0.4, green: 0.4, blue: 0.5)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Security Card

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("安全")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("密钥管理与指纹保护")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                NavigationLink {
                    KeyManagementView(
                        authManager: BiometricAuthManager(authService: LocalAuthenticationService.shared),
                        secureStore: SecureKeychainStore(authManager: BiometricAuthManager(authService: LocalAuthenticationService.shared))
                    )
                } label: {
                    Text("管理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accentPrimary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "touchid")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accentPrimary)

                Text("使用指纹或面容保护敏感密钥")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("settings.about"))
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("\(appVersion)")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            Text(Brand.aboutLine)
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Launch at Login Card

    private var launchAtLoginCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.7, blue: 0.4),
                                Color(red: 0.3, green: 0.55, blue: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "power")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("settings.launch"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(l10n.t("settings.launch_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Background Sync Card

    private var backgroundSyncCard: some View {
        SettingsExpandableCard(isExpanded: $backgroundSyncExpanded) {
            backgroundSyncHeader
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("settings.refresh_interval"))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.pickerCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text(l10n.t("settings.bg_sync_help"))
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backgroundSyncHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.6, blue: 0.9),
                                Color(red: 0.2, green: 0.45, blue: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("settings.bg_sync"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("\(l10n.t("settings.bg_sync_sub")) · \(settings.refreshInterval.label)")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: - Threshold alerts (5h / 7d) — collapsed by default

    private var thresholdAlertCard: some View {
        SettingsExpandableCard(isExpanded: $thresholdAlertsExpanded) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("额度阈值报警")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                    Text(
                        settings.quotaThresholdAlertsEnabled
                            ? "已开启 · 5h≤\(Int(settings.sessionAlertThreshold))% · 7d≤\(Int(settings.weeklyAlertThreshold))%"
                            : "已关闭 · 点开配置"
                    )
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用通知")
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                        Text("5 小时 / 7 天剩余低于线时通知；临近重置未用完也会提醒")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $settings.quotaThresholdAlertsEnabled)
                        .toggleStyle(.switch)
                        .tint(theme.accentPrimary)
                        .scaleEffect(0.85)
                        .labelsHidden()
                }

                if settings.quotaThresholdAlertsEnabled {
                    thresholdSliderRow(
                        title: "5 小时剩余 ≤",
                        value: $settings.sessionAlertThreshold,
                        range: 5...50
                    )
                    thresholdSliderRow(
                        title: "7 天剩余 ≤",
                        value: $settings.weeklyAlertThreshold,
                        range: 5...50
                    )
                    thresholdSliderRow(
                        title: "重置前 N 小时提醒",
                        value: $settings.nearResetAlertHours,
                        range: 6...72,
                        unit: "小时"
                    )
                    thresholdSliderRow(
                        title: "未用完阈值（剩余 ≥）",
                        value: $settings.underuseAlertRemaining,
                        range: 20...80
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func thresholdSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String = "%"
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))\(unit)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            Slider(value: value, in: range, step: 1)
                .tint(theme.accentPrimary)
        }
    }

    // MARK: - Burn Rate Card

    private var burnRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "flame")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("消耗速度预警")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("按消耗节奏预警，而非固定阈值")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                Toggle("", isOn: $settings.burnRateWarningEnabled)
                    .toggleStyle(.switch)
                    .tint(theme.accentPrimary)
                    .scaleEffect(0.8)
                    .labelsHidden()
            }

            if settings.burnRateWarningEnabled {
                HStack {
                    Text("阈值")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)

                    Spacer()

                    Picker("", selection: $settings.burnRateThreshold) {
                        Text("1.2x（敏感）").tag(1.2)
                        Text("1.5x（默认）").tag(1.5)
                        Text("2.0x（宽松）").tag(2.0)
                        Text("3.0x（很宽松）").tag(3.0)
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accentPrimary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Hooks Card

    private var hooksCard: some View {
        DisclosureGroup(isExpanded: $hooksExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(hooksInstalled ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(hooksInstalled ? "已安装 Hooks（~/.claude/settings.json）" : "未安装 Hooks")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }

                if let hookError {
                    Text(hookError)
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(.red)
                }

                Text("实时跟踪 Claude Code 会话（活跃状态、子代理、任务完成）。")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        } label: {
            hooksHeader
                .contentShape(.rect)
                .onTapGesture {
                    AppMotion.withExpand {
                        hooksExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var hooksHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.7, blue: 0.5),
                                Color(red: 0.25, green: 0.55, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code Hooks")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("实时会话跟踪")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $hooksEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
                .onChange(of: hooksEnabled) { _, newValue in
                    hookError = nil
                    do {
                        if newValue {
                            try HookInstaller.install()
                        } else {
                            try HookInstaller.uninstall()
                        }
                        settings.hook.setHookEnabled(newValue)
                        hooksInstalled = HookInstaller.isInstalled()
                        NotificationCenter.default.post(
                            name: .hookSettingsChanged,
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    } catch {
                        hookError = error.localizedDescription
                        hooksEnabled = !newValue
                        AppLog.hooks.error("Hook \(newValue ? "install" : "uninstall") failed: \(error.localizedDescription)")
                    }
                }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button {
                AppMotion.withExpand {
                    showSettings = false
                }
            } label: {
                Text("完成")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentSecondary.opacity(0.25), radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Theme Option Button

struct ThemeOptionButton: View {
    let themeProvider: any AppThemeProvider
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var isImported: Bool {
        ThemeRegistry.shared.isImported(id: themeProvider.id)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(themeProvider.accentGradient)
                        .frame(width: 28, height: 28)

                    Image(systemName: themeProvider.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(themeProvider.id == "cli" ? Color.black : .white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(themeProvider.displayName)
                        .font(.system(size: 11, weight: .medium, design: themeProvider.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    if let subtitle = themeProvider.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(themeProvider.accentPrimary)
                    }
                }

                Spacer()

                if isImported {
                    Button {
                        ThemeRegistry.shared.removeImportedTheme(id: themeProvider.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.statusHealthy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.15) : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                            .stroke(isSelected ? theme.accentPrimary : theme.glassBorder.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Display Mode Button

struct DisplayModeButton: View {
    let mode: UsageDisplayMode
    let isSelected: Bool
    var compact: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var iconName: String {
        switch mode {
        case .remaining: "arrow.down.right"
        case .used: "arrow.up.right"
        case .pace: "gauge.with.needle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: iconName)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))

                Text(mode.displayLabel)
                    .font(.system(size: compact ? 11 : 11, weight: .semibold, design: theme.fontDesign))
            }
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 10 : 0)
            .padding(.vertical, compact ? 5 : 8)
            .background(buttonBackground)
            .foregroundStyle(isSelected ? theme.accentPrimary : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: compact ? 7 : 8)
            .fill(isSelected ? theme.accentPrimary.opacity(0.2) : (isHovering ? theme.hoverOverlay : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 8)
                    .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
            )
    }
}

// MARK: - Menu Bar Percentage Choice Buttons

struct MenuBarProviderChoiceButton: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuBarChoiceButton(
            iconName: ProviderVisualIdentityLookup.symbolIcon(for: providerId),
            label: providerName,
            isSelected: isSelected,
            action: action
        )
    }
}

struct MenuBarQuotaChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuBarChoiceButton(
            iconName: "gauge.with.needle.fill",
            label: title,
            isSelected: isSelected,
            action: action
        )
    }
}

struct MenuBarChoiceButton: View {
    let iconName: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))

                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? selectedForeground : theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var selectedForeground: Color {
        theme.id == "cli" ? theme.textPrimary : .white
    }

    private var buttonBackground: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(theme.accentGradient)
                    .shadow(color: theme.accentPrimary.opacity(0.25), radius: 5, y: 2)
            } else {
                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
            }

            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview("Settings - Dark") {
    ZStack {
        DarkTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "dark")
    .frame(width: 380, height: 420)
}

#Preview("Settings - Light") {
    ZStack {
        LightTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "light")
    .frame(width: 380, height: 420)
}

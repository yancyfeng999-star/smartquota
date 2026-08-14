import SwiftUI
import AppKit
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Main menu popover — Runtime menu style for the 4 memberships
/// (Codex / Kimi / MiniMax / Grok). Settings still uses the existing sheet.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let sessionMonitor: SessionMonitor
    let quotaAlerter: QuotaAlerter
    let refreshCoordinator: RefreshCoordinator
    var onHookSettingsChanged: ((Bool) -> Void)?
    /// True when this view is hosted in the independent floating pin window.
    var runsInPinnedWindow: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif
    @State private var isHoveringRefresh = false
    @State private var animateIn = false
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showSharePass = false
    @State private var settings = AppSettings.shared
    private var l10n: L10n { L10n.shared }
    @State private var hasRequestedNotificationPermission = false
    /// The currently selected provider ID (from monitor, which is @Observable)
    private var selectedProviderId: String {
        get { monitor.selectedProviderId }
        nonmutating set { monitor.selectedProviderId = newValue }
    }

    /// The currently selected provider
    private var selectedProvider: (any AIProvider)? {
        monitor.selectedProvider
    }

    /// Default card order when user has not customized.
    private static let defaultMembershipOrder = ["codex", "kimi", "minimax", "grok"]

    /// Enabled memberships in user-defined order (long-press drag to reorder).
    private var membershipProviders: [any AIProvider] {
        _ = settings.membershipOrderRevision
        let preferredOrder = settings.membershipOrder.isEmpty
            ? Self.defaultMembershipOrder
            : settings.membershipOrder
        let enabled = monitor.enabledProviders
        let ordered = preferredOrder.compactMap { id in enabled.first { $0.id == id } }
        let rest = enabled.filter { provider in !preferredOrder.contains(provider.id) }
        return ordered + rest
    }

    private var isAnySyncing: Bool {
        membershipProviders.contains { $0.isSyncing }
    }

    private var lastRefreshedAt: Date? {
        membershipProviders.compactMap(\.snapshot?.capturedAt).max()
    }

    var body: some View {
        let _ = l10n.revision
        ZStack {
            // liquid-glass backdrop (neutral, not purple-pink orbs)
            MembershipPalette.backgroundGradient(for: colorScheme)
                .ignoresSafeArea()

            if showSettings {
                SettingsContentView(showSettings: $showSettings, monitor: monitor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                membershipRuntimeMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Share Pass Overlay (Claude guest pass, when Claude provider is enabled)
            if showSharePass, let claudeProvider = selectedProvider as? ClaudeProvider,
               let guestPass = claudeProvider.guestPass {
                SharePassOverlay(pass: guestPass) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSharePass = false
                    }
                }
            }
        }
        // Popover: fixed compact size. Pinned window: fill host + scroll vertically.
        .modifier(PinnedOrPopoverChrome(runsInPinnedWindow: runsInPinnedWindow))
        .appSettings(settings)
        .environment(\.layoutDirection, l10n.language.layoutDirection)
        .environment(\.locale, l10n.language.locale)
        .id(l10n.revision)
        .sheet(isPresented: $showHelp) {
            HelpCenterView(monitor: monitor)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hookSettingsChanged)) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            onHookSettingsChanged?(enabled)
        }
        .task {
            // Pinned window reuses already-loaded data — skip heavy work that can hang UI.
            if runsInPinnedWindow {
                animateIn = true
                return
            }

            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                let granted = await quotaAlerter.requestPermission()
                AppLog.notifications.info("Alert permission request result: \(granted ? "granted" : "denied")")
            }

            if reduceMotion {
                animateIn = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) {
                    animateIn = true
                }
            }

            await refreshCoordinator.refresh(.allEnabledProviders, skipFreshWithin: Self.freshSnapshotTTL)

            #if ENABLE_SPARKLE
            if sparkleUpdater?.automaticallyChecksForUpdates == true {
                sparkleUpdater?.checkForUpdatesInBackground()
            }
            #endif
        }
        .onChange(of: selectedProviderId) { _, newProviderId in
            Task {
                await refreshCoordinator.refresh(.provider(newProviderId))
            }
        }
    }

    // MARK: - Runtime Menu

    private var membershipRuntimeMenu: some View {
        Group {
            if runsInPinnedWindow {
                // Pinned window: header+footer sticky-ish; middle scrolls when tall/short.
                VStack(spacing: 0) {
                    membershipHeader
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                    ScrollView(.vertical, showsIndicators: true) {
                        membershipCards
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    membershipFooter
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Same fixed panel height as settings — scroll cards if needed
                VStack(alignment: .leading, spacing: 0) {
                    membershipHeader
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                    ScrollView(.vertical, showsIndicators: true) {
                        membershipCards
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    membershipFooter
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 6)
    }

    private var membershipHeader: some View {
        HStack(spacing: 8) {
            // Pure Q mark, transparent PNG — no white/gray plate
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                .accessibilityIdentifier(AccessibilityChrome.ID.decorativeAppLogo)

            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(Brand.nameEN)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Refresh time / counts sit left of the refresh actions
            Text(refreshSubtitle)
                .font(AppTypeScale.callout(.rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .untruncatedSupportText()

            refreshActionCluster

            // Pin: deferred floating window (never block the menu click handler)
            Button {
                togglePinWindow()
            } label: {
                let pinned = runsInPinnedWindow || settings.windowPinned
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 26)
                    .foregroundStyle(pinned ? MembershipPalette.accentPrimary : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(pinned ? MembershipPalette.accentPrimary.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .supportIconAccessibility(
                id: AccessibilityChrome.ID.menuPin,
                valueKey: (runsInPinnedWindow || settings.windowPinned) ? "a11y.pin.value.on" : "a11y.pin.value.off"
            )

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 26)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("?", modifiers: [.command])
            .supportIconAccessibility(id: AccessibilityChrome.ID.menuHelp, valueKey: "a11y.help.value")
        }
    }

    private func togglePinWindow() {
        // Always return immediately — open is deferred to next runloop.
        if runsInPinnedWindow {
            PinnedQuotaWindowController.shared.close()
            return
        }
        PinnedQuotaWindowController.shared.toggleDeferred(
            monitor: monitor,
            sessionMonitor: sessionMonitor,
            quotaAlerter: quotaAlerter,
            refreshCoordinator: refreshCoordinator,
            onHookSettingsChanged: onHookSettingsChanged
        )
    }

    /// Hides the popover or pinned window without quitting the process.
    private func dismissMenuPanel() {
        if runsInPinnedWindow {
            PinnedQuotaWindowController.shared.close()
            return
        }
        // MenuBarExtra `.window` style hosts content in a transient NSWindow.
        if let window = NSApp.keyWindow {
            window.orderOut(nil)
        } else {
            for window in NSApp.windows where window.isVisible && window.canBecomeKey {
                // Prefer non-main status-item panels
                if window.level != .normal || window.styleMask.contains(.nonactivatingPanel) {
                    window.orderOut(nil)
                }
            }
        }
    }

    private var refreshSubtitle: String {
        let _ = refreshCoordinator.state
        switch refreshCoordinator.state {
        case .running:
            return l10n.t("refresh.status.running")
        case .cancelling:
            return l10n.t("refresh.status.cancelling")
        case let .completed(success, failure):
            return l10n.tf("refresh.status.completed", success, failure)
        case let .cancelled(completed):
            return l10n.tf(
                "refresh.status.cancelled",
                completed,
                refreshCoordinator.lastSuccessCount,
                refreshCoordinator.lastFailureCount
            )
        case let .failed(message):
            return l10n.tf("refresh.status.failed", message)
        case .idle:
            if isAnySyncing { return l10n.t("refresh.status.running") }
            if let date = lastRefreshedAt {
                return l10n.tf("refresh.last_at", timeString(date))
            }
            return l10n.t("refresh.status.idle")
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.language.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var isRefreshBusy: Bool {
        refreshCoordinator.state.isBusy || isAnySyncing
    }

    private var refreshActionCluster: some View {
        HStack(spacing: 2) {
            Button {
                Task { await refreshCoordinator.refresh(.provider(selectedProviderId)) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshBusy || selectedProvider == nil)
            .help(l10n.t("refresh.current"))
            .supportIconAccessibility(
                id: AccessibilityChrome.ID.menuRefreshCurrent,
                valueKey: isRefreshBusy ? "a11y.refresh.value.running" : "a11y.refresh.value.idle"
            )

            Button {
                Task { await refreshCoordinator.refresh(.allEnabledProviders) }
            } label: {
                Image(systemName: isRefreshBusy ? "hourglass" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshBusy)
            .keyboardShortcut("r")
            .help(l10n.t("refresh.all"))
            .supportIconAccessibility(
                id: AccessibilityChrome.ID.menuRefresh,
                valueKey: isRefreshBusy ? "a11y.refresh.value.running" : "a11y.refresh.value.idle"
            )

            if refreshCoordinator.state.isBusy {
                Button {
                    Task { await refreshCoordinator.cancel() }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help(l10n.t("refresh.cancel"))
                .supportIconAccessibility(
                    id: AccessibilityChrome.ID.menuRefreshCancel,
                    valueKey: "a11y.refresh.cancel.value"
                )
            }
        }
    }

    private var membershipCards: some View {
        Group {
            if membershipProviders.isEmpty {
                emptyMembershipsCard
            } else {
                VStack(spacing: 8) {
                    // Pending account banners for multi-account providers
                    ForEach(membershipProviders, id: \.id) { provider in
                        if let multiProvider = provider as? (any MultiAccountProvider) {
                            let pending = monitor.pendingConfirmations(for: multiProvider.id)
                            if !pending.isEmpty {
                                PendingAccountBanner(
                                    providerId: multiProvider.id,
                                    pendingAccounts: pending,
                                    onConfirm: { accountId in
                                        monitor.confirmAccount(accountId, forProvider: multiProvider.id)
                                    },
                                    onIgnore: { accountId in
                                        monitor.ignoreAccount(accountId, forProvider: multiProvider.id)
                                    }
                                )
                            }
                        }
                    }

                    ReorderableMembershipList(
                        providers: membershipProviders,
                        selectedId: selectedProviderId,
                        onSelect: { id in
                            selectedProviderId = id
                            Task { await refreshCoordinator.refresh(.provider(id)) }
                        },
                        onReorder: { newOrder in
                            settings.membershipOrder = newOrder
                        }
                    )
                }
            }
        }
    }

    private var emptyMembershipsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("menu.empty_title"))
                .font(.system(size: 13, weight: .semibold))
            Text(l10n.t("menu.empty_body"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MembershipPalette.cardFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MembershipPalette.cardStroke(colorScheme), lineWidth: 0.9)
                )
        )
    }

    private var membershipFooter: some View {
        HStack(spacing: 8) {
            membershipCommandButton(
                title: l10n.t("menu.open_dashboard"),
                systemName: "safari",
                action: {
                    if let url = selectedProvider?.dashboardURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            .disabled(selectedProvider?.dashboardURL == nil)
            .keyboardShortcut("d")
            .supportKeyboardIdentifier(AccessibilityChrome.ID.menuDashboard)

            membershipCommandButton(
                title: l10n.t("common.settings"),
                systemName: "gearshape",
                action: { showSettings = true }
            )
            .keyboardShortcut(",")
            .supportKeyboardIdentifier(AccessibilityChrome.ID.menuSettings)

            membershipCommandButton(
                title: l10n.t("common.quit"),
                systemName: "power",
                action: { NSApplication.shared.terminate(nil) }
            )
            .help(l10n.t("common.quit"))
            .supportKeyboardIdentifier(AccessibilityChrome.ID.menuQuit)
            // No ⌘Q here — ⌘Q still works system-wide; avoid accidental toolbar quit.
        }
    }

    private func membershipCommandButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MembershipPalette.controlFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(MembershipPalette.controlStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .focusable()
    }

    /// Upper bound for the scrollable content region — see
    /// `PopoverContentHeight` for the policy and its tests.
    private var contentMaxHeight: CGFloat {
        PopoverContentHeight.maxHeight(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 800,
            overviewMode: settings.overviewModeEnabled
        )
    }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                // Large purple orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.purpleVibrant.opacity(colorScheme == .dark ? 0.4 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: -60, y: -80)
                    .blur(radius: 40)

                // Pink orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.pinkHot.opacity(colorScheme == .dark ? 0.35 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width - 80, y: geo.size.height - 150)
                    .blur(radius: 30)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Custom Provider Icon - shows AppLogo in overview mode, provider icon otherwise
            // Avoid animation on provider icon to prevent constraint update loops in MenuBarExtra
            ZStack {
                if settings.overviewModeEnabled, let logo = NSImage(named: "AppLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(theme.accentPrimary.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: theme.accentPrimary.opacity(0.15), radius: 3, y: 1)
                } else {
                    ProviderIconView(providerId: selectedProviderId, size: 38)
                }

                // Christmas star sparkle overlay
                if theme.id == "christmas" {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accentPrimary)
                        .offset(x: 14, y: -14)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(Brand.displayTitle)
                        .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    // Christmas gift icon
                    if theme.id == "christmas" {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accentPrimary)
                    }
                }

                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.id == "cli" ? theme.accentPrimary : theme.textSecondary)
            }

            Spacer()

            // Status Badge
            statusBadge
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    private var headerSubtitle: String {
        switch theme.id {
        case "cli": return "> usage monitor"
        case "christmas": return "Happy Holidays!"
        default: return "AI Usage Monitor"
        }
    }

    /// Status of the currently selected provider
    private var selectedProviderStatus: QuotaStatus {
        guard let snapshot = selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    /// Whether the selected provider is currently syncing
    private var isSelectedProviderSyncing: Bool {
        selectedProvider?.isSyncing ?? false
    }

    private var statusBadge: some View {
        let statusColor = theme.statusColor(for: selectedProviderStatus)

        return HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: statusColor,
                isSyncing: isSelectedProviderSyncing
            )

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .fill(theme.glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(statusColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        if isSelectedProviderSyncing { return "Syncing..." }
        return selectedProviderStatus.badgeText
    }

    /// Help text for settings button, includes update info if available
    private var updateAvailableHelpText: String {
        #if ENABLE_SPARKLE
        if let version = sparkleUpdater?.availableVersion, sparkleUpdater?.isUpdateAvailable == true {
            return "Update available: v\(version)"
        }
        #endif
        return "Settings"
    }

    // MARK: - Provider Pills

    /// Only show enabled providers in the pills
    private var enabledProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(enabledProviders, id: \.id) { provider in
                    ProviderPill(
                        providerId: provider.id,
                        providerName: provider.name,
                        isSelected: provider.id == selectedProviderId,
                        hasData: provider.snapshot != nil
                    ) {
                        // Avoid withAnimation to prevent constraint update loops in MenuBarExtra
                        selectedProviderId = provider.id
                    }
                }
            }
            .background(HorizontalScrollBooster())
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if settings.overviewModeEnabled {
            let providers = monitor.enabledProviders
            if providers.isEmpty {
                emptyState
            } else {
                overviewContent(providers: providers)
            }
        } else if let provider = selectedProvider, let snapshot = provider.snapshot {
            VStack(spacing: 12) {
                // Account picker for multi-account providers
                if let multiProvider = provider as? (any MultiAccountProvider),
                   multiProvider.accounts.count > 1 {
                    AccountPickerView(provider: multiProvider) { accountId in
                        multiProvider.switchAccount(to: accountId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    accountCard(displayName: displayName, snapshot: snapshot)
                }
                statsGrid(snapshot: snapshot)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if selectedProvider?.isSyncing == true {
            loadingState
        } else {
            emptyState
        }
    }

    private func overviewContent(providers: [any AIProvider]) -> some View {
        // Scrolling is owned by the shared middle-region ScrollView in
        // `body`; nesting another vertical ScrollView here would break
        // height negotiation and swallow gestures.
        VStack(spacing: 12) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Divider()
                        .background(theme.glassBorder)
                }
                providerSection(provider: provider)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
    }

    private func providerSection(provider: any AIProvider) -> some View {
        VStack(spacing: 8) {
            providerSectionHeader(provider: provider)

            if let snapshot = provider.snapshot {
                statsGrid(snapshot: snapshot)
            } else if provider.isSyncing {
                LoadingSpinnerView()
            } else {
                compactErrorState(provider: provider)
            }
        }
    }

    private func providerSectionHeader(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 20, showGlow: false)

            HStack(spacing: 6) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                // Account count badge for multi-account providers
                if let multiProvider = provider as? (any MultiAccountProvider),
                   multiProvider.accounts.count > 1 {
                    Text(L10n.shared.tf("account.count_fmt", "\(multiProvider.accounts.count)"))
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(theme.glassBackground)
                        )
                }
            }

            Spacer()

            let status = provider.snapshot?.overallStatus ?? .healthy
            Text(provider.isSyncing ? "Syncing..." : status.badgeText)
                .badge(theme.statusColor(for: status))
        }
        .padding(.horizontal, 4)
    }

    private func compactErrorState(provider: any AIProvider) -> some View {
        let kind = SupportErrorCatalog.classify(provider.lastError, providerId: provider.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SemanticStatusStyle.color(.warning, theme: theme, highContrast: colorSchemeContrast == .increased))
                    .decorativeGlyph()
                SemanticStatusLabel(kind: .failure, theme: theme, highContrast: colorSchemeContrast == .increased)
            }
            UnifiedErrorBlock(kind: kind, theme: theme)
        }
        .padding(.vertical, 4)
    }


    private func accountCard(displayName: String, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(ProviderVisualIdentityLookup.gradient(for: selectedProviderId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.accentPrimary.opacity(0.8))
                            )
                    }
                }

                Text("Updated \(snapshot.ageDescription)")
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statusWarning)
            }
        }
        .glassCard(cornerRadius: 12, padding: 10)
    }

    /// Collapsed state of quota-group sections, keyed by `QuotaGroup.id`.
    /// Ephemeral by design: reopening the popover starts fully expanded.
    @State private var collapsedQuotaGroups: Set<String> = []

    /// Sections for aggregating providers (e.g. Oh My Pi): one collapsible
    /// block per upstream account, so ten flat cards become scannable.
    @ViewBuilder
    private func quotaGroupSections(snapshot: UsageSnapshot) -> some View {
        let groups = snapshot.quotaGroups
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                let baseDelay = Double(groups.prefix(groupIndex).reduce(0) { $0 + $1.quotas.count }) * 0.08
                quotaGroupSection(group, baseDelay: baseDelay)
            }
        }
    }

    private func quotaGroupSection(_ group: QuotaGroup, baseDelay: Double) -> some View {
        // Note-only sections (accounts without usable quota data) have no
        // cards to collapse; the note renders inline in the header.
        let isNoteOnly = group.quotas.isEmpty
        let isCollapsed = !isNoteOnly && collapsedQuotaGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    collapsedQuotaGroups = isCollapsed
                        ? collapsedQuotaGroups.subtracting([group.id])
                        : collapsedQuotaGroups.union([group.id])
                }
            } label: {
                HStack(spacing: 6) {
                    if !isNoteOnly {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }

                    Text((group.title ?? "Other").uppercased())
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer(minLength: 4)

                    if case .headerInline(let note) = group.notePlacement {
                        Text(note)
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    } else if isNoteOnly {
                        Text(L10n.shared.t("menu.no_usage"))
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        // Collapsed sections keep their headline number visible.
                        if isCollapsed, let lowest = group.lowestQuota {
                            Text("\(Int(lowest.percentRemaining))% left")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(group.worstStatus.badgeText)
                            .badge(theme.statusColor(for: group.worstStatus))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isNoteOnly)

            if !isNoteOnly && !isCollapsed {
                // A note attached to a quota-bearing section (the same
                // account also reported "No usage" somewhere) is shown as
                // its own row - never silently dropped.
                if case .row(let note) = group.notePlacement {
                    Text(note)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                TwoColumnCardGrid(
                    items: Array(group.quotas.enumerated()),
                    id: \.element.quotaType
                ) { entry in
                    WrappedStatCard(quota: entry.element, delay: baseDelay + Double(entry.offset) * 0.08)
                }
            }
        }
    }

    @ViewBuilder
    private func statsGrid(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 10) {
            // Grouped sections cover aggregating providers even when every
            // account lacks quota data (note-only sections must still render).
            if snapshot.hasQuotaGroups {
                quotaGroupSections(snapshot: snapshot)
            } else if !snapshot.quotas.isEmpty {
                TwoColumnCardGrid(
                    items: Array(snapshot.quotas.enumerated()),
                    id: \.element.quotaType
                ) { entry in
                    WrappedStatCard(quota: entry.element, delay: Double(entry.offset) * 0.08)
                }
            }

            // Show Extra usage cost card if available (Pro with Extra usage enabled)
            if let costUsage = snapshot.costUsage {
                let budget = settings.claudeApiBudgetEnabled ? settings.claudeApiBudget : nil
                CostStatCard(costUsage: costUsage, budget: budget, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Show Bedrock usage card if available
            if let bedrockUsage = snapshot.bedrockUsage {
                BedrockUsageCard(usage: bedrockUsage, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Show daily usage cards from JSONL session analysis (e.g., Claude Code)
            // Controlled via Settings toggle or ~/.smartquota/settings.json
            if settings.showDailyUsageCards, let report = snapshot.dailyUsageReport {
                let baseDelay = Double(snapshot.quotas.count + 1) * 0.08
                HStack(spacing: 10) {
                    DailyUsageCardView(metric: .cost, report: report, delay: baseDelay)
                        .frame(maxWidth: .infinity)
                    DailyUsageCardView(metric: .tokens, report: report, delay: baseDelay + 0.08)
                        .frame(maxWidth: .infinity)
                }
                if report.today.workingTime > 0 || report.previous.workingTime > 0 {
                    DailyUsageCardView(metric: .workingTime, report: report, delay: baseDelay + 0.16)
                }
            }

            // Show extension metrics cards (from extension probes)
            if let extensionMetrics = snapshot.extensionMetrics?.filter({ $0.group == nil }),
               !extensionMetrics.isEmpty {
                let metricBaseDelay = Double(snapshot.quotas.count + 2) * 0.08
                TwoColumnCardGrid(
                    items: Array(extensionMetrics.enumerated()),
                    id: \.element.label
                ) { entry in
                    ExtensionMetricCardView(metric: entry.element, delay: metricBaseDelay + Double(entry.offset) * 0.08)
                }
            }

            // Show custom web card if URL is configured for this provider
            if let urlString = settings.provider.customCardURL(forProvider: snapshot.providerId),
               let url = URL(string: urlString) {
                let cardDelay = Double(snapshot.quotas.count + 2) * 0.08
                CustomWebCardView(url: url, delay: cardDelay)
            }
        }
        .padding(.top, 4)
    }

    private var loadingState: some View {
        LoadingSpinnerView()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.statusWarning.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.statusWarning)
            }

            Text("\(selectedProvider?.name ?? selectedProviderId) \(L10n.shared.t("menu.unavailable"))")
                .font(AppTypeScale.headline(theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .untruncatedSupportText()

            UnifiedErrorBlock(
                kind: SupportErrorCatalog.classify(selectedProvider?.lastError, providerId: selectedProviderId),
                theme: theme
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            // Dashboard Button
            WrappedActionButton(
                icon: "safari.fill",
                label: "Dashboard",
                gradient: theme.accentGradient
            ) {
                if let url = selectedProvider?.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")
            .supportKeyboardIdentifier(AccessibilityChrome.ID.menuDashboard)

            // Refresh Button
            let isCurrentlyRefreshing = settings.overviewModeEnabled
                ? monitor.enabledProviders.contains { $0.isSyncing }
                : selectedProvider?.isSyncing == true
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: theme.accentGradient,
                isLoading: isCurrentlyRefreshing
            ) {
                if settings.overviewModeEnabled {
                    Task { await refreshCoordinator.refresh(.allEnabledProviders) }
                } else {
                    Task { await refreshCoordinator.refresh(.provider(selectedProviderId)) }
                }
            }
            .keyboardShortcut("r")
            .supportIconAccessibility(
                id: AccessibilityChrome.ID.menuRefresh,
                valueKey: isCurrentlyRefreshing ? "a11y.refresh.value.running" : "a11y.refresh.value.idle"
            )

            Spacer()

            // Share Button (Claude only) - icon only
            if let claudeProvider = selectedProvider as? ClaudeProvider,
               claudeProvider.supportsGuestPasses {
                let isFetchingPasses = claudeProvider.isFetchingPasses
                Button {
                    Task { await fetchAndShowPasses() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.shareGradient)
                            .frame(width: 32, height: 32)

                        if isFetchingPasses {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(.white)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s")
                .supportIconAccessibility(id: AccessibilityChrome.ID.menuShare, valueKey: "a11y.share.value")
            }

            // Settings Button with update indicator
            Button {
                // Avoid window resize animation glitches in MenuBarExtra.
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)

                    // Update available indicator
                    #if ENABLE_SPARKLE
                    if sparkleUpdater?.isUpdateAvailable == true {
                        UpdateBadge(accentColor: theme.accentPrimary)
                            .offset(x: 14, y: -14)
                    }
                    #endif
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .supportIconAccessibility(id: AccessibilityChrome.ID.menuSettings, valueKey: "a11y.settings_icon.value")

            // Close panel only — do NOT terminate. App stays in the menu bar.
            Button {
                dismissMenuPanel()
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .supportIconAccessibility(id: AccessibilityChrome.ID.menuClosePanel, valueKey: "a11y.close_panel.value")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }

    // MARK: - Actions

    /// Skip re-probe when a snapshot is still fresh (cuts CPU/network when
    /// opening the menu repeatedly).
    private static let freshSnapshotTTL: TimeInterval = 45

    /// Fetch guest passes and show the share view
    private func fetchAndShowPasses() async {
        guard let claudeProvider = selectedProvider as? ClaudeProvider else {
            return
        }

        // Prevent duplicate fetches
        guard !claudeProvider.isFetchingPasses else { return }

        do {
            _ = try await claudeProvider.fetchPasses()
            withAnimation(.easeInOut(duration: 0.2)) {
                showSharePass = true
            }
        } catch {
            // Provider stores error in lastError
        }
    }
}

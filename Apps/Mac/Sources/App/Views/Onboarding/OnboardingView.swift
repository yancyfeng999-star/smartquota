import SwiftUI
import AppKit
import Domain
import Infrastructure

/// First-launch guide. Closing the window must not quit the menu-bar app.
struct OnboardingView: View {
    @State private var state: FirstLaunchState
    @State private var report: CompatibilityReport?
    @State private var isCheckingCompatibility = false
    @State private var isRefreshing = false
    @State private var showingHelp = false

    let store: FirstLaunchStore
    let monitor: QuotaMonitor
    var onFinished: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appSettings) private var settings
    private var l10n: L10n { L10n.shared }

    init(store: FirstLaunchStore, monitor: QuotaMonitor, onFinished: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.onFinished = onFinished
        _state = State(initialValue: store.load())
    }

    var body: some View {
        let _ = l10n.revision
        ZStack {
            MembershipPalette.backgroundGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ScrollView {
                    stepContent
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 440, minHeight: 560)
        .environment(\.layoutDirection, l10n.language.layoutDirection)
        .environment(\.locale, l10n.language.locale)
        .sheet(isPresented: $showingHelp) {
            OnboardingHelpSheet()
        }
        .task {
            await runCompatibilityCheck()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("onboard.title"))
                .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("onboard.subtitle"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(stepCaption)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.accentPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepCaption: String {
        let visible = OnboardingStep.ordered.filter { $0 != .completed }
        let index = (visible.firstIndex(of: state.currentStep) ?? 0) + 1
        let title: String
        switch state.currentStep {
        case .privacy: title = l10n.t("onboard.step.privacy")
        case .compatibility: title = l10n.t("onboard.step.compatibility")
        case .chooseProvider: title = l10n.t("onboard.step.choose")
        case .configureProvider: title = l10n.t("onboard.step.configure")
        case .firstRefresh: title = l10n.t("onboard.step.refresh")
        case .completed: title = l10n.t("onboard.step.completed")
        }
        if state.currentStep == .completed {
            return title
        }
        return "\(index)/\(visible.count) · \(title)"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case .privacy:
            PrivacyBoundaryView()
        case .compatibility:
            compatibilityStep
        case .chooseProvider:
            chooseProviderStep
        case .configureProvider:
            configureProviderStep
        case .firstRefresh:
            firstRefreshStep
        case .completed:
            completedStep
        }
    }

    private var compatibilityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report {
                CompatibilityView(
                    report: report,
                    onRecheck: { Task { await runCompatibilityCheck() } },
                    onViewHelp: { showingHelp = true }
                )
            } else if isCheckingCompatibility {
                Text(l10n.t("common.checking"))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooseProviderStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("onboard.choose.title"))
                .font(.system(size: 14, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("onboard.choose.subtitle"))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(orderedProviders, id: \.id) { provider in
                Button {
                    select(provider.id)
                } label: {
                    HStack(spacing: 10) {
                        ProviderIconView(providerId: provider.id, size: 22, showGlow: false)
                        Text(provider.name)
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        if state.selectedProviderId == provider.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MembershipPalette.statusSuccess)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.cardGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        state.selectedProviderId == provider.id
                                            ? theme.accentPrimary.opacity(0.7)
                                            : theme.glassBorder,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var configureProviderStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("onboard.configure.title"))
                .font(.system(size: 14, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("onboard.configure.subtitle"))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let id = state.selectedProviderId, let provider = monitor.provider(for: id) {
                ProviderConfigRegistry.configCard(
                    for: provider,
                    monitor: monitor,
                    extensionConfig: settings.extensionConfig
                )
            } else {
                Text(l10n.t("onboard.choose.none"))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstRefreshStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("onboard.refresh.title"))
                .font(.system(size: 14, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Button {
                Task { await runFirstRefresh() }
            } label: {
                Text(isRefreshing ? l10n.t("common.checking") : l10n.t("onboard.refresh.run"))
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.accentGradient))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || state.selectedProviderId == nil)

            if let outcome = state.lastRefreshOutcome {
                Text(l10n.t(outcome.messageKey))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.t(outcome.nextStepKey))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            followUpButtons(
                OnboardingFollowUp.actions(
                    report: report,
                    missingCredential: state.lastRefreshOutcome == .needsConfiguration,
                    outcome: state.lastRefreshOutcome,
                    hasSelectedProvider: state.selectedProviderId != nil
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("onboard.completed.title"))
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("onboard.completed.body"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if state.currentStep != .privacy && state.currentStep != .completed {
                Button(l10n.t("common.back")) {
                    state.goBack()
                    persist()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            }

            if !state.isCompleted {
                Button(l10n.t("onboard.skip")) {
                    state.skip()
                    persist()
                    onFinished()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            if state.currentStep == .completed {
                Button(l10n.t("common.done")) {
                    persist()
                    onFinished()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accentGradient))
            } else {
                Button(l10n.t("onboard.next")) {
                    state.completeCurrentAndAdvance()
                    persist()
                    if state.isCompleted {
                        onFinished()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accentGradient))
                .opacity(state.canAdvance ? 1 : 0.45)
                .disabled(!state.canAdvance)
            }
        }
    }

    @ViewBuilder
    private func followUpButtons(_ actions: [OnboardingFollowUpAction]) -> some View {
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button(title(for: action)) {
                        perform(action)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
                }
            }
        }
    }

    private func title(for action: OnboardingFollowUpAction) -> String {
        switch action {
        case .openSystemSettings: l10n.t("compat.action.open_settings")
        case .openConfiguration: l10n.t("onboard.action.open_config")
        case .viewHelp: l10n.t("onboard.action.view_help")
        case .recheck: l10n.t("onboard.action.recheck")
        }
    }

    private func perform(_ action: OnboardingFollowUpAction) {
        switch action {
        case .openSystemSettings:
            openSystemSettingsFromReport()
        case .openConfiguration:
            jumpToConfigure()
        case .viewHelp:
            showingHelp = true
        case .recheck:
            Task {
                await runCompatibilityCheck()
                if state.currentStep == .firstRefresh {
                    await runFirstRefresh()
                }
            }
        }
    }

    private var orderedProviders: [any AIProvider] {
        let order = ProviderCatalog.displayOrder
        return monitor.allProviders.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? Int.max
            let ib = order.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func select(_ providerId: String) {
        monitor.setProviderEnabled(providerId, enabled: true)
        monitor.selectProvider(id: providerId)
        state.selectProvider(providerId)
        persist()
    }

    private func jumpToConfigure() {
        state.currentStep = state.configurationDestination
        persist()
    }

    private func openSystemSettingsFromReport() {
        let pane = report?.issues.first { $0.kind == .notifications }?.systemSettingsPane
            ?? report?.issues.first { $0.kind == .keychain }?.systemSettingsPane
        guard let pane, let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    private func persist() {
        try? store.save(state)
        AppSettings.shared.syncFirstLaunch(state)
    }

    private func runCompatibilityCheck() async {
        isCheckingCompatibility = true
        defer { isCheckingCompatibility = false }
        let checker = CompatibilityChecker(
            store: JSONSettingsStore(fileURL: store.configRoot.appendingPathComponent("settings.json")),
            environment: .live(appDirectory: store.configRoot)
        )
        let next = await checker.check()
        report = next
        AppSettings.shared.updateCompatibilityReport(next)
    }

    private func runFirstRefresh() async {
        guard let id = state.selectedProviderId else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await monitor.refresh(providerId: id)
        let provider = monitor.provider(for: id)
        let outcome = FirstRefreshOutcome.classify(
            snapshot: provider?.snapshot,
            error: provider?.lastError
        )
        state.recordFirstRefresh(outcome)
        persist()
    }
}

struct ContinueOnboardingCard: View {
    var onContinue: () -> Void

    @Environment(\.appTheme) private var theme
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.continue_onboarding"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Text(l10n.t("settings.continue_onboarding_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button(l10n.t("settings.continue_onboarding")) {
                onContinue()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.accentGradient))
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
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var store: FirstLaunchStore?
    private var monitor: QuotaMonitor?

    func configure(store: FirstLaunchStore, monitor: QuotaMonitor) {
        self.store = store
        self.monitor = monitor
        AppSettings.shared.syncFirstLaunch(store.load())
    }

    func presentIfNeeded(launchMode: AppLaunchMode) {
        guard let store else { return }
        let state = store.load()
        guard state.shouldPresent(launchMode: launchMode) else { return }
        show()
    }

    func continueFromSettings() {
        guard let store else { return }
        var state = store.load()
        state.resumeFromSettings()
        try? store.save(state)
        AppSettings.shared.syncFirstLaunch(state)
        show()
    }

    func show() {
        guard let store, let monitor else { return }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "\(Brand.nameCN) · \(L10n.lookup("onboard.title", language: L10n.shared.language))"
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        window?.contentView = NSHostingView(
            rootView: OnboardingView(store: store, monitor: monitor) { [weak self] in
                self?.close()
            }
            .appThemeProvider(themeModeId: AppSettings.shared.themeMode)
            .appSettings(AppSettings.shared)
        )
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let store {
            var state = store.load()
            state.dismissWindow()
            try? store.save(state)
            AppSettings.shared.syncFirstLaunch(state)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the guide must not quit the menu-bar agent.
    }
}

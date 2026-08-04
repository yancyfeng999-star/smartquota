import SwiftUI
import AppKit
import Domain
import Infrastructure
import MenuBarExtraAccess
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.smartquota.hookSettingsChanged")
}

@main
struct SmartQuotaApp: App {
    /// AppKit delegate: do not quit when the last window (pin panel) closes.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// Monitors Claude Code sessions via hook events
    @State private var sessionMonitor: SessionMonitor

    /// Drives the menu-bar pixels and the background-refresh lifecycle
    /// imperatively, outside SwiftUI — the MenuBarExtra label hosting can
    /// permanently stop re-evaluating after system sleep (issue #192).
    private let statusItemDriver: StatusItemLabelDriver

    /// Binding required by `.menuBarExtraAccess`; also enables programmatic
    /// dropdown control if ever needed.
    @State private var isMenuPresented = false

    /// The hook HTTP server that receives events from Claude Code
    private let hookServer = HookHTTPServer()

    /// Task for the hook server event loop (allows cancellation on toggle off)
    @State private var hookServerTask: Task<Void, Never>?

    /// Alerts users when quota status degrades / thresholds hit
    private let quotaAlerter = NotificationAlerter(thresholdReader: {
        await MainActor.run {
            let s = AppSettings.shared
            return NotificationAlerter.ThresholdConfig(
                enabled: s.quotaThresholdAlertsEnabled,
                sessionThreshold: s.sessionAlertThreshold,
                weeklyThreshold: s.weeklyAlertThreshold,
                nearResetHours: s.nearResetAlertHours,
                underuseRemaining: s.underuseAlertRemaining
            )
        }
    })

    /// Sends session start/end notifications
    private let sessionAlertSender = SystemAlertSender()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("\(Brand.nameCN) (\(Brand.nameEN)) v\(version) (\(build)) initializing...")
        #if DEBUG
        let missingCN = L10n.keysMissingChinese()
        if !missingCN.isEmpty {
            AppLog.ui.error("L10n missing zh-Hans for \(missingCN.count) keys: \(missingCN.prefix(8).joined(separator: ", "))…")
        }
        #endif

        // Create the shared settings repository (JSON-backed: ~/.smartquota/settings.json)
        // JSONSettingsRepository implements all sub-protocols:
        // - AppSettingsRepository (app-level display/sync settings)
        // - ProviderSettingsRepository + all provider sub-protocols
        // - HookSettingsRepository
        let settingsRepository = JSONSettingsRepository.shared

        // Built-in catalog: core 4 + common open-source memberships.
        // More can be added later in ProviderCatalog (and via ~/.smartquota/extensions/).
        let allProviders = ProviderCatalog.makeAllProviders(settingsRepository: settingsRepository)
        let repository = AIProviders(providers: allProviders)
        AppLog.providers.info(
            "Created \(repository.all.count) providers (core: \(ProviderCatalog.coreProviderIDs.sorted().joined(separator: ", ")); + extensions)"
        )

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        let monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        self.monitor = monitor
        AppLog.monitor.info("QuotaMonitor initialized")

        let sessionMonitor = SessionMonitor()
        self.sessionMonitor = sessionMonitor

        // The driver owns the menu-bar pixels and the refresh-loop lifecycle
        // (outside SwiftUI — see StatusItemLabelDriver). Pixels start flowing
        // once `.menuBarExtraAccess` hands over the NSStatusItem.
        statusItemDriver = StatusItemLabelDriver(
            monitor: monitor,
            settings: AppSettings.shared,
            sessionMonitor: sessionMonitor
        )
        statusItemDriver.startMonitoringLifecycle()

        // Load user extensions from ~/.smartquota/extensions/
        let extensionRegistry = ExtensionRegistry(
            settingsRepository: settingsRepository,
            configRepository: AppSettings.shared.extensionConfig
        )
        let extensionProviders = extensionRegistry.loadExtensions(into: monitor)
        if !extensionProviders.isEmpty {
            AppLog.providers.info("Loaded \(extensionProviders.count) extension provider(s): \(extensionProviders.map(\.name).joined(separator: ", "))")
        }

        // Start hook server if hooks are enabled
        if settingsRepository.isHookEnabled() {
            // Reconcile installed hooks so newly-added events (e.g.
            // UserPromptSubmit, which revives a stopped session) register for
            // existing users without re-toggling the setting. install() is
            // idempotent — it replaces only 智额's own matcher entries
            // per event and preserves hooks from other tools.
            if HookInstaller.isInstalled() {
                try? HookInstaller.install()
            }
            startHookServer()
        }

        // Note: Notification permission is requested in onAppear, not here
        // Menu bar apps need the run loop to be active before requesting permissions

        AppLog.ui.info("\(Brand.nameCN) initialization complete")
    }

    /// App settings for theme
    @State private var settings = AppSettings.shared

    /// Current theme mode from settings
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    private func startHookServer() {
        // Cancel any existing server task
        hookServerTask?.cancel()
        hookServer.stop()

        hookServerTask = Task {
            do {
                let events = try await hookServer.start()
                AppLog.hooks.info("Hook server started, listening for events")
                for await event in events {
                    // Ignore 智额's own background quota probe so routine
                    // polling doesn't spam "Claude Code Finished: Probe"
                    // notifications or pollute the recent-sessions list. (issue #172)
                    guard !event.isAppBackgroundProbe else { continue }
                    await sessionMonitor.processEvent(event)
                    await sendSessionNotification(for: event)
                }
            } catch {
                AppLog.hooks.error("Failed to start hook server: \(error.localizedDescription)")
            }
        }
    }

    func stopHookServer() {
        hookServerTask?.cancel()
        hookServerTask = nil
        hookServer.stop()
    }

    @MainActor private func sendSessionNotification(for event: SessionEvent) {
        let projectName = (event.cwd as NSString).lastPathComponent

        switch event.eventName {
        case .sessionStart:
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Started",
                    body: "Session started in \(projectName)",
                    categoryIdentifier: "SESSION_START"
                )
            }
        case .sessionEnd:
            let taskCount = sessionMonitor.recentSessions.first?.completedTaskCount ?? 0
            let duration = sessionMonitor.recentSessions.first?.durationDescription ?? ""
            let summary = taskCount > 0
                ? "Completed \(taskCount) task\(taskCount == 1 ? "" : "s") in \(duration)"
                : "Session ended after \(duration)"
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Finished",
                    body: "\(projectName) — \(summary)",
                    categoryIdentifier: "SESSION_END"
                )
            }
        default:
            break
        }
    }

    var body: some Scene {
        // Pure menu-bar agent (LSUIElement=true): stays in status bar until user quits.
        MenuBarExtra {
            Group {
                #if ENABLE_SPARKLE
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                    .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
            .onAppear {
                statusItemDriver.reassertPresentation()
            }
            .onDisappear { statusItemDriver.reassertPresentation() }
        } label: {
            // Icon only — no “额度” text on the menu-bar chip.
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            statusItemDriver.attach(statusItem)
        }
        .menuBarExtraStyle(.window)
    }

}

private func sessionPhaseColor(_ phase: ClaudeSession.Phase) -> Color {
    phase.color
}

/// The menu bar icon that reflects the overall quota status.
/// When a Claude Code session is active, shows a terminal icon with phase color.
/// Uses theme's `statusBarIconName` if set, otherwise shows status-based icons.
struct StatusBarIcon: View {
    let status: QuotaStatus
    var activeSession: ClaudeSession? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        if let session = activeSession {
            // Active session: show terminal icon with phase color
            HStack(spacing: 3) {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(sessionPhaseColor(session.phase))
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor)
            }
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        // Use theme's custom icon if provided
        if let themeIcon = theme.statusBarIconName {
            return themeIcon
        }
        // Otherwise use status-based icon
        switch status {
        case .depleted:
            return "chart.bar.xaxis"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning, .healthy:
            return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        theme.statusColor(for: status)
    }
}

// MARK: - StatusBarIcon Preview

#Preview("StatusBarIcon - All States") {
    HStack(spacing: 30) {
        VStack {
            StatusBarIcon(status: .healthy)
            Text("HEALTHY")
                .font(.caption)
                .foregroundStyle(.green)
        }
        VStack {
            StatusBarIcon(status: .warning)
            Text("WARNING")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        VStack {
            StatusBarIcon(status: .critical)
            Text("CRITICAL")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .depleted)
            Text("DEPLETED")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "cli")
            Text("CLI")
                .font(.caption)
                .foregroundStyle(CLITheme().accentPrimary)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "christmas")
            Text("CHRISTMAS")
                .font(.caption)
                .foregroundStyle(ChristmasTheme().accentPrimary)
        }
    }
    .padding(40)
    .background(Color.black)
}

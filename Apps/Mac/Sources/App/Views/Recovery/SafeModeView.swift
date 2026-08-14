import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Infrastructure

/// Safe Mode recovery actions. Hosted in the menu-bar extra and an optional window.
struct SafeModeView: View {
    let reason: SafeModeReason
    let store: CrashRecoveryStore
    var onRetryNormal: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    private var l10n: L10n { L10n.shared }

    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var confirmReset = false

    var body: some View {
        let _ = l10n.revision
        ZStack {
            MembershipPalette.backgroundGradient(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    reasonCard
                    if AppRecoveryState(launchMode: .safeMode(reason: reason)).usesReadOnlyDefaultSettings {
                        note(l10n.t("recovery.readonly_defaults"))
                    }
                    note(l10n.t("recovery.scope_note"))
                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(statusIsError ? MembershipPalette.statusDanger : MembershipPalette.statusSuccess)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                }
                .padding(16)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .environment(\.layoutDirection, l10n.language.layoutDirection)
        .environment(\.locale, l10n.language.locale)
        .alert(l10n.t("recovery.reset.title"), isPresented: $confirmReset) {
            Button(l10n.t("common.cancel"), role: .cancel) {}
            Button(l10n.t("recovery.reset.confirm"), role: .destructive) {
                performReset()
            }
        } message: {
            Text(l10n.t("recovery.reset.message"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(l10n.t("recovery.title"), systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("recovery.subtitle"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t(reasonTitleKey))
                .font(.system(size: 14, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t(reasonDetailKey))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MembershipPalette.cardFill(colorScheme, elevated: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(MembershipPalette.cardStroke(colorScheme, elevated: true), lineWidth: 1)
                )
        )
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            actionButton(title: l10n.t("recovery.action.open_logs"), systemName: "doc.text") {
                FileLogger.shared.openCurrentLogFile()
            }
            actionButton(title: l10n.t("recovery.action.restore_backup"), systemName: "clock.arrow.circlepath") {
                restoreBackup()
            }
            actionButton(title: l10n.t("recovery.action.export_settings"), systemName: "square.and.arrow.up") {
                exportSettings()
            }
            actionButton(title: l10n.t("recovery.action.reset_settings"), systemName: "trash") {
                confirmReset = true
            }
            actionButton(title: l10n.t("recovery.action.retry_normal"), systemName: "arrow.clockwise", prominent: true) {
                retryNormal()
            }
        }
    }

    private func actionButton(
        title: String,
        systemName: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 12)
                .foregroundStyle(prominent ? Color.white : theme.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(prominent ? MembershipPalette.accentPrimary : MembershipPalette.cardFill(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }

    private var reasonTitleKey: String {
        "recovery.reason.\(reason.rawValue)"
    }

    private var reasonDetailKey: String {
        "recovery.detail.\(reason.rawValue)"
    }

    private func restoreBackup() {
        do {
            try store.restoreLatestBackup()
            AppSettings.shared.reloadFromDisk()
            statusIsError = false
            statusText = l10n.t("recovery.status.restore_ok")
        } catch {
            statusIsError = true
            statusText = l10n.t("recovery.status.restore_failed")
        }
    }

    private func performReset() {
        do {
            try store.resetAppSettings()
            AppSettings.shared.reloadFromDisk()
            statusIsError = false
            statusText = l10n.t("recovery.status.reset_ok")
        } catch {
            statusIsError = true
            statusText = l10n.t("recovery.status.reset_failed")
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "smartquota-settings.json"
        panel.title = l10n.t("recovery.action.export_settings")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportAllowlistedSettings(to: url)
            statusIsError = false
            statusText = l10n.t("recovery.status.export_ok")
        } catch {
            statusIsError = true
            statusText = l10n.t("recovery.status.export_failed")
        }
    }

    private func retryNormal() {
        let mode = store.retryNormalLaunch()
        if mode == .normal {
            statusIsError = false
            statusText = l10n.t("recovery.status.retry_ok")
            onRetryNormal()
        } else {
            statusIsError = true
            statusText = l10n.t("recovery.status.retry_blocked")
        }
    }
}

@MainActor
final class SafeModeWindowController: NSObject, NSWindowDelegate {
    static let shared = SafeModeWindowController()

    private var window: NSWindow?

    func show(reason: SafeModeReason, store: CrashRecoveryStore, onRetryNormal: @escaping () -> Void) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "\(Brand.nameCN) · \(L10n.lookup("recovery.title", language: L10n.shared.language))"
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        window?.contentView = NSHostingView(
            rootView: SafeModeView(reason: reason, store: store, onRetryNormal: onRetryNormal)
                .appThemeProvider(themeModeId: AppSettings.shared.themeMode)
        )
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window must not quit the menu-bar agent.
    }
}

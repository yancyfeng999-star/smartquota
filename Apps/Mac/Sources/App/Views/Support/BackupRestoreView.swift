import SwiftUI
import Domain
import Infrastructure

struct BackupRestoreCard: View {
    let monitor: QuotaMonitor
    var backupManager: BackupManager = BackupManager(configRoot: AppIdentity.configDirectoryURL)
    var transferService: SettingsTransferService = SettingsTransferService(
        configRoot: AppIdentity.configDirectoryURL,
        store: .shared
    )
    var settingsRepository: JSONSettingsRepository = .shared

    @Environment(\.appTheme) private var theme
    @State private var showing = false
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            .decorativeGlyph()
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.backup"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Text(l10n.t("settings.backup_sub"))
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(l10n.t("common.open")) {
                showing = true
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.accentGradient))
            .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsOpenBackups)
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
        .sheet(isPresented: $showing) {
            BackupRestoreView(
                backupManager: backupManager,
                transferService: transferService,
                monitor: monitor,
                settingsRepository: settingsRepository
            )
        }
    }
}

struct BackupRestoreView: View {
    let backupManager: BackupManager
    let transferService: SettingsTransferService
    let monitor: QuotaMonitor
    var settingsRepository: JSONSettingsRepository = .shared

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var inspections: [BackupInspection] = []
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var defaultsConfirmation = DualConfirmation(action: .restoreDefaults)
    @State private var wipeConfirmation = DualConfirmation(action: .clearAllLocalData)
    @State private var showingDefaultsFirst = false
    @State private var showingDefaultsSecond = false
    @State private var showingWipeFirst = false
    @State private var showingWipeSecond = false
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            header
            if inspections.isEmpty {
                Text(l10n.t("backup.empty"))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(inspections.enumerated()), id: \.offset) { _, item in
                            backupRow(item)
                        }
                    }
                }
            }
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(statusIsError ? MembershipPalette.statusDanger : MembershipPalette.statusSuccess)
                    .fixedSize(horizontal: false, vertical: true)
            }
            dangerSection
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 540)
        .onAppear { reload() }
        .alert(l10n.t("backup.defaults.first.title"), isPresented: $showingDefaultsFirst) {
            Button(l10n.t("common.cancel"), role: .cancel) { defaultsConfirmation.cancel() }
            Button(l10n.t("backup.defaults.first.confirm")) {
                defaultsConfirmation.confirm()
            }
        } message: {
            Text(l10n.t("backup.defaults.first.message"))
        }
        .onChange(of: showingDefaultsFirst) { _, showing in
            if !showing && defaultsConfirmation.isAwaitingSecondConfirmation {
                showingDefaultsSecond = true
            }
        }
        .alert(l10n.t("backup.defaults.second.title"), isPresented: $showingDefaultsSecond) {
            Button(l10n.t("common.cancel"), role: .cancel) { defaultsConfirmation.cancel() }
            Button(l10n.t("backup.defaults.second.confirm"), role: .destructive) {
                defaultsConfirmation.confirm()
                if defaultsConfirmation.isComplete {
                    restoreDefaults()
                }
                defaultsConfirmation.cancel()
            }
        } message: {
            Text(l10n.t("backup.defaults.second.message"))
        }
        .alert(l10n.t("backup.wipe.first.title"), isPresented: $showingWipeFirst) {
            Button(l10n.t("common.cancel"), role: .cancel) { wipeConfirmation.cancel() }
            Button(l10n.t("backup.wipe.first.confirm")) {
                wipeConfirmation.confirm()
            }
        } message: {
            Text(l10n.t("backup.wipe.first.message"))
        }
        .onChange(of: showingWipeFirst) { _, showing in
            if !showing && wipeConfirmation.isAwaitingSecondConfirmation {
                showingWipeSecond = true
            }
        }
        .alert(l10n.t("backup.wipe.second.title"), isPresented: $showingWipeSecond) {
            Button(l10n.t("common.cancel"), role: .cancel) { wipeConfirmation.cancel() }
            Button(l10n.t("backup.wipe.second.confirm"), role: .destructive) {
                wipeConfirmation.confirm()
                if wipeConfirmation.isComplete {
                    clearAll()
                }
                wipeConfirmation.cancel()
            }
        } message: {
            Text(l10n.t("backup.wipe.second.message"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.t("backup.title"))
                    .font(AppTypeScale.title(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(l10n.t("common.done")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(l10n.t("backup.subtitle"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func backupRow(_ item: BackupInspection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.manifest.createdAt.formatted(date: .abbreviated, time: .standard))
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.tf("backup.meta_fmt", item.manifest.appVersion, item.manifest.schemaVersion))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            Text(item.manifest.includedFiles.joined(separator: ", "))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Text(item.checksumValid ? l10n.t("backup.checksum.ok") : l10n.tf("backup.checksum.fail_fmt", item.failureReason ?? ""))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(item.checksumValid ? MembershipPalette.statusSuccess : MembershipPalette.statusDanger)
            Button(l10n.t("backup.restore")) {
                restore(item)
            }
            .buttonStyle(.plain)
            .disabled(!item.checksumValid)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(item.checksumValid ? theme.accentPrimary : theme.textTertiary)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.backupRestore)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.cardGradient)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.glassBorder, lineWidth: 1))
        )
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("backup.danger.title"))
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Button(l10n.t("backup.defaults.action")) {
                defaultsConfirmation.cancel()
                showingDefaultsFirst = true
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(MembershipPalette.statusDanger)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.backupRestoreDefaults)
            Button(l10n.t("backup.wipe.action")) {
                wipeConfirmation.cancel()
                showingWipeFirst = true
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(MembershipPalette.statusDanger)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.backupClearAll)
        }
    }

    private func reload() {
        inspections = (try? backupManager.inspectBackups()) ?? []
    }

    private func reloadLiveSettings() {
        AppSettings.shared.reloadFromDisk()
        monitor.reloadEnablement(from: settingsRepository)
    }

    private func restore(_ item: BackupInspection) {
        do {
            try backupManager.restore(item.manifest)
            reloadLiveSettings()
            reload()
            statusIsError = false
            statusText = l10n.t("backup.restore.ok")
        } catch {
            statusIsError = true
            statusText = SupportErrorCatalog.copy(for: .backupRestoreFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    private func restoreDefaults() {
        do {
            try transferService.restoreFactoryDefaults()
            reloadLiveSettings()
            reload()
            statusIsError = false
            statusText = l10n.t("backup.defaults.ok")
        } catch {
            statusIsError = true
            statusText = l10n.t("backup.defaults.failed")
        }
    }

    private func clearAll() {
        do {
            try transferService.clearAllLocalData()
            reloadLiveSettings()
            reload()
            statusIsError = false
            statusText = l10n.t("backup.wipe.ok")
        } catch {
            statusIsError = true
            statusText = l10n.t("backup.wipe.failed")
        }
    }
}

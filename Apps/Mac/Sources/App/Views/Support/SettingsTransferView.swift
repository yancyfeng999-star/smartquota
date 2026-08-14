import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Infrastructure

struct SettingsTransferCard: View {
    var service: SettingsTransferService = SettingsTransferService(
        configRoot: AppIdentity.configDirectoryURL,
        store: .shared
    )

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
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }
            .decorativeGlyph()
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.transfer"))
                    .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Text(l10n.t("settings.transfer_sub"))
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
            .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsOpenTransfer)
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
            SettingsTransferView(service: service)
        }
    }
}

struct SettingsTransferView: View {
    let service: SettingsTransferService

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var includeEmail = false
    @State private var preview: PortableSettingsPreview?
    @State private var importPreview: SettingsImportPreview?
    @State private var pendingImportData: Data?
    @State private var importMode: SettingsImportMode = .merge
    @State private var statusText: String?
    @State private var statusIsError = false
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            header
            privacyCard
            exportSection
            importSection
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(statusIsError ? MembershipPalette.statusDanger : MembershipPalette.statusSuccess)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 540)
        .onAppear { refreshPreview() }
        .onChange(of: includeEmail) { _, _ in refreshPreview() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.t("transfer.title"))
                    .font(AppTypeScale.title(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(l10n.t("common.done")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(l10n.t("transfer.subtitle"))
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("transfer.privacy.title"))
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Text(l10n.t("transfer.privacy.body"))
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.cardGradient)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.glassBorder, lineWidth: 1))
        )
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("transfer.export.title"))
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Toggle(isOn: $includeEmail) {
                Text(l10n.t("transfer.export.include_email"))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            }
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            Text(l10n.t("transfer.export.email_note"))
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(preview.fields.prefix(40)) { field in
                            Text(field.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            Button(l10n.t("transfer.export.action")) {
                export()
            }
            .buttonStyle(.plain)
            .font(AppTypeScale.callout(theme.fontDesign))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.accentGradient))
            .supportKeyboardIdentifier(AccessibilityChrome.ID.transferExport)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("transfer.import.title"))
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            HStack {
                Button(l10n.t("transfer.import.choose")) {
                    chooseImport()
                }
                .buttonStyle(.plain)
                .font(AppTypeScale.callout(theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().stroke(theme.glassBorder, lineWidth: 1))
                .supportKeyboardIdentifier(AccessibilityChrome.ID.transferImport)
                Picker(l10n.t("transfer.import.mode"), selection: $importMode) {
                    Text(l10n.t("transfer.import.merge")).tag(SettingsImportMode.merge)
                    Text(l10n.t("transfer.import.overwrite")).tag(SettingsImportMode.overwrite)
                }
                .pickerStyle(.segmented)
            }
            if let importPreview {
                Text(l10n.tf("transfer.import.schema_fmt", importPreview.schemaVersion))
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                Text(diffSummary(importPreview.diff))
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !importPreview.diff.unknownProvidersKeptDisabled.isEmpty {
                    Text(l10n.tf(
                        "transfer.import.unknown_fmt",
                        importPreview.diff.unknownProvidersKeptDisabled.joined(separator: ", ")
                    ))
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                }
                Button(l10n.t("transfer.import.apply")) {
                    applyImport()
                }
                .buttonStyle(.plain)
                .font(AppTypeScale.callout(theme.fontDesign))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accentGradient))
            }
        }
    }

    private func diffSummary(_ diff: SettingsImportDiff) -> String {
        l10n.tf(
            "transfer.import.diff_fmt",
            diff.added.count,
            diff.changed.count,
            diff.removed.count
        )
    }

    private func refreshPreview() {
        do {
            preview = try service.makeExportPreview(includeEmail: includeEmail)
        } catch {
            preview = nil
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "smartquota-settings.json"
        panel.title = l10n.t("transfer.export.action")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.writeExport(to: url, includeEmail: includeEmail)
            statusIsError = false
            statusText = l10n.t("transfer.export.ok")
        } catch {
            statusIsError = true
            statusText = SupportErrorCatalog.copy(for: .exportFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = l10n.t("transfer.import.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            importPreview = try service.previewImport(data: data)
            pendingImportData = data
            statusText = nil
        } catch {
            pendingImportData = nil
            importPreview = nil
            statusIsError = true
            statusText = SupportErrorCatalog.copy(for: .importFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    private func applyImport() {
        guard let pendingImportData else { return }
        do {
            try service.importData(pendingImportData, mode: importMode)
            AppSettings.shared.reloadFromDisk()
            refreshPreview()
            statusIsError = false
            statusText = l10n.t("transfer.import.ok")
        } catch {
            statusIsError = true
            statusText = SupportErrorCatalog.copy(for: .importFailed, language: l10n.supportLanguage).fullMessage
        }
    }
}

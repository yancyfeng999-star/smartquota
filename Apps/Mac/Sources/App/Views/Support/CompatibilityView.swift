import SwiftUI
import AppKit
import Domain
import Infrastructure

/// Thin status view for OS, architecture, permissions, and enabled-provider CLIs.
/// Does not install third-party CLIs.
struct CompatibilityView: View {
    let report: CompatibilityReport
    var onRecheck: (() -> Void)?

    @Environment(\.appTheme) private var theme
    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t(report.isReady ? "compat.ready" : "compat.not_ready"))
                .font(.system(size: 14, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            row(
                title: l10n.t(report.minimumOSSatisfied ? "compat.os.ok" : "compat.os.fail"),
                ok: report.minimumOSSatisfied
            )
            row(
                title: l10n.tf(
                    report.supportedArchitecture ? "compat.arch.ok_fmt" : "compat.arch.fail_fmt",
                    report.architecture
                ),
                ok: report.supportedArchitecture
            )
            row(
                title: l10n.t(report.appDirectoryWritable ? "compat.writable.ok" : "compat.writable.fail"),
                ok: report.appDirectoryWritable
            )
            row(
                title: l10n.t(report.keychainAvailable ? "compat.keychain.ok" : "compat.keychain.fail"),
                ok: report.keychainAvailable
            )
            row(
                title: notificationTitle,
                ok: report.notificationStatus.isGranted
            )

            ForEach(report.providerChecks.values.sorted(by: { $0.providerId < $1.providerId }), id: \.providerId) { check in
                if let cliName = check.cliName, !check.cliInstalled {
                    row(
                        title: l10n.tf("compat.cli.missing_fmt", check.providerId, cliName),
                        ok: false
                    )
                    Text(l10n.tf("compat.cli.install_hint_fmt", cliName))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                    Text(l10n.tf("compat.cli.login_hint_fmt", cliName))
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if report.issues.contains(where: { $0.kind == .notifications }) {
                Button(l10n.t("compat.action.open_settings")) {
                    openSystemSettings(report.issues.first { $0.kind == .notifications }?.systemSettingsPane)
                }
                .buttonStyle(.plain)
            }

            if let onRecheck {
                Button(l10n.t("compat.action.recheck"), action: onRecheck)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationTitle: String {
        switch report.notificationStatus {
        case .authorized, .provisional:
            return l10n.t("compat.notifications.ok")
        case .denied:
            return l10n.t("compat.notifications.denied")
        case .notDetermined:
            return l10n.t("compat.notifications.not_determined")
        }
    }

    private func row(title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(ok ? MembershipPalette.statusSuccess : MembershipPalette.statusDanger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSystemSettings(_ pane: String?) {
        guard let pane, let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }
}

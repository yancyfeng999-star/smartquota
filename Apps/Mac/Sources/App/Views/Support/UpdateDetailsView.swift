import AppKit
import SwiftUI
import Domain
import Infrastructure

/// Settings update card: check first, show notes, then the user confirms download/install.
struct UpdateDetailsView: View {
    var checker: GitHubReleaseChecker = GitHubReleaseChecker()
    var makeDownloader: () -> ReleaseDownloader = { ReleaseDownloader() }
    var currentVersionString: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    var runningOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var terminateApp: () -> Void = { NSApp.terminate(nil) }

    @Environment(\.appTheme) private var theme
    @State private var isChecking = false
    @State private var isInstalling = false
    @State private var downloadProgress: Double?
    @State private var assessment: ManualUpdateAssessment?
    @State private var statusText: String?
    @State private var downloader: ReleaseDownloader?
    @State private var localInstaller: URL?

    private var l10n: L10n { L10n.shared }

    var body: some View {
        let _ = l10n.revision
        VStack(alignment: .leading, spacing: 8) {
            header
            if isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.t("settings.updates_installing"))
                        .font(AppTypeScale.caption(theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .untruncatedSupportText()
                }
            } else if let progress = downloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0.3, green: 0.7, blue: 0.4))
                    Text(l10n.tf("settings.updates_progress_fmt", Int((progress * 100).rounded())))
                        .font(AppTypeScale.caption(theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .monospacedDigit()
                    Button(l10n.t("settings.updates_cancel")) {
                        downloader?.cancel()
                    }
                    .buttonStyle(.plain)
                    .font(AppTypeScale.caption(theme.fontDesign).weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
                    .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsCancelUpdate)
                }
            }

            if let assessment {
                details(for: assessment)
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

    private var header: some View {
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
            .decorativeGlyph()

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("settings.updates"))
                    .font(AppTypeScale.headline(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                Text(subtitle)
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(highlightSubtitle ? theme.accentPrimary : theme.textTertiary)
                    .untruncatedSupportText()
            }

            Spacer(minLength: 8)

            Button {
                Task { await check() }
            } label: {
                HStack(spacing: 4) {
                    if isChecking && downloadProgress == nil && !isInstalling {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    }
                    Text(checkButtonTitle)
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
            .disabled(isChecking || isInstalling || downloadProgress != nil)
            .opacity(isChecking ? 0.7 : 1)
            .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsCheckUpdates)
        }
    }

    @ViewBuilder
    private func details(for assessment: ManualUpdateAssessment) -> some View {
        let snapshot = UpdateDetailsSnapshot.make(assessment: assessment)
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.tf("settings.updates_current_fmt", snapshot.currentVersion))
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .untruncatedSupportText()
            if let latest = snapshot.latestVersion {
                Text(l10n.tf("settings.updates_latest_fmt", latest))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .untruncatedSupportText()
            }
            if let date = snapshot.publishedAt {
                Text(l10n.tf("settings.updates_published_fmt", Self.dateText(date, language: l10n.language)))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .untruncatedSupportText()
            }
            if let size = snapshot.assetSize {
                Text(l10n.tf("settings.updates_size_fmt", Self.sizeText(size)))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .untruncatedSupportText()
            }
            if let minOS = snapshot.minimumOSLabel {
                Text(l10n.tf("settings.updates_min_os_fmt", minOS))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .untruncatedSupportText()
            }
            if !snapshot.releaseNotes.isEmpty {
                Text(l10n.t("settings.updates_notes"))
                    .font(AppTypeScale.caption(theme.fontDesign).weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Text(snapshot.releaseNotes)
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                    .textSelection(.enabled)
            }
            Text(l10n.t("settings.updates_pkg_note"))
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .untruncatedSupportText()
            Text(l10n.t("settings.updates_signing_note"))
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .untruncatedSupportText()

            if case .unsupportedOS(_, _, let required, let running) = assessment {
                Text(
                    l10n.tf(
                        "settings.updates_os_blocked_fmt",
                        OSVersionOrdering.displayString(required),
                        OSVersionOrdering.displayString(running)
                    )
                )
                .font(AppTypeScale.caption(theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .untruncatedSupportText()
            }

            if snapshot.shouldOpenReleasePage {
                Text(l10n.t("settings.updates_asset_error"))
                    .font(AppTypeScale.caption(theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .untruncatedSupportText()
                if let page = assessment.latestRelease?.htmlURL {
                    Button(l10n.t("settings.updates_open_release")) {
                        openURL(page)
                        statusText = l10n.t("settings.updates_open_page")
                    }
                    .buttonStyle(.plain)
                    .font(AppTypeScale.callout(theme.fontDesign))
                    .foregroundStyle(theme.accentPrimary)
                    .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsOpenRelease)
                }
            } else if snapshot.allowsDownload, downloadProgress == nil, !isInstalling {
                Button(l10n.t("settings.updates_confirm_install")) {
                    Task { await downloadAndInstall(assessment) }
                }
                .buttonStyle(.plain)
                .font(AppTypeScale.callout(theme.fontDesign))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(theme.accentGradient))
                .supportKeyboardIdentifier(AccessibilityChrome.ID.settingsDownloadUpdate)
            }
        }
    }

    private var subtitle: String {
        if let statusText { return statusText }
        return l10n.tf("settings.updates_version_fmt", currentVersionString)
    }

    private var highlightSubtitle: Bool {
        if case .available = assessment { return true }
        return false
    }

    private var checkButtonTitle: String {
        if isInstalling { return l10n.t("settings.updates_installing_btn") }
        if downloadProgress != nil { return l10n.t("settings.updates_downloading_btn") }
        if isChecking { return l10n.t("settings.updates_checking") }
        return l10n.t("settings.updates_check")
    }

    @MainActor
    private func check() async {
        isChecking = true
        statusText = nil
        assessment = nil
        localInstaller = nil
        downloadProgress = nil
        isInstalling = false
        defer { isChecking = false }

        do {
            let result = try await checker.check(currentVersionString: currentVersionString)
            switch result {
            case .upToDate(let current):
                assessment = .upToDate(current: current)
                statusText = l10n.tf("settings.updates_up_to_date", current.description)
            case .updateAvailable(let current, let latest):
                let decided = ManualUpdateEvaluator.assess(
                    current: current,
                    latest: latest,
                    runningOS: runningOS
                )
                assessment = decided
                switch decided {
                case .available(_, let release):
                    statusText = l10n.tf(
                        "settings.updates_available_fmt",
                        release.version.description,
                        current.description
                    )
                case .unsupportedOS(_, _, let required, let running):
                    statusText = l10n.tf(
                        "settings.updates_os_blocked_fmt",
                        OSVersionOrdering.displayString(required),
                        OSVersionOrdering.displayString(running)
                    )
                case .missingAsset, .missingChecksum:
                    statusText = l10n.t("settings.updates_asset_error")
                case .upToDate(let current):
                    statusText = l10n.tf("settings.updates_up_to_date", current.description)
                }
            }
        } catch let error as ManualUpdateError {
            statusText = message(for: error)
        } catch {
            statusText = SupportErrorCatalog.copy(for: .updateCheckFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    @MainActor
    private func downloadAndInstall(_ assessment: ManualUpdateAssessment) async {
        guard case .available(let current, let latest) = assessment else { return }
        guard latest.version > current else {
            statusText = l10n.t("settings.updates_not_newer")
            return
        }
        guard let remote = ReleaseDownloader.installerDownloadURL(from: latest) else {
            openURL(latest.htmlURL)
            statusText = l10n.t("settings.updates_asset_error")
            return
        }

        let worker = makeDownloader()
        downloader = worker
        downloadProgress = 0
        statusText = l10n.t("settings.updates_downloading")
        do {
            let file = try await worker.download(release: latest) { fraction in
                Task { @MainActor in
                    downloadProgress = fraction
                    statusText = l10n.tf(
                        "settings.updates_progress_fmt",
                        Int((fraction * 100).rounded())
                    )
                }
            }
            localInstaller = file
            downloadProgress = nil
            await install(file, current: current, latest: latest, remote: remote)
        } catch let error as ManualUpdateError {
            downloadProgress = nil
            statusText = message(for: error)
        } catch {
            downloadProgress = nil
            statusText = SupportErrorCatalog.copy(for: .updateCheckFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    @MainActor
    private func install(_ file: URL, current: AppVersion, latest: RemoteRelease, remote: URL) async {
        if file.pathExtension.lowercased() == "pkg" {
            isInstalling = true
            statusText = l10n.t("settings.updates_installing")
            do {
                let result = try await SilentPkgInstaller.installAndRelaunch(
                    pkgURL: file,
                    currentVersion: current
                )
                // Replace runs after quit; re-read the live bundle so we never claim it is already new.
                let live = InstalledAppVersion.read(fromAppBundle: result.installedAppURL)
                    ?? InstalledAppVersion.read(from: .main)
                if live == result.incomingVersion {
                    statusText = l10n.tf("settings.updates_up_to_date", result.incomingVersion.description)
                    isInstalling = false
                    return
                }
                statusText = l10n.t("settings.updates_relaunching")
                try? await Task.sleep(nanoseconds: 250_000_000)
                terminateApp()
            } catch let error as ManualUpdateError {
                isInstalling = false
                statusText = message(for: error)
            } catch {
                isInstalling = false
                statusText = SupportErrorCatalog.copy(for: .updateCheckFailed, language: l10n.supportLanguage).fullMessage
            }
            return
        }

        _ = remote
        _ = latest
        statusText = l10n.t("settings.updates_opening")
        openURL(file)
        statusText = l10n.t("settings.updates_opened")
    }

    private func message(for error: ManualUpdateError) -> String {
        switch error {
        case .downloadTimeout:
            return l10n.t("settings.updates_timeout")
        case .downloadCancelled:
            return l10n.t("settings.updates_cancelled")
        case .missingReleaseAsset, .missingChecksum:
            return l10n.t("settings.updates_asset_error")
        case .targetNotNewer:
            return l10n.t("settings.updates_not_newer")
        case .unsupportedOperatingSystem(let required, let current):
            return l10n.tf("settings.updates_os_blocked_fmt", required, current)
        case .install:
            return l10n.t("settings.updates_install_failed")
        case .noMacReleaseFound:
            return l10n.t("settings.updates_failed_none")
        case .invalidCurrentVersion:
            return l10n.t("settings.updates_failed_version")
        default:
            return SupportErrorCatalog.copy(for: .updateCheckFailed, language: l10n.supportLanguage).fullMessage
        }
    }

    private static func dateText(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}

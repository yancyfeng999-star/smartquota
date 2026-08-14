import Foundation

public struct AccessibilityIconSpec: Equatable, Sendable, Identifiable {
    public let id: String
    public let labelKey: String
    public let hintKey: String
    public let valueKeys: [String]

    public init(id: String, labelKey: String, hintKey: String, valueKeys: [String]) {
        self.id = id
        self.labelKey = labelKey
        self.hintKey = hintKey
        self.valueKeys = valueKeys
    }

    public var allKeys: [String] {
        [labelKey, hintKey] + valueKeys
    }
}

public struct AccessibilityKeyboardControl: Equatable, Sendable, Identifiable {
    public let id: String
    public let shortcut: String?

    public init(id: String, shortcut: String?) {
        self.id = id
        self.shortcut = shortcut
    }
}

/// VoiceOver labels / hints / values and keyboard-relevant identifiers.
public enum AccessibilityChrome: Sendable {
    public enum ID {
        public static let menuRefresh = "menu.refresh"
        public static let menuRefreshCurrent = "menu.refresh.current"
        public static let menuRefreshCancel = "menu.refresh.cancel"
        public static let menuPin = "menu.pin"
        public static let menuHelp = "menu.help"
        public static let menuClosePanel = "menu.close_panel"
        public static let menuSettings = "menu.settings"
        public static let menuDashboard = "menu.dashboard"
        public static let menuQuit = "menu.quit"
        public static let menuShare = "menu.share"
        public static let settingsBack = "settings.back"
        public static let settingsOpenDiagnostics = "settings.open_diagnostics"
        public static let settingsOpenTransfer = "settings.open_transfer"
        public static let settingsOpenBackups = "settings.open_backups"
        public static let settingsOpenHelp = "settings.open_help"
        public static let settingsOpenLogs = "settings.open_logs"
        public static let settingsCheckUpdates = "settings.check_updates"
        public static let settingsDownloadUpdate = "settings.download_update"
        public static let settingsCancelUpdate = "settings.cancel_update"
        public static let settingsOpenRelease = "settings.open_release"
        public static let helpOpenLogs = "help.open_logs"
        public static let helpOpenDiagnostics = "help.open_diagnostics"
        public static let helpOpenReleases = "help.open_releases"
        public static let helpOpenUserGuide = "help.open_user_guide"
        public static let helpBack = "help.back"
        public static let diagRun = "diag.run"
        public static let diagCopy = "diag.copy"
        public static let transferExport = "transfer.export"
        public static let transferImport = "transfer.import"
        public static let backupRestore = "backup.restore"
        public static let backupRestoreDefaults = "backup.restore_defaults"
        public static let backupClearAll = "backup.clear_all"
        public static let recoveryExport = "recovery.export"
        public static let recoveryReset = "recovery.reset"
        public static let accountDelete = "account.delete"

        public static let decorativeAppLogo = "decorative.app_logo"
        public static let decorativeCardIcon = "decorative.card_icon"
    }

    public static let iconButtons: [AccessibilityIconSpec] = [
        AccessibilityIconSpec(
            id: ID.menuRefresh,
            labelKey: "a11y.refresh.label",
            hintKey: "a11y.refresh.hint",
            valueKeys: ["a11y.refresh.value.idle", "a11y.refresh.value.running"]
        ),
        AccessibilityIconSpec(
            id: ID.menuRefreshCurrent,
            labelKey: "a11y.refresh.current.label",
            hintKey: "a11y.refresh.current.hint",
            valueKeys: ["a11y.refresh.value.idle", "a11y.refresh.value.running"]
        ),
        AccessibilityIconSpec(
            id: ID.menuRefreshCancel,
            labelKey: "a11y.refresh.cancel.label",
            hintKey: "a11y.refresh.cancel.hint",
            valueKeys: ["a11y.refresh.cancel.value"]
        ),
        AccessibilityIconSpec(
            id: ID.menuPin,
            labelKey: "a11y.pin.label",
            hintKey: "a11y.pin.hint",
            valueKeys: ["a11y.pin.value.on", "a11y.pin.value.off"]
        ),
        AccessibilityIconSpec(
            id: ID.menuHelp,
            labelKey: "a11y.help.label",
            hintKey: "a11y.help.hint",
            valueKeys: ["a11y.help.value"]
        ),
        AccessibilityIconSpec(
            id: ID.menuClosePanel,
            labelKey: "a11y.close_panel.label",
            hintKey: "a11y.close_panel.hint",
            valueKeys: ["a11y.close_panel.value"]
        ),
        AccessibilityIconSpec(
            id: ID.menuSettings,
            labelKey: "a11y.settings_icon.label",
            hintKey: "a11y.settings_icon.hint",
            valueKeys: ["a11y.settings_icon.value"]
        ),
        AccessibilityIconSpec(
            id: ID.menuShare,
            labelKey: "a11y.share.label",
            hintKey: "a11y.share.hint",
            valueKeys: ["a11y.share.value"]
        ),
        AccessibilityIconSpec(
            id: ID.settingsBack,
            labelKey: "a11y.back.label",
            hintKey: "a11y.back.hint",
            valueKeys: ["a11y.back.value"]
        ),
    ]

    public static let decorativeElementIds: [String] = [
        ID.decorativeAppLogo,
        ID.decorativeCardIcon,
    ]

    public static let keyboardControls: [AccessibilityKeyboardControl] = [
        AccessibilityKeyboardControl(id: ID.menuRefresh, shortcut: "r"),
        AccessibilityKeyboardControl(id: ID.menuRefreshCurrent, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.menuRefreshCancel, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.menuDashboard, shortcut: "d"),
        AccessibilityKeyboardControl(id: ID.menuSettings, shortcut: ","),
        AccessibilityKeyboardControl(id: ID.menuHelp, shortcut: "?"),
        AccessibilityKeyboardControl(id: ID.settingsBack, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsOpenDiagnostics, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsOpenTransfer, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsOpenBackups, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsOpenHelp, shortcut: "?"),
        AccessibilityKeyboardControl(id: ID.settingsOpenLogs, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsCheckUpdates, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsDownloadUpdate, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsCancelUpdate, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.settingsOpenRelease, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.helpOpenLogs, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.helpOpenDiagnostics, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.helpOpenReleases, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.helpOpenUserGuide, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.helpBack, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.diagRun, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.transferExport, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.transferImport, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.backupRestore, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.backupRestoreDefaults, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.backupClearAll, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.recoveryExport, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.recoveryReset, shortcut: nil),
        AccessibilityKeyboardControl(id: ID.accountDelete, shortcut: nil),
    ]

    public static func spec(id: String) -> AccessibilityIconSpec? {
        iconButtons.first { $0.id == id }
    }

    public static var requiredStringKeys: [String] {
        var keys = Set(iconButtons.flatMap(\.allKeys))
        keys.insert("status.info")
        keys.insert("status.severity.warning")
        return keys.sorted()
    }
}

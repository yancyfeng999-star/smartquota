import Foundation

public enum CompatibilityOSPolicy: Sendable {
    public static let minimumMajorVersion = 15

    public static func isSatisfied(majorVersion: Int) -> Bool {
        majorVersion >= minimumMajorVersion
    }
}

public enum CompatibilityArchitecture: Sendable {
    public static let supported: Set<String> = ["arm64", "x86_64"]

    public static func isSupported(_ architecture: String) -> Bool {
        supported.contains(architecture)
    }
}

public enum CompatibilityCheckKind: String, Codable, Sendable {
    case operatingSystem
    case architecture
    case appWritable
    case keychain
    case notifications
    case providerCLI
}

public enum CompatibilitySeverity: String, Codable, Sendable {
    case ok
    case warning
    case error
}

public enum CompatibilityNotificationStatus: String, Codable, Sendable {
    case authorized
    case denied
    case notDetermined
    case provisional

    public var isGranted: Bool {
        self == .authorized || self == .provisional
    }
}

public enum CompatibilityAction: String, Codable, Sendable {
    case none
    case installOrSignInCLI
    case openSystemSettingsNotifications
    case openSystemSettingsPrivacy

    /// Compatibility checks never install a third-party CLI.
    public var installsThirdPartyCLI: Bool { false }
}

public enum ProviderExternalDependency: Sendable {
    public static func cliName(for providerId: String) -> String? {
        switch providerId {
        case "claude": "claude"
        case "codex": "codex"
        case "gemini": "gemini"
        case "kimi": "kimi"
        case "ampcode": "amp"
        case "kiro": "kiro-cli"
        case "omp": "omp"
        case "opencode-go": "opencode"
        default: nil
        }
    }
}

public struct ProviderCompatibility: Codable, Equatable, Sendable {
    public let providerId: String
    public let enabled: Bool
    public let cliName: String?
    public let cliInstalled: Bool
    public let suggestedAction: CompatibilityAction

    public init(
        providerId: String,
        enabled: Bool,
        cliName: String?,
        cliInstalled: Bool,
        suggestedAction: CompatibilityAction
    ) {
        self.providerId = providerId
        self.enabled = enabled
        self.cliName = cliName
        self.cliInstalled = cliInstalled
        self.suggestedAction = suggestedAction
    }
}

public struct CompatibilityIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: CompatibilityCheckKind
    public let severity: CompatibilitySeverity
    public let code: String
    public let permissionName: String?
    public let systemSettingsPane: String?
    public let relatedProviderId: String?

    public init(
        id: String,
        kind: CompatibilityCheckKind,
        severity: CompatibilitySeverity,
        code: String,
        permissionName: String? = nil,
        systemSettingsPane: String? = nil,
        relatedProviderId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.code = code
        self.permissionName = permissionName
        self.systemSettingsPane = systemSettingsPane
        self.relatedProviderId = relatedProviderId
    }

    public var titleContainsUnknownError: Bool {
        code.localizedCaseInsensitiveContains("unknown error")
            || code.localizedCaseInsensitiveContains("unknown") && code.hasSuffix("error")
    }

    public static func unsupportedOS() -> CompatibilityIssue {
        CompatibilityIssue(
            id: "os",
            kind: .operatingSystem,
            severity: .error,
            code: "compat.os.unsupported"
        )
    }

    public static func unsupportedArchitecture(_ architecture: String) -> CompatibilityIssue {
        CompatibilityIssue(
            id: "arch",
            kind: .architecture,
            severity: .error,
            code: "compat.arch.unsupported"
        )
    }

    public static func appDirectoryNotWritable() -> CompatibilityIssue {
        CompatibilityIssue(
            id: "writable",
            kind: .appWritable,
            severity: .error,
            code: "compat.writable.fail"
        )
    }

    public static func keychainUnavailable() -> CompatibilityIssue {
        CompatibilityIssue(
            id: "keychain",
            kind: .keychain,
            severity: .warning,
            code: "compat.keychain.fail",
            permissionName: "Keychain",
            systemSettingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy"
        )
    }

    public static func notificationDenied() -> CompatibilityIssue {
        CompatibilityIssue(
            id: "notifications",
            kind: .notifications,
            severity: .warning,
            code: "compat.notifications.denied",
            permissionName: "Notifications",
            systemSettingsPane: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    public static func notificationNotDetermined() -> CompatibilityIssue {
        CompatibilityIssue(
            id: "notifications",
            kind: .notifications,
            severity: .warning,
            code: "compat.notifications.not_determined",
            permissionName: "Notifications",
            systemSettingsPane: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    public static func missingCLI(providerId: String, cliName: String) -> CompatibilityIssue {
        CompatibilityIssue(
            id: "cli.\(providerId)",
            kind: .providerCLI,
            severity: .warning,
            code: "compat.cli.missing",
            relatedProviderId: providerId
        )
    }
}

public struct CompatibilityReport: Codable, Equatable, Sendable {
    public let minimumOSSatisfied: Bool
    public let architecture: String
    public let supportedArchitecture: Bool
    public let appDirectoryWritable: Bool
    public let keychainAvailable: Bool
    public let providerChecks: [String: ProviderCompatibility]
    public let notificationStatus: CompatibilityNotificationStatus
    public let issues: [CompatibilityIssue]

    public init(
        minimumOSSatisfied: Bool,
        architecture: String,
        supportedArchitecture: Bool,
        appDirectoryWritable: Bool,
        keychainAvailable: Bool,
        providerChecks: [String: ProviderCompatibility],
        notificationStatus: CompatibilityNotificationStatus,
        issues: [CompatibilityIssue]
    ) {
        self.minimumOSSatisfied = minimumOSSatisfied
        self.supportedArchitecture = supportedArchitecture
        self.architecture = architecture
        self.appDirectoryWritable = appDirectoryWritable
        self.keychainAvailable = keychainAvailable
        self.providerChecks = providerChecks
        self.notificationStatus = notificationStatus
        self.issues = issues
    }

    /// System can run 智额. Missing CLI or a denied permission is not “ready”.
    public var isReady: Bool {
        minimumOSSatisfied && supportedArchitecture && appDirectoryWritable
    }

    public var hasActionableIssues: Bool {
        !issues.filter { $0.severity != .ok }.isEmpty
    }

    public static func make(
        minimumOSSatisfied: Bool,
        architecture: String,
        supportedArchitecture: Bool,
        appDirectoryWritable: Bool,
        keychainAvailable: Bool,
        notificationStatus: CompatibilityNotificationStatus,
        providerChecks: [String: ProviderCompatibility]
    ) -> CompatibilityReport {
        var issues: [CompatibilityIssue] = []
        if !minimumOSSatisfied {
            issues.append(.unsupportedOS())
        }
        if !supportedArchitecture {
            issues.append(.unsupportedArchitecture(architecture))
        }
        if !appDirectoryWritable {
            issues.append(.appDirectoryNotWritable())
        }
        if !keychainAvailable {
            issues.append(.keychainUnavailable())
        }
        switch notificationStatus {
        case .authorized, .provisional:
            break
        case .denied:
            issues.append(.notificationDenied())
        case .notDetermined:
            issues.append(.notificationNotDetermined())
        }
        for check in providerChecks.values where check.enabled {
            if let cliName = check.cliName, !check.cliInstalled {
                issues.append(.missingCLI(providerId: check.providerId, cliName: cliName))
            }
        }
        return CompatibilityReport(
            minimumOSSatisfied: minimumOSSatisfied,
            architecture: architecture,
            supportedArchitecture: supportedArchitecture,
            appDirectoryWritable: appDirectoryWritable,
            keychainAvailable: keychainAvailable,
            providerChecks: providerChecks,
            notificationStatus: notificationStatus,
            issues: issues
        )
    }
}

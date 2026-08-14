import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable {
    case ok
    case info
    case warning
    case error
}

public enum DiagnosticCheckKind: String, Codable, Sendable {
    case operatingSystem
    case architecture
    case providerEnabled
    case cliInstalled
    case credentialAvailable
    case keychainAccess
    case networkReachability
    case providerEndpoint
    case cacheFreshness
    case notificationPermission
    case appWritable
    case configurationIntegrity
}

public enum DiagnosticAction: String, Codable, Sendable {
    case none
    case openConfiguration
    case openHelp
    case openDashboard
    case retry
    case openLogs
    case openSystemSettings
}

public enum DiagnosticCode: Sendable {
    public static let osUnsupported = "diag.os.unsupported"
    public static let archUnsupported = "diag.arch.unsupported"
    public static let writableFail = "diag.writable.fail"
    public static let keychainFail = "diag.keychain.fail"
    public static let notificationsDenied = "diag.notifications.denied"
    public static let notificationsNotDetermined = "diag.notifications.not_determined"
    public static let configCorrupt = "diag.config.corrupt"
    public static let configMissing = "diag.config.missing"
    public static let cliMissing = "diag.cli.missing"
    public static let notLoggedIn = "diag.credential.not_logged_in"
    public static let missingKey = "diag.credential.missing_key"
    public static let networkFail = "diag.network.fail"
    public static let serviceRejected = "diag.endpoint.rejected"
    public static let cacheExpired = "diag.cache.expired"
    public static let providerDisabled = "diag.provider.disabled"
}

public enum DiagnosticCredentialKind: String, Codable, Sendable {
    case available
    case missingKey
    case notLoggedIn
}

public enum DiagnosticNetworkKind: String, Codable, Sendable {
    case reachable
    case unreachable
}

public enum DiagnosticEndpointKind: String, Codable, Sendable {
    case valid
    case serviceRejected
    case skipped
}

public enum DiagnosticCacheKind: String, Codable, Sendable {
    case fresh
    case expired
    case missing
}

public enum DiagnosticConfigIntegrity: String, Codable, Sendable {
    case ok
    case missing
    case corrupt
}

public struct DiagnosticProviderInspection: Sendable, Equatable {
    public var enabled: Bool
    public var credential: DiagnosticCredentialKind
    public var network: DiagnosticNetworkKind
    public var endpoint: DiagnosticEndpointKind
    public var cache: DiagnosticCacheKind
    public var detailHint: String?

    public init(
        enabled: Bool,
        credential: DiagnosticCredentialKind,
        network: DiagnosticNetworkKind,
        endpoint: DiagnosticEndpointKind,
        cache: DiagnosticCacheKind,
        detailHint: String? = nil
    ) {
        self.enabled = enabled
        self.credential = credential
        self.network = network
        self.endpoint = endpoint
        self.cache = cache
        self.detailHint = detailHint
    }

    public static func healthy(enabled: Bool = true) -> DiagnosticProviderInspection {
        DiagnosticProviderInspection(
            enabled: enabled,
            credential: .available,
            network: .reachable,
            endpoint: .valid,
            cache: .fresh
        )
    }
}

public struct DiagnosticResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerId: String?
    public let kind: DiagnosticCheckKind
    public let severity: DiagnosticSeverity
    public let title: String
    public let detail: String
    public let suggestedAction: String?
    public let checkedAt: Date
    public let code: String

    public init(
        id: String,
        providerId: String?,
        kind: DiagnosticCheckKind,
        severity: DiagnosticSeverity,
        title: String,
        detail: String,
        suggestedAction: String?,
        checkedAt: Date,
        code: String = ""
    ) {
        self.id = id
        self.providerId = providerId
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestedAction = suggestedAction
        self.checkedAt = checkedAt
        self.code = code
    }

    public var action: DiagnosticAction {
        DiagnosticAction(rawValue: suggestedAction ?? "") ?? .none
    }

    public var actions: [DiagnosticAction] {
        DiagnosticActionSet.actions(kind: kind, severity: severity, code: code)
    }
}

public enum DiagnosticActionSet: Sendable {
    public static func actions(
        kind: DiagnosticCheckKind,
        severity: DiagnosticSeverity,
        code: String
    ) -> [DiagnosticAction] {
        if severity == .ok || severity == .info {
            return []
        }
        switch kind {
        case .operatingSystem, .architecture:
            return [.openHelp]
        case .appWritable, .configurationIntegrity:
            return [.openLogs]
        case .keychainAccess, .notificationPermission:
            return [.openSystemSettings]
        case .cliInstalled:
            return [.openConfiguration, .openHelp]
        case .credentialAvailable:
            if code == DiagnosticCode.missingKey {
                return [.openConfiguration, .openHelp]
            }
            return [.openConfiguration, .openDashboard]
        case .networkReachability:
            return [.retry, .openLogs]
        case .providerEndpoint:
            return [.openDashboard, .retry]
        case .cacheFreshness:
            return [.retry]
        case .providerEnabled:
            return [.openConfiguration]
        }
    }

    public static func primary(
        kind: DiagnosticCheckKind,
        severity: DiagnosticSeverity,
        code: String
    ) -> String? {
        let list = actions(kind: kind, severity: severity, code: code)
        return list.first?.rawValue
    }
}

public enum DiagnosticPrivacy: Sendable {
    public static func displayPath(_ raw: String, homeDirectory: String? = nil) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }
        if let home = homeDirectory, !home.isEmpty, value.hasPrefix(home) {
            return "~" + value.dropFirst(home.count)
        }
        if value.hasPrefix("/Users/") || value.hasPrefix("/home/") {
            let comps = (value as NSString).pathComponents
            if comps.count >= 3 {
                let rest = comps.dropFirst(3)
                if rest.isEmpty { return "~" }
                return "~/" + rest.joined(separator: "/")
            }
        }
        if value.contains("/"), !value.hasPrefix("~") {
            return (value as NSString).lastPathComponent
        }
        return value
    }

    public static func maskEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return "***" }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        guard let first = local.first else { return "***@\(domain)" }
        return "\(first)***@\(domain)"
    }

    public static func sanitize(_ text: String, homeDirectory: String? = nil) -> String {
        var result = text
        result = redactSecrets(result)
        result = redactEmails(result)
        result = redactPaths(result, homeDirectory: homeDirectory)
        return result
    }

    public static func redactSecrets(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (#"sk-[A-Za-z0-9_\-]{8,}"#, "sk-***"),
            (#"ghp_[A-Za-z0-9]{8,}"#, "ghp_***"),
            (#"Bearer\s+[A-Za-z0-9._\-+=/]+"#, "Bearer ***"),
            (#"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, "eyJ***"),
            (#"(?i)(cookie|set-cookie)\s*[:=]\s*\S+"#, "$1=***"),
            (#"(?i)(access_token|refresh_token|api[_-]?key|authorization)\s*[:=]\s*\S+"#, "$1=***"),
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: template
                )
            }
        }
        return result
    }

    public static func containsForbiddenPayload(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("sk-") && lowered.contains("sk-***") == false && text.contains("sk-***") == false {
            if text.range(of: #"sk-[A-Za-z0-9_\-]{8,}"#, options: .regularExpression) != nil {
                return true
            }
        }
        if lowered.contains("bearer ") && !lowered.contains("bearer ***") {
            return true
        }
        if text.contains("eyJ"), text.contains(".") {
            return true
        }
        if text.contains("@"), text.range(of: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if text.hasPrefix("/Users/") || text.contains("/Users/") || text.hasPrefix("/home/") {
            return true
        }
        return false
    }

    private static func redactEmails(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let email = ns.substring(with: match.range)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: maskEmail(email))
            }
        }
        return result
    }

    private static func redactPaths(_ text: String, homeDirectory: String?) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(file://)?(/Users/[^/\s]+|/home/[^/\s]+)(/[^\s]*)?"#
        ) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let raw = ns.substring(with: match.range)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: displayPath(raw, homeDirectory: homeDirectory))
            }
        }
        return result
    }
}

public struct DiagnosticSummary: Equatable, Sendable {
    public let appVersion: String
    public let osVersion: String
    public let architecture: String
    public let text: String

    public init(appVersion: String, osVersion: String, architecture: String, text: String) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.architecture = architecture
        self.text = text
    }

    public static func make(
        appVersion: String,
        osVersion: String,
        architecture: String,
        results: [DiagnosticResult]
    ) -> DiagnosticSummary {
        var lines: [String] = [
            "Version: \(appVersion)",
            "OS: \(osVersion)",
            "Arch: \(architecture)",
        ]
        for result in results {
            var parts = [result.kind.rawValue, result.severity.rawValue]
            if let providerId = result.providerId, !providerId.isEmpty {
                parts.append(providerId)
            }
            if !result.code.isEmpty {
                parts.append(result.code)
            }
            lines.append(parts.joined(separator: " "))
        }
        return DiagnosticSummary(
            appVersion: appVersion,
            osVersion: osVersion,
            architecture: architecture,
            text: lines.joined(separator: "\n")
        )
    }
}

public protocol DiagnosticsServicing: Sendable {
    func runAll() async -> [DiagnosticResult]
    func run(providerId: String) async -> [DiagnosticResult]
    func retry(_ result: DiagnosticResult) async -> DiagnosticResult
}

public enum DiagnosticClassification: Sendable {
    public static func credential(
        providerId: String,
        available: Bool,
        lastError: Error?
    ) -> DiagnosticCredentialKind {
        if let probe = lastError as? ProbeError {
            switch probe {
            case .authenticationRequired, .sessionExpired:
                return .notLoggedIn
            default:
                break
            }
        }
        if available { return .available }
        if ProviderExternalDependency.cliName(for: providerId) != nil {
            return .notLoggedIn
        }
        return .missingKey
    }

    public static func endpoint(lastError: Error?, snapshot: UsageSnapshot?) -> DiagnosticEndpointKind {
        if let probe = lastError as? ProbeError {
            switch probe {
            case .rateLimited, .subscriptionRequired:
                return .serviceRejected
            case .authenticationRequired, .sessionExpired, .cliNotFound:
                return .skipped
            case .timeout:
                return .skipped
            case .parseFailed, .executionFailed, .noData, .updateRequired, .folderTrustRequired:
                return .serviceRejected
            }
        }
        if lastError != nil { return .serviceRejected }
        if snapshot != nil { return .valid }
        return .skipped
    }

    public static func cache(snapshot: UsageSnapshot?) -> DiagnosticCacheKind {
        guard let snapshot else { return .missing }
        return snapshot.isStale ? .expired : .fresh
    }

    public static func network(lastError: Error?, reachable: Bool) -> DiagnosticNetworkKind {
        if !reachable { return .unreachable }
        if let probe = lastError as? ProbeError {
            switch probe {
            case .timeout:
                return .unreachable
            case .executionFailed(let reason):
                let lowered = reason.lowercased()
                if lowered.contains("offline")
                    || lowered.contains("network")
                    || lowered.contains("internet")
                    || lowered.contains("could not connect")
                    || lowered.contains("not connected")
                {
                    return .unreachable
                }
            default:
                break
            }
        }
        return .reachable
    }
}

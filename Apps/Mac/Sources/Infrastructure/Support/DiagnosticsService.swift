import Foundation
import Network
import Domain

public struct DiagnosticSessionContext: Sendable {
    public var appVersion: String
    public var osVersion: String
    public var homeDirectory: String
    public var now: @Sendable () -> Date
    public var configPath: String
    public var configIntegrity: @Sendable () -> DiagnosticConfigIntegrity
    public var inspect: @Sendable (String) async -> DiagnosticProviderInspection?

    public init(
        appVersion: String,
        osVersion: String,
        homeDirectory: String,
        now: @escaping @Sendable () -> Date = { Date() },
        configPath: String,
        configIntegrity: @escaping @Sendable () -> DiagnosticConfigIntegrity,
        inspect: @escaping @Sendable (String) async -> DiagnosticProviderInspection?
    ) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.homeDirectory = homeDirectory
        self.now = now
        self.configPath = configPath
        self.configIntegrity = configIntegrity
        self.inspect = inspect
    }
}

public final class DiagnosticsService: DiagnosticsServicing, Sendable {
    private let checker: any CompatibilityChecking
    private let context: DiagnosticSessionContext

    public init(
        checker: any CompatibilityChecking,
        context: DiagnosticSessionContext
    ) {
        self.checker = checker
        self.context = context
    }

    public func runAll() async -> [DiagnosticResult] {
        let report = await checker.check()
        let now = context.now()
        var results = systemResults(from: report, now: now)
        results.append(configResult(now: now))
        for providerId in report.providerChecks.keys.sorted() {
            results.append(contentsOf: await providerResults(
                providerId: providerId,
                report: report,
                now: now
            ))
        }
        return results
    }

    public func run(providerId: String) async -> [DiagnosticResult] {
        let report = await checker.check()
        return await providerResults(providerId: providerId, report: report, now: context.now())
    }

    public func retry(_ result: DiagnosticResult) async -> DiagnosticResult {
        if result.kind.isSystemKind {
            let report = await checker.check()
            let refreshed = systemResults(from: report, now: context.now())
            return refreshed.first { $0.kind == result.kind } ?? result
        }
        if result.kind == .configurationIntegrity {
            return configResult(now: context.now())
        }
        guard let providerId = result.providerId else { return result }
        let report = await checker.check()
        let refreshed = await providerResults(providerId: providerId, report: report, now: context.now())
        return refreshed.first { $0.id == result.id } ?? result
    }

    @MainActor
    public static func live(
        monitor: QuotaMonitor,
        store: JSONSettingsStore = .shared,
        checker: (any CompatibilityChecking)? = nil
    ) -> DiagnosticsService {
        DiagnosticSessionContext.live(monitor: monitor, store: store, checker: checker).service
    }

    public func summary(for results: [DiagnosticResult]) -> DiagnosticSummary {
        let architecture = results.first(where: { $0.kind == .architecture })?.detail
            ?? ""
        return DiagnosticSummary.make(
            appVersion: context.appVersion,
            osVersion: context.osVersion,
            architecture: architecture,
            results: results
        )
    }

    private func systemResults(from report: CompatibilityReport, now: Date) -> [DiagnosticResult] {
        [
            make(
                id: "os",
                kind: .operatingSystem,
                ok: report.minimumOSSatisfied,
                errorCode: DiagnosticCode.osUnsupported,
                title: "diag.title.os",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.os.fail",
                now: now
            ),
            make(
                id: "arch",
                kind: .architecture,
                ok: report.supportedArchitecture,
                errorCode: DiagnosticCode.archUnsupported,
                title: "diag.title.arch",
                okDetail: report.architecture,
                failDetail: report.architecture,
                now: now
            ),
            make(
                id: "writable",
                kind: .appWritable,
                ok: report.appDirectoryWritable,
                errorCode: DiagnosticCode.writableFail,
                title: "diag.title.writable",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.writable.fail",
                now: now
            ),
            make(
                id: "keychain",
                kind: .keychainAccess,
                ok: report.keychainAvailable,
                errorCode: DiagnosticCode.keychainFail,
                title: "diag.title.keychain",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.keychain.fail",
                now: now,
                failSeverity: .warning
            ),
            notificationResult(report.notificationStatus, now: now),
        ]
    }

    private func notificationResult(
        _ status: CompatibilityNotificationStatus,
        now: Date
    ) -> DiagnosticResult {
        switch status {
        case .authorized, .provisional:
            return make(
                id: "notifications",
                kind: .notificationPermission,
                ok: true,
                errorCode: "",
                title: "diag.title.notifications",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.ok",
                now: now
            )
        case .denied:
            return make(
                id: "notifications",
                kind: .notificationPermission,
                ok: false,
                errorCode: DiagnosticCode.notificationsDenied,
                title: "diag.title.notifications",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.notifications.denied",
                now: now,
                failSeverity: .warning
            )
        case .notDetermined:
            return make(
                id: "notifications",
                kind: .notificationPermission,
                ok: false,
                errorCode: DiagnosticCode.notificationsNotDetermined,
                title: "diag.title.notifications",
                okDetail: "diag.detail.ok",
                failDetail: "diag.detail.notifications.not_determined",
                now: now,
                failSeverity: .warning
            )
        }
    }

    private func configResult(now: Date) -> DiagnosticResult {
        let integrity = context.configIntegrity()
        let path = DiagnosticPrivacy.displayPath(
            context.configPath,
            homeDirectory: context.homeDirectory
        )
        switch integrity {
        case .ok:
            return make(
                id: "config",
                kind: .configurationIntegrity,
                ok: true,
                errorCode: "",
                title: "diag.title.config",
                okDetail: "diag.detail.config.ok",
                failDetail: path,
                now: now
            )
        case .missing:
            return DiagnosticResult(
                id: "config",
                providerId: nil,
                kind: .configurationIntegrity,
                severity: .info,
                title: "diag.title.config",
                detail: sanitized("diag.detail.config.missing \(path)"),
                suggestedAction: nil,
                checkedAt: now,
                code: DiagnosticCode.configMissing
            )
        case .corrupt:
            return make(
                id: "config",
                kind: .configurationIntegrity,
                ok: false,
                errorCode: DiagnosticCode.configCorrupt,
                title: "diag.title.config",
                okDetail: path,
                failDetail: path,
                now: now
            )
        }
    }

    private func providerResults(
        providerId: String,
        report: CompatibilityReport,
        now: Date
    ) async -> [DiagnosticResult] {
        let check = report.providerChecks[providerId]
        let inspection = await context.inspect(providerId)
        let enabled = check?.enabled ?? inspection?.enabled ?? false
        var results: [DiagnosticResult] = [
            providerEnabledResult(providerId: providerId, enabled: enabled, now: now),
        ]
        guard enabled else { return results }

        if let check, let cliName = check.cliName {
            results.append(cliResult(check: check, cliName: cliName, now: now))
        }

        guard let inspection else { return results }

        results.append(credentialResult(providerId: providerId, inspection: inspection, now: now))
        results.append(networkResult(providerId: providerId, inspection: inspection, now: now))
        results.append(endpointResult(providerId: providerId, inspection: inspection, now: now))
        results.append(cacheResult(providerId: providerId, inspection: inspection, now: now))
        return results
    }

    private func providerEnabledResult(
        providerId: String,
        enabled: Bool,
        now: Date
    ) -> DiagnosticResult {
        DiagnosticResult(
            id: "provider.enabled.\(providerId)",
            providerId: providerId,
            kind: .providerEnabled,
            severity: enabled ? .ok : .info,
            title: "diag.title.provider",
            detail: enabled ? "diag.detail.provider.enabled" : "diag.detail.provider.disabled",
            suggestedAction: enabled
                ? nil
                : DiagnosticActionSet.primary(
                    kind: .providerEnabled,
                    severity: .info,
                    code: DiagnosticCode.providerDisabled
                ),
            checkedAt: now,
            code: enabled ? "" : DiagnosticCode.providerDisabled
        )
    }

    private func cliResult(
        check: ProviderCompatibility,
        cliName: String,
        now: Date
    ) -> DiagnosticResult {
        make(
            id: "provider.cli.\(check.providerId)",
            providerId: check.providerId,
            kind: .cliInstalled,
            ok: check.cliInstalled,
            errorCode: DiagnosticCode.cliMissing,
            title: "diag.title.cli",
            okDetail: cliName,
            failDetail: cliName,
            now: now
        )
    }

    private func credentialResult(
        providerId: String,
        inspection: DiagnosticProviderInspection,
        now: Date
    ) -> DiagnosticResult {
        let hint = sanitizedHint(inspection.detailHint)
        switch inspection.credential {
        case .available:
            return make(
                id: "provider.credential.\(providerId)",
                providerId: providerId,
                kind: .credentialAvailable,
                ok: true,
                errorCode: "",
                title: "diag.title.credential",
                okDetail: joined("diag.detail.credential.ok", hint),
                failDetail: hint,
                now: now
            )
        case .missingKey:
            return make(
                id: "provider.credential.\(providerId)",
                providerId: providerId,
                kind: .credentialAvailable,
                ok: false,
                errorCode: DiagnosticCode.missingKey,
                title: "diag.title.credential",
                okDetail: "",
                failDetail: joined("diag.detail.credential.missing_key", hint),
                now: now
            )
        case .notLoggedIn:
            return make(
                id: "provider.credential.\(providerId)",
                providerId: providerId,
                kind: .credentialAvailable,
                ok: false,
                errorCode: DiagnosticCode.notLoggedIn,
                title: "diag.title.credential",
                okDetail: "",
                failDetail: joined("diag.detail.credential.not_logged_in", hint),
                now: now
            )
        }
    }

    private func networkResult(
        providerId: String,
        inspection: DiagnosticProviderInspection,
        now: Date
    ) -> DiagnosticResult {
        make(
            id: "provider.network.\(providerId)",
            providerId: providerId,
            kind: .networkReachability,
            ok: inspection.network == .reachable,
            errorCode: DiagnosticCode.networkFail,
            title: "diag.title.network",
            okDetail: "diag.detail.network.ok",
            failDetail: "diag.detail.network.fail",
            now: now
        )
    }

    private func endpointResult(
        providerId: String,
        inspection: DiagnosticProviderInspection,
        now: Date
    ) -> DiagnosticResult {
        switch inspection.endpoint {
        case .valid:
            return make(
                id: "provider.endpoint.\(providerId)",
                providerId: providerId,
                kind: .providerEndpoint,
                ok: true,
                errorCode: "",
                title: "diag.title.endpoint",
                okDetail: "diag.detail.endpoint.ok",
                failDetail: "diag.detail.endpoint.ok",
                now: now
            )
        case .skipped:
            return DiagnosticResult(
                id: "provider.endpoint.\(providerId)",
                providerId: providerId,
                kind: .providerEndpoint,
                severity: .info,
                title: "diag.title.endpoint",
                detail: "diag.detail.endpoint.skipped",
                suggestedAction: nil,
                checkedAt: now,
                code: ""
            )
        case .serviceRejected:
            return make(
                id: "provider.endpoint.\(providerId)",
                providerId: providerId,
                kind: .providerEndpoint,
                ok: false,
                errorCode: DiagnosticCode.serviceRejected,
                title: "diag.title.endpoint",
                okDetail: "diag.detail.endpoint.ok",
                failDetail: "diag.detail.endpoint.rejected",
                now: now
            )
        }
    }

    private func cacheResult(
        providerId: String,
        inspection: DiagnosticProviderInspection,
        now: Date
    ) -> DiagnosticResult {
        switch inspection.cache {
        case .fresh:
            return make(
                id: "provider.cache.\(providerId)",
                providerId: providerId,
                kind: .cacheFreshness,
                ok: true,
                errorCode: "",
                title: "diag.title.cache",
                okDetail: "diag.detail.cache.fresh",
                failDetail: "diag.detail.cache.fresh",
                now: now
            )
        case .missing:
            return DiagnosticResult(
                id: "provider.cache.\(providerId)",
                providerId: providerId,
                kind: .cacheFreshness,
                severity: .info,
                title: "diag.title.cache",
                detail: "diag.detail.cache.missing",
                suggestedAction: nil,
                checkedAt: now,
                code: ""
            )
        case .expired:
            return DiagnosticResult(
                id: "provider.cache.\(providerId)",
                providerId: providerId,
                kind: .cacheFreshness,
                severity: .warning,
                title: "diag.title.cache",
                detail: "diag.detail.cache.expired",
                suggestedAction: DiagnosticActionSet.primary(
                    kind: .cacheFreshness,
                    severity: .warning,
                    code: DiagnosticCode.cacheExpired
                ),
                checkedAt: now,
                code: DiagnosticCode.cacheExpired
            )
        }
    }

    private func make(
        id: String,
        providerId: String? = nil,
        kind: DiagnosticCheckKind,
        ok: Bool,
        errorCode: String,
        title: String,
        okDetail: String,
        failDetail: String,
        now: Date,
        failSeverity: DiagnosticSeverity = .error
    ) -> DiagnosticResult {
        let severity: DiagnosticSeverity = ok ? .ok : failSeverity
        let code = ok ? "" : errorCode
        return DiagnosticResult(
            id: id,
            providerId: providerId,
            kind: kind,
            severity: severity,
            title: title,
            detail: sanitized(ok ? okDetail : failDetail),
            suggestedAction: DiagnosticActionSet.primary(
                kind: kind,
                severity: severity,
                code: code
            ),
            checkedAt: now,
            code: code
        )
    }

    private func sanitized(_ text: String) -> String {
        DiagnosticPrivacy.sanitize(text, homeDirectory: context.homeDirectory)
    }

    private func sanitizedHint(_ hint: String?) -> String {
        guard let hint, !hint.isEmpty else { return "" }
        var value = DiagnosticPrivacy.sanitize(hint, homeDirectory: context.homeDirectory)
        value = value.replacingOccurrences(of: #"\{[^{}]*\}"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "raw-response", with: "", options: .caseInsensitive)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func joined(_ base: String, _ hint: String) -> String {
        hint.isEmpty ? base : "\(base) \(hint)"
    }
}

private extension DiagnosticCheckKind {
    var isSystemKind: Bool {
        switch self {
        case .operatingSystem, .architecture, .appWritable, .keychainAccess, .notificationPermission:
            return true
        default:
            return false
        }
    }
}

extension DiagnosticSessionContext {
    public static func osVersionLabel(
        _ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    public static func configIntegrity(of store: JSONSettingsStore) -> DiagnosticConfigIntegrity {
        _ = store.readAll()
        if let error = store.lastError, case .corruptJSON = error {
            return .corrupt
        }
        if !FileManager.default.fileExists(atPath: store.fileURL.path) {
            return .missing
        }
        return .ok
    }

    @MainActor
    public static func live(
        monitor: QuotaMonitor,
        store: JSONSettingsStore,
        checker: (any CompatibilityChecking)? = nil
    ) -> (service: DiagnosticsService, context: DiagnosticSessionContext) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let context = DiagnosticSessionContext(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            osVersion: osVersionLabel(),
            homeDirectory: home,
            now: { Date() },
            configPath: store.fileURL.path,
            configIntegrity: { configIntegrity(of: store) },
            inspect: { providerId in
                await DiagnosticLiveInspector.inspect(providerId: providerId, monitor: monitor)
            }
        )
        let service = DiagnosticsService(
            checker: checker ?? CompatibilityChecker(store: store),
            context: context
        )
        return (service, context)
    }
}

enum DiagnosticLiveInspector {
    @MainActor
    static func inspect(
        providerId: String,
        monitor: QuotaMonitor
    ) async -> DiagnosticProviderInspection? {
        guard let provider = monitor.provider(for: providerId) else {
            return DiagnosticProviderInspection(
                enabled: false,
                credential: .missingKey,
                network: .reachable,
                endpoint: .skipped,
                cache: .missing
            )
        }
        let available = await provider.isAvailable()
        let reachable = await DiagnosticReachability.isSatisfied()
        let snapshot = provider.snapshot
        let error = provider.lastError
        let network = DiagnosticClassification.network(lastError: error, reachable: reachable)
        var endpoint = DiagnosticClassification.endpoint(lastError: error, snapshot: snapshot)
        let credential = DiagnosticClassification.credential(
            providerId: providerId,
            available: available,
            lastError: error
        )
        if network == .unreachable || credential != .available {
            endpoint = .skipped
        }
        return DiagnosticProviderInspection(
            enabled: provider.isEnabled,
            credential: credential,
            network: network,
            endpoint: endpoint,
            cache: DiagnosticClassification.cache(snapshot: snapshot)
        )
    }
}

enum DiagnosticReachability {
    static func isSatisfied(timeoutNanoseconds: UInt64 = 400_000_000) async -> Bool {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            func take() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if finished { return false }
                finished = true
                return true
            }
        }
        let once = Once()
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.smartquota.diag.reachability")
            monitor.pathUpdateHandler = { path in
                guard once.take() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Double(timeoutNanoseconds) / 1_000_000_000) {
                guard once.take() else { return }
                monitor.cancel()
                continuation.resume(returning: true)
            }
        }
    }
}

import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("DiagnosticsService Tests")
struct DiagnosticsServiceTests {

    @Test
    func `paths become tilde-relative or filename and emails are masked`() {
        #expect(
            DiagnosticPrivacy.displayPath(
                "/Users/tester/.smartquota/settings.json",
                homeDirectory: "/Users/tester"
            ) == "~/.smartquota/settings.json"
        )
        #expect(
            DiagnosticPrivacy.displayPath(
                "/var/folders/xx/tmp/auth.json",
                homeDirectory: "/Users/tester"
            ) == "auth.json"
        )
        #expect(DiagnosticPrivacy.maskEmail("jane.doe@example.com") == "j***@example.com")
        let sanitized = DiagnosticPrivacy.sanitize(
            "token=sk-secretTOKEN99 cookie=abc email=jane.doe@example.com path=/Users/tester/.codex/auth.json Bearer eyJhbGciOi.payload.sig",
            homeDirectory: "/Users/tester"
        )
        #expect(!sanitized.contains("sk-secretTOKEN99"))
        #expect(!sanitized.contains("jane.doe@example.com"))
        #expect(!sanitized.contains("/Users/tester"))
        #expect(!sanitized.contains("eyJhbGciOi.payload.sig"))
        #expect(sanitized.contains("j***@example.com"))
        #expect(sanitized.contains("~/.codex/auth.json"))
    }

    @Test
    func `copy summary includes version OS arch results and codes only`() async {
        let env = try! makeEnv()
        defer { env.cleanup() }

        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: env.readyReport()),
            context: env.context(
                probes: [
                    "claude": .success(providerId: "claude"),
                ]
            )
        )
        let results = await service.runAll()
        let summary = service.summary(for: results).text

        #expect(summary.contains("Version: 0.3.28"))
        #expect(summary.contains("OS: macOS 15.4"))
        #expect(summary.contains("Arch: arm64"))
        #expect(summary.contains("operatingSystem ok"))
        #expect(summary.contains("architecture ok"))
        #expect(!summary.contains("sk-"))
        #expect(!summary.contains("@example.com"))
        #expect(!summary.contains("/Users/"))
        #expect(!summary.contains("raw-response"))
        #expect(!summary.contains("Cookie"))
    }

    @Test
    func `system checks come from CompatibilityReport and are not reimplemented`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let report = CompatibilityReport.make(
            minimumOSSatisfied: false,
            architecture: "i386",
            supportedArchitecture: false,
            appDirectoryWritable: false,
            keychainAvailable: false,
            notificationStatus: .denied,
            providerChecks: [:]
        )
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(probes: [:])
        )
        let results = await service.runAll()

        #expect(result(results, kind: .operatingSystem)?.code == DiagnosticCode.osUnsupported)
        #expect(result(results, kind: .operatingSystem)?.severity == .error)
        #expect(result(results, kind: .architecture)?.code == DiagnosticCode.archUnsupported)
        #expect(result(results, kind: .architecture)?.detail == "i386")
        #expect(result(results, kind: .appWritable)?.code == DiagnosticCode.writableFail)
        #expect(result(results, kind: .keychainAccess)?.code == DiagnosticCode.keychainFail)
        #expect(result(results, kind: .notificationPermission)?.code == DiagnosticCode.notificationsDenied)
        #expect(result(results, kind: .notificationPermission)?.actions.contains(.openSystemSettings) == true)
        #expect(results.contains { $0.kind == .cliInstalled } == false)
    }

    @Test
    func `failure taxonomy is distinct for CLI key login network rejection and cache`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let report = CompatibilityReport.make(
            minimumOSSatisfied: true,
            architecture: "arm64",
            supportedArchitecture: true,
            appDirectoryWritable: true,
            keychainAvailable: true,
            notificationStatus: .authorized,
            providerChecks: [
                "claude": ProviderCompatibility(
                    providerId: "claude",
                    enabled: true,
                    cliName: "claude",
                    cliInstalled: false,
                    suggestedAction: .installOrSignInCLI
                ),
                "copilot": ProviderCompatibility(
                    providerId: "copilot",
                    enabled: true,
                    cliName: nil,
                    cliInstalled: true,
                    suggestedAction: .none
                ),
                "codex": ProviderCompatibility(
                    providerId: "codex",
                    enabled: true,
                    cliName: "codex",
                    cliInstalled: true,
                    suggestedAction: .none
                ),
                "kimi": ProviderCompatibility(
                    providerId: "kimi",
                    enabled: true,
                    cliName: "kimi",
                    cliInstalled: true,
                    suggestedAction: .none
                ),
                "grok": ProviderCompatibility(
                    providerId: "grok",
                    enabled: true,
                    cliName: nil,
                    cliInstalled: true,
                    suggestedAction: .none
                ),
            ]
        )
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(
                probes: [
                    "claude": DiagnosticProbeOutcome(
                        enabled: true,
                        reachable: true,
                        credentialAvailable: true
                    ),
                    "copilot": DiagnosticProbeOutcome(
                        enabled: true,
                        error: .authenticationRequired,
                        reachable: true,
                        credentialAvailable: false,
                        detailHint: "key path /Users/tester/.copilot/token sk-secretTOKEN99"
                    ),
                    "codex": DiagnosticProbeOutcome(
                        enabled: true,
                        error: .authenticationRequired,
                        reachable: true,
                        credentialAvailable: false,
                        detailHint: "jane.doe@example.com /Users/tester/.codex/auth.json"
                    ),
                    "kimi": DiagnosticProbeOutcome(
                        enabled: true,
                        snapshot: UsageSnapshot(providerId: "kimi", quotas: [], capturedAt: Date()),
                        error: .timeout,
                        reachable: false,
                        credentialAvailable: true
                    ),
                    "grok": DiagnosticProbeOutcome(
                        enabled: true,
                        snapshot: UsageSnapshot(
                            providerId: "grok",
                            quotas: [],
                            capturedAt: Date.distantPast
                        ),
                        error: .rateLimited(retryAt: Date()),
                        reachable: true,
                        credentialAvailable: true
                    ),
                ]
            )
        )
        let results = await service.runAll()

        let cli = try #require(result(results, kind: .cliInstalled, providerId: "claude"))
        #expect(cli.code == DiagnosticCode.cliMissing)
        #expect(cli.severity == .error)
        #expect(cli.actions.contains(.openConfiguration))

        let key = try #require(result(results, kind: .credentialAvailable, providerId: "copilot"))
        #expect(key.code == DiagnosticCode.missingKey)
        #expect(key.actions.contains(.openConfiguration))
        #expect(!key.detail.contains("sk-secretTOKEN99"))
        #expect(!key.detail.contains("/Users/tester"))

        let login = try #require(result(results, kind: .credentialAvailable, providerId: "codex"))
        #expect(login.code == DiagnosticCode.notLoggedIn)
        #expect(login.code != key.code)
        #expect(!login.detail.contains("jane.doe@example.com"))
        #expect(login.detail.contains("j***@example.com") || !login.detail.contains("@"))

        let network = try #require(result(results, kind: .networkReachability, providerId: "kimi"))
        #expect(network.code == DiagnosticCode.networkFail)
        #expect(network.actions.contains(.retry))

        let rejected = try #require(result(results, kind: .providerEndpoint, providerId: "grok"))
        #expect(rejected.code == DiagnosticCode.serviceRejected)
        #expect(rejected.actions.contains(.openDashboard))

        let cache = try #require(result(results, kind: .cacheFreshness, providerId: "grok"))
        #expect(cache.code == DiagnosticCode.cacheExpired)
        #expect(cache.severity == .warning)
        #expect(cache.actions.contains(.retry))

        let codes = [cli.code, key.code, login.code, network.code, rejected.code, cache.code]
        #expect(Set(codes).count == 6)
    }

    @Test
    func `corrupt settings file is a config integrity error with a redacted path`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try Data("not-json {".utf8).write(to: env.settingsURL)
        let store = env.store
        _ = store.readAll()
        #expect(store.lastError != nil)
        #expect(DiagnosticSessionContext.configIntegrity(of: store) == .corrupt)

        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: env.readyReport()),
            context: env.context(
                probes: [:],
                integrity: .corrupt,
                configPath: env.settingsURL.path
            )
        )
        let results = await service.runAll()
        let config = try #require(result(results, kind: .configurationIntegrity))
        #expect(config.code == DiagnosticCode.configCorrupt)
        #expect(config.severity == .error)
        #expect(config.actions.contains(.openLogs))
        #expect(!config.detail.contains(env.configRoot.path))
        #expect(config.detail.contains("settings.json") || config.detail.contains("~/"))
    }

    @Test
    func `retry reruns only that check and can change the result`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let box = ProbeBox(
            value: [
                "claude": DiagnosticProbeOutcome(
                    enabled: true,
                    error: .timeout,
                    reachable: false,
                    credentialAvailable: true
                ),
            ]
        )
        let report = env.readyReport(providers: [
            "claude": ProviderCompatibility(
                providerId: "claude",
                enabled: true,
                cliName: "claude",
                cliInstalled: true,
                suggestedAction: .none
            ),
        ])
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(box: box)
        )
        let first = await service.run(providerId: "claude")
        let network = try #require(result(first, kind: .networkReachability, providerId: "claude"))
        #expect(network.code == DiagnosticCode.networkFail)

        box.value["claude"] = .success(providerId: "claude")
        let retried = await service.retry(network)
        #expect(retried.id == network.id)
        #expect(retried.kind == .networkReachability)
        #expect(retried.severity == .ok)
        #expect(retried.code.isEmpty)
        #expect(box.probed == ["claude", "claude"])
    }

    @Test
    func `run classifies endpoint from a fresh probe not leftover cache`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let leftover = UsageSnapshot(
            providerId: "grok",
            quotas: [],
            capturedAt: Date.distantPast
        )
        let box = ProbeBox(
            value: [
                "grok": DiagnosticProbeOutcome(
                    enabled: true,
                    snapshot: leftover,
                    error: .parseFailed("raw-response {\"access_token\":\"xyz\"}"),
                    reachable: true,
                    credentialAvailable: true,
                    detailHint: "jane.doe@example.com leftover"
                ),
            ]
        )
        let report = env.readyReport(providers: [
            "grok": ProviderCompatibility(
                providerId: "grok",
                enabled: true,
                cliName: nil,
                cliInstalled: true,
                suggestedAction: .none
            ),
        ])
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(box: box)
        )
        let results = await service.run(providerId: "grok")
        let endpoint = try #require(result(results, kind: .providerEndpoint, providerId: "grok"))
        let cache = try #require(result(results, kind: .cacheFreshness, providerId: "grok"))
        #expect(box.probed == ["grok"])
        #expect(endpoint.code == DiagnosticCode.serviceRejected)
        #expect(cache.code == DiagnosticCode.cacheExpired)
        #expect(!endpoint.detail.contains("access_token"))
        #expect(!endpoint.detail.contains("raw-response"))
    }

    @Test
    func `run for one provider does not include other provider checks`() async {
        let env = try! makeEnv()
        defer { env.cleanup() }

        let report = env.readyReport(providers: [
            "claude": ProviderCompatibility(
                providerId: "claude",
                enabled: true,
                cliName: "claude",
                cliInstalled: false,
                suggestedAction: .installOrSignInCLI
            ),
            "codex": ProviderCompatibility(
                providerId: "codex",
                enabled: true,
                cliName: "codex",
                cliInstalled: true,
                suggestedAction: .none
            ),
        ])
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(
                probes: [
                    "claude": .success(providerId: "claude"),
                    "codex": DiagnosticProbeOutcome(
                        enabled: true,
                        error: .authenticationRequired,
                        reachable: true,
                        credentialAvailable: false
                    ),
                ]
            )
        )
        let results = await service.run(providerId: "claude")
        #expect(results.contains { $0.providerId == "codex" } == false)
        #expect(results.contains { $0.providerId == "claude" && $0.kind == .cliInstalled })
        #expect(results.contains { $0.kind == .operatingSystem } == false)
    }

    @Test
    func `copy summary never includes tokens cookies emails or raw responses`() async {
        let env = try! makeEnv()
        defer { env.cleanup() }

        let report = env.readyReport(providers: [
            "copilot": ProviderCompatibility(
                providerId: "copilot",
                enabled: true,
                cliName: nil,
                cliInstalled: true,
                suggestedAction: .none
            ),
        ])
        let service = DiagnosticsService(
            checker: StubCompatibilityChecker(report: report),
            context: env.context(
                probes: [
                    "copilot": DiagnosticProbeOutcome(
                        enabled: true,
                        snapshot: UsageSnapshot(
                            providerId: "copilot",
                            quotas: [],
                            capturedAt: Date.distantPast
                        ),
                        error: .authenticationRequired,
                        reachable: false,
                        credentialAvailable: false,
                        detailHint: """
                        email=jane.doe@example.com token=sk-secretTOKEN99 \
                        Cookie: session=abc path=/Users/tester/.copilot/raw.json \
                        raw-response={"access_token":"xyz"}
                        """
                    ),
                ]
            )
        )
        let results = await service.runAll()
        let summary = service.summary(for: results).text
        for result in results {
            #expect(DiagnosticPrivacy.containsForbiddenPayload(result.detail) == false)
            #expect(!result.detail.contains("sk-secretTOKEN99"))
            #expect(!result.detail.contains("jane.doe@example.com"))
            #expect(!result.detail.contains("raw-response"))
        }
        #expect(!summary.contains("sk-secretTOKEN99"))
        #expect(!summary.contains("jane.doe@example.com"))
        #expect(!summary.contains("session=abc"))
        #expect(!summary.contains("/Users/tester"))
        #expect(summary.contains(DiagnosticCode.missingKey))
        #expect(summary.contains(DiagnosticCode.networkFail))
        #expect(summary.contains(DiagnosticCode.cacheExpired))
    }

    private func result(
        _ results: [DiagnosticResult],
        kind: DiagnosticCheckKind,
        providerId: String? = nil
    ) -> DiagnosticResult? {
        results.first { item in
            item.kind == kind && item.providerId == providerId
        }
    }

    private struct Env {
        let configRoot: URL
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        var store: JSONSettingsStore { JSONSettingsStore(fileURL: settingsURL) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let home = "/Users/tester"

        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
        }

        func readyReport(
            providers: [String: ProviderCompatibility] = [:]
        ) -> CompatibilityReport {
            CompatibilityReport.make(
                minimumOSSatisfied: true,
                architecture: "arm64",
                supportedArchitecture: true,
                appDirectoryWritable: true,
                keychainAvailable: true,
                notificationStatus: .authorized,
                providerChecks: providers
            )
        }

        func context(
            probes: [String: DiagnosticProbeOutcome],
            integrity: DiagnosticConfigIntegrity = .ok,
            configPath: String? = nil
        ) -> DiagnosticSessionContext {
            DiagnosticSessionContext(
                appVersion: "0.3.28",
                osVersion: "macOS 15.4",
                homeDirectory: home,
                now: { now },
                configPath: configPath ?? settingsURL.path,
                configIntegrity: { integrity },
                probe: { id in probes[id] }
            )
        }

        func context(box: ProbeBox) -> DiagnosticSessionContext {
            DiagnosticSessionContext(
                appVersion: "0.3.28",
                osVersion: "macOS 15.4",
                homeDirectory: home,
                now: { now },
                configPath: settingsURL.path,
                configIntegrity: { .ok },
                probe: { id in await box.probe(id) }
            )
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-diag-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(configRoot: root)
    }
}

struct StubCompatibilityChecker: CompatibilityChecking, Sendable {
    let report: CompatibilityReport
    func check() async -> CompatibilityReport { report }
}

final class ProbeBox: @unchecked Sendable {
    var value: [String: DiagnosticProbeOutcome]
    private(set) var probed: [String] = []

    init(value: [String: DiagnosticProbeOutcome]) {
        self.value = value
    }

    func probe(_ providerId: String) async -> DiagnosticProbeOutcome? {
        probed.append(providerId)
        return value[providerId]
    }
}

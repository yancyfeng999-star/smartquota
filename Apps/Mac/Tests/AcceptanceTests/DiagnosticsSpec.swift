import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: Diagnostics center
///
/// Acceptance: disconnecting the network, removing a CLI, deleting a test
/// credential, and denying notification permission each produce a distinct
/// result and an executable suggestion. Copy-summary stays non-sensitive.
@Suite("Feature: Diagnostics")
struct DiagnosticsSpec {

    @Test
    func `disconnected network missing CLI missing key and denied notifications differ`() async throws {
        let env = try DiagnosticsHarness.make()
        defer { env.cleanup() }

        let network = await env.service(
            notifications: .authorized,
            providers: [
                "kimi": .cliInstalled("kimi"),
            ],
            inspections: [
                "kimi": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .available,
                    network: .unreachable,
                    endpoint: .skipped,
                    cache: .fresh
                ),
            ]
        ).runAll()
        let networkHit = try #require(network.first { $0.kind == .networkReachability })
        #expect(networkHit.code == DiagnosticCode.networkFail)
        #expect(networkHit.actions.contains(.retry))
        #expect(network.contains { $0.code == DiagnosticCode.cliMissing } == false)
        #expect(network.contains { $0.code == DiagnosticCode.missingKey } == false)
        #expect(network.contains { $0.code == DiagnosticCode.notificationsDenied } == false)

        let cli = await env.service(
            notifications: .authorized,
            providers: [
                "claude": ProviderCompatibility(
                    providerId: "claude",
                    enabled: true,
                    cliName: "claude",
                    cliInstalled: false,
                    suggestedAction: .installOrSignInCLI
                ),
            ],
            inspections: [
                "claude": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .available,
                    network: .reachable,
                    endpoint: .skipped,
                    cache: .missing
                ),
            ]
        ).runAll()
        let cliHit = try #require(cli.first { $0.kind == .cliInstalled })
        #expect(cliHit.code == DiagnosticCode.cliMissing)
        #expect(cliHit.actions.contains(.openConfiguration))
        #expect(cliHit.actions.contains(.openHelp))

        let key = await env.service(
            notifications: .authorized,
            providers: [
                "copilot": ProviderCompatibility(
                    providerId: "copilot",
                    enabled: true,
                    cliName: nil,
                    cliInstalled: true,
                    suggestedAction: .none
                ),
            ],
            inspections: [
                "copilot": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .missingKey,
                    network: .reachable,
                    endpoint: .skipped,
                    cache: .missing,
                    detailHint: "/Users/tester/.copilot/token"
                ),
            ]
        ).runAll()
        let keyHit = try #require(key.first { $0.kind == .credentialAvailable })
        #expect(keyHit.code == DiagnosticCode.missingKey)
        #expect(keyHit.actions.contains(.openConfiguration))
        #expect(keyHit.code != DiagnosticCode.notLoggedIn)
        #expect(keyHit.code != DiagnosticCode.cliMissing)

        let login = await env.service(
            notifications: .authorized,
            providers: [
                "codex": .cliInstalled("codex"),
            ],
            inspections: [
                "codex": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .notLoggedIn,
                    network: .reachable,
                    endpoint: .skipped,
                    cache: .missing
                ),
            ]
        ).runAll()
        let loginHit = try #require(login.first { $0.kind == .credentialAvailable })
        #expect(loginHit.code == DiagnosticCode.notLoggedIn)
        #expect(loginHit.actions.contains(.openConfiguration))

        let denied = await env.service(
            notifications: .denied,
            providers: [:],
            inspections: [:]
        ).runAll()
        let notice = try #require(denied.first { $0.kind == .notificationPermission })
        #expect(notice.code == DiagnosticCode.notificationsDenied)
        #expect(notice.actions.contains(.openSystemSettings))

        let codes = [networkHit.code, cliHit.code, keyHit.code, loginHit.code, notice.code]
        #expect(Set(codes).count == 5)
    }

    @Test
    func `service rejection and expired cache are distinct from network failure`() async throws {
        let env = try DiagnosticsHarness.make()
        defer { env.cleanup() }

        let results = await env.service(
            notifications: .authorized,
            providers: [
                "grok": ProviderCompatibility(
                    providerId: "grok",
                    enabled: true,
                    cliName: nil,
                    cliInstalled: true,
                    suggestedAction: .none
                ),
            ],
            inspections: [
                "grok": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .available,
                    network: .reachable,
                    endpoint: .serviceRejected,
                    cache: .expired
                ),
            ]
        ).runAll()

        let endpoint = try #require(results.first { $0.kind == .providerEndpoint })
        let cache = try #require(results.first { $0.kind == .cacheFreshness })
        #expect(endpoint.code == DiagnosticCode.serviceRejected)
        #expect(endpoint.actions.contains(.openDashboard))
        #expect(cache.code == DiagnosticCode.cacheExpired)
        #expect(cache.actions.contains(.retry))
        #expect(results.contains { $0.code == DiagnosticCode.networkFail } == false)
    }

    @Test
    func `copy summary is shareable and strips secrets paths and emails`() async {
        let env = try! DiagnosticsHarness.make()
        defer { env.cleanup() }

        let service = env.service(
            notifications: .denied,
            providers: [
                "copilot": ProviderCompatibility(
                    providerId: "copilot",
                    enabled: true,
                    cliName: nil,
                    cliInstalled: true,
                    suggestedAction: .none
                ),
            ],
            inspections: [
                "copilot": DiagnosticProviderInspection(
                    enabled: true,
                    credential: .missingKey,
                    network: .unreachable,
                    endpoint: .skipped,
                    cache: .expired,
                    detailHint: "jane.doe@example.com sk-secretTOKEN99 Cookie: sid=1 /Users/tester/.copilot"
                ),
            ]
        )
        let results = await service.runAll()
        let text = service.summary(for: results).text

        #expect(text.contains("Version: 0.3.28"))
        #expect(text.contains("OS: macOS 15.4"))
        #expect(text.contains("Arch: arm64"))
        #expect(text.contains(DiagnosticCode.notificationsDenied))
        #expect(text.contains(DiagnosticCode.missingKey))
        #expect(text.contains(DiagnosticCode.networkFail))
        #expect(text.contains(DiagnosticCode.cacheExpired))
        #expect(!text.contains("jane.doe@example.com"))
        #expect(!text.contains("sk-secretTOKEN99"))
        #expect(!text.contains("sid=1"))
        #expect(!text.contains("/Users/tester"))
        #expect(!text.contains("{"))
        for result in results {
            #expect(DiagnosticPrivacy.containsForbiddenPayload(result.detail) == false)
        }
    }
}

private enum DiagnosticsHarness {
    struct Env {
        let configRoot: URL
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }

        func cleanup() {
            try? FileManager.default.removeItem(at: configRoot)
        }

        func service(
            notifications: CompatibilityNotificationStatus,
            providers: [String: ProviderCompatibility],
            inspections: [String: DiagnosticProviderInspection]
        ) -> DiagnosticsService {
            let report = CompatibilityReport.make(
                minimumOSSatisfied: true,
                architecture: "arm64",
                supportedArchitecture: true,
                appDirectoryWritable: true,
                keychainAvailable: true,
                notificationStatus: notifications,
                providerChecks: providers
            )
            return DiagnosticsService(
                checker: SpecCompatibilityChecker(report: report),
                context: DiagnosticSessionContext(
                    appVersion: "0.3.28",
                    osVersion: "macOS 15.4",
                    homeDirectory: "/Users/tester",
                    now: { Date(timeIntervalSince1970: 1_700_000_000) },
                    configPath: settingsURL.path,
                    configIntegrity: { .ok },
                    inspect: { inspections[$0] }
                )
            )
        }
    }

    static func make() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-diag-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(configRoot: root)
    }
}

private struct SpecCompatibilityChecker: CompatibilityChecking, Sendable {
    let report: CompatibilityReport
    func check() async -> CompatibilityReport { report }
}

private extension ProviderCompatibility {
    static func cliInstalled(_ name: String) -> ProviderCompatibility {
        ProviderCompatibility(
            providerId: name == "kimi" ? "kimi" : name,
            enabled: true,
            cliName: name,
            cliInstalled: true,
            suggestedAction: .none
        )
    }
}

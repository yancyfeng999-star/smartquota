import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("CompatibilityChecker Tests")
struct CompatibilityCheckerTests {

    @Test
    func `old OS and unsupported arch are not ready`() async {
        let env = try! makeEnv()
        defer { env.cleanup() }

        let checker = CompatibilityChecker(
            environment: CompatibilityEnvironment(
                osMajorVersion: 14,
                architecture: "i386",
                appDirectory: env.configRoot,
                keychainAvailable: { true },
                notificationStatus: { .authorized },
                locateCLI: { _ in "/usr/local/bin/claude" },
                enabledProviders: { [] }
            )
        )
        let report = await checker.check()
        #expect(report.minimumOSSatisfied == false)
        #expect(report.supportedArchitecture == false)
        #expect(report.isReady == false)
        #expect(report.issues.contains { $0.kind == .operatingSystem })
        #expect(report.issues.contains { $0.kind == .architecture })
    }

    @Test
    func `arm64 and x86_64 environments report supported architecture`() async {
        for arch in ["arm64", "x86_64"] {
            let env = try! makeEnv()
            defer { env.cleanup() }
            let checker = CompatibilityChecker(
                environment: CompatibilityEnvironment(
                    osMajorVersion: 15,
                    architecture: arch,
                    appDirectory: env.configRoot,
                    keychainAvailable: { true },
                    notificationStatus: { .authorized },
                    locateCLI: { _ in "/bin/true" },
                    enabledProviders: { [] }
                )
            )
            let report = await checker.check()
            #expect(report.architecture == arch)
            #expect(report.supportedArchitecture)
            #expect(report.minimumOSSatisfied)
            #expect(report.appDirectoryWritable)
            #expect(report.isReady)
        }
    }

    @Test
    func `unwritable app directory is a named failure not an unknown error`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let checker = CompatibilityChecker(
            environment: CompatibilityEnvironment(
                osMajorVersion: 15,
                architecture: "arm64",
                appDirectory: env.configRoot,
                isDirectoryWritable: { _ in false },
                keychainAvailable: { true },
                notificationStatus: { .authorized },
                locateCLI: { _ in nil },
                enabledProviders: { [] }
            )
        )
        let report = await checker.check()
        #expect(report.appDirectoryWritable == false)
        #expect(report.isReady == false)
        let issue = try #require(report.issues.first { $0.kind == .appWritable })
        #expect(issue.titleContainsUnknownError == false)
        #expect(issue.code == "compat.writable.fail")
    }

    @Test
    func `denied notifications name the permission and Settings pane`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let checker = CompatibilityChecker(
            environment: CompatibilityEnvironment(
                osMajorVersion: 15,
                architecture: "x86_64",
                appDirectory: env.configRoot,
                keychainAvailable: { false },
                notificationStatus: { .denied },
                locateCLI: { _ in nil },
                enabledProviders: { [] }
            )
        )
        let report = await checker.check()
        #expect(report.keychainAvailable == false)
        #expect(report.notificationStatus == .denied)
        let notifications = try #require(report.issues.first { $0.kind == .notifications })
        #expect(notifications.permissionName == "Notifications")
        #expect(notifications.systemSettingsPane?.contains("Notifications") == true)
        #expect(notifications.titleContainsUnknownError == false)
        let keychain = try #require(report.issues.first { $0.kind == .keychain })
        #expect(keychain.permissionName == "Keychain")
    }

    @Test
    func `missing enabled-provider CLI suggests install or login and does not install`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let checker = CompatibilityChecker(
            environment: CompatibilityEnvironment(
                osMajorVersion: 15,
                architecture: "arm64",
                appDirectory: env.configRoot,
                keychainAvailable: { true },
                notificationStatus: { .authorized },
                locateCLI: { _ in nil },
                enabledProviders: {
                    [
                        EnabledProviderDependency(providerId: "claude", cliName: "claude"),
                        EnabledProviderDependency(providerId: "copilot", cliName: nil),
                    ]
                }
            )
        )
        let report = await checker.check()
        let claude = try #require(report.providerChecks["claude"])
        #expect(claude.enabled)
        #expect(claude.cliInstalled == false)
        #expect(claude.suggestedAction == .installOrSignInCLI)
        #expect(claude.suggestedAction.installsThirdPartyCLI == false)
        #expect(report.issues.contains { $0.relatedProviderId == "claude" })

        let copilot = try #require(report.providerChecks["copilot"])
        #expect(copilot.cliName == nil)
        #expect(copilot.suggestedAction == .none)
    }

    @Test
    func `checker reads enabled providers from an injected settings store`() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        try env.store.replaceAll([
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "providers": [
                "claude": ["isEnabled": true],
                "gemini": ["isEnabled": false],
                "codex": ["isEnabled": true],
            ],
        ])

        let checker = CompatibilityChecker(
            store: env.store,
            environment: CompatibilityEnvironment(
                osMajorVersion: 15,
                architecture: "arm64",
                appDirectory: env.configRoot,
                keychainAvailable: { true },
                notificationStatus: { .authorized },
                locateCLI: { name in
                    name == "codex" ? "/usr/local/bin/codex" : nil
                },
                enabledProviders: nil
            )
        )
        let report = await checker.check()
        #expect(report.providerChecks["claude"]?.cliInstalled == false)
        #expect(report.providerChecks["codex"]?.cliInstalled == true)
        #expect(report.providerChecks["gemini"] == nil)
    }

    private struct Env {
        let configRoot: URL
        let store: JSONSettingsStore
        func cleanup() {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: configRoot.path
            )
            try? FileManager.default.removeItem(at: configRoot)
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-compat-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(configRoot: root, store: JSONSettingsStore(fileURL: root.appendingPathComponent("settings.json")))
    }
}

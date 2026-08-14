import Testing
import Foundation
@testable import Domain

@Suite("CompatibilityReport Tests")
struct CompatibilityReportTests {

    @Test
    func `macOS 15 and later satisfies the minimum OS`() {
        #expect(CompatibilityOSPolicy.isSatisfied(majorVersion: 15) == true)
        #expect(CompatibilityOSPolicy.isSatisfied(majorVersion: 16) == true)
        #expect(CompatibilityOSPolicy.isSatisfied(majorVersion: 14) == false)
        #expect(CompatibilityOSPolicy.minimumMajorVersion == 15)
    }

    @Test
    func `arm64 and x86_64 are supported architectures`() {
        #expect(CompatibilityArchitecture.isSupported("arm64"))
        #expect(CompatibilityArchitecture.isSupported("x86_64"))
        #expect(CompatibilityArchitecture.isSupported("i386") == false)
        #expect(CompatibilityArchitecture.isSupported("unknown") == false)
    }

    @Test
    func `report is ready only when OS architecture writable keychain notifications and CLIs pass`() {
        let ready = makeReport(
            minimumOSSatisfied: true,
            architecture: "arm64",
            supportedArchitecture: true,
            appDirectoryWritable: true
        )
        #expect(ready.isReady)

        let intel = makeReport(
            minimumOSSatisfied: true,
            architecture: "x86_64",
            supportedArchitecture: true,
            appDirectoryWritable: true
        )
        #expect(intel.isReady)
        #expect(intel.architecture == "x86_64")

        let oldOS = makeReport(minimumOSSatisfied: false)
        #expect(oldOS.isReady == false)

        let badArch = makeReport(architecture: "i386", supportedArchitecture: false)
        #expect(badArch.isReady == false)

        let unwritable = makeReport(appDirectoryWritable: false)
        #expect(unwritable.isReady == false)
    }

    @Test
    func `missing keychain or notifications does not pretend the environment is fully ready`() {
        let keychainDown = makeReport(keychainAvailable: false)
        #expect(keychainDown.isReady == false)
        #expect(keychainDown.hasActionableIssues)

        let denied = makeReport(notificationStatus: .denied)
        #expect(denied.isReady == false)
        #expect(denied.hasActionableIssues)
        #expect(denied.issues.contains { $0.kind == .notifications && $0.permissionName == "Notifications" })

        let undetermined = makeReport(notificationStatus: .notDetermined)
        #expect(undetermined.isReady == false)
    }

    @Test
    func `missing CLI suggests install or login and never auto-installs`() {
        let check = ProviderCompatibility(
            providerId: "claude",
            enabled: true,
            cliName: "claude",
            cliInstalled: false,
            suggestedAction: .installOrSignInCLI
        )
        #expect(check.cliInstalled == false)
        #expect(check.suggestedAction == .installOrSignInCLI)
        #expect(check.suggestedAction.installsThirdPartyCLI == false)

        let report = makeReport(providerChecks: ["claude": check])
        #expect(report.isReady == false)
        #expect(report.hasActionableIssues)
        #expect(report.issues.contains { $0.kind == .providerCLI && $0.relatedProviderId == "claude" })
    }

    @Test
    func `provider enablement matches app construction defaults`() {
        #expect(ProviderEnablement.defaultEnabled(for: "codex"))
        #expect(ProviderEnablement.defaultEnabled(for: "kimi"))
        #expect(ProviderEnablement.defaultEnabled(for: "minimax"))
        #expect(ProviderEnablement.defaultEnabled(for: "grok"))
        #expect(ProviderEnablement.defaultEnabled(for: "claude"))
        #expect(ProviderEnablement.defaultEnabled(for: "copilot") == false)
        #expect(ProviderEnablement.defaultEnabled(for: "bedrock") == false)
        #expect(ProviderEnablement.isEnabled(providerId: "kimi", storedValue: nil))
        #expect(ProviderEnablement.isEnabled(providerId: "kimi", storedValue: false) == false)
        #expect(ProviderEnablement.isEnabled(providerId: "copilot", storedValue: nil) == false)
        #expect(ProviderEnablement.isEnabled(providerId: "copilot", storedValue: true))
        #expect(ProviderEnablement.coreProviderIDs == Set(["codex", "kimi", "minimax", "grok"]))
    }

    @Test
    func `permission issues name the permission or Settings pane instead of unknown error`() {
        let notification = CompatibilityIssue.notificationDenied()
        #expect(notification.permissionName == "Notifications")
        #expect(notification.systemSettingsPane != nil)
        #expect(notification.code != "unknown")
        #expect(notification.titleContainsUnknownError == false)

        let keychain = CompatibilityIssue.keychainUnavailable()
        #expect(keychain.permissionName == "Keychain")
        #expect(keychain.titleContainsUnknownError == false)

        let writable = CompatibilityIssue.appDirectoryNotWritable()
        #expect(writable.titleContainsUnknownError == false)
    }

    @Test
    func `enabled providers with a CLI requirement expose the binary name`() {
        #expect(ProviderExternalDependency.cliName(for: "claude") == "claude")
        #expect(ProviderExternalDependency.cliName(for: "codex") == "codex")
        #expect(ProviderExternalDependency.cliName(for: "gemini") == "gemini")
        #expect(ProviderExternalDependency.cliName(for: "kimi") == "kimi")
        #expect(ProviderExternalDependency.cliName(for: "ampcode") == "amp")
        #expect(ProviderExternalDependency.cliName(for: "kiro") == "kiro-cli")
        #expect(ProviderExternalDependency.cliName(for: "omp") == "omp")
        #expect(ProviderExternalDependency.cliName(for: "opencode-go") == "opencode")
        #expect(ProviderExternalDependency.cliName(for: "copilot") == nil)
        #expect(ProviderExternalDependency.cliName(for: "bedrock") == nil)
    }

    @Test
    func `Task 2 report fields are present and Codable`() throws {
        let report = makeReport(
            architecture: "arm64",
            providerChecks: [
                "claude": ProviderCompatibility(
                    providerId: "claude",
                    enabled: true,
                    cliName: "claude",
                    cliInstalled: true,
                    suggestedAction: .none
                ),
            ]
        )
        #expect(report.minimumOSSatisfied)
        #expect(report.architecture == "arm64")
        #expect(report.supportedArchitecture)
        #expect(report.appDirectoryWritable)
        #expect(report.keychainAvailable)
        #expect(report.providerChecks["claude"]?.cliInstalled == true)

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CompatibilityReport.self, from: data)
        #expect(decoded == report)
    }

    private func makeReport(
        minimumOSSatisfied: Bool = true,
        architecture: String = "arm64",
        supportedArchitecture: Bool = true,
        appDirectoryWritable: Bool = true,
        keychainAvailable: Bool = true,
        notificationStatus: CompatibilityNotificationStatus = .authorized,
        providerChecks: [String: ProviderCompatibility] = [:]
    ) -> CompatibilityReport {
        CompatibilityReport.make(
            minimumOSSatisfied: minimumOSSatisfied,
            architecture: architecture,
            supportedArchitecture: supportedArchitecture,
            appDirectoryWritable: appDirectoryWritable,
            keychainAvailable: keychainAvailable,
            notificationStatus: notificationStatus,
            providerChecks: providerChecks
        )
    }
}

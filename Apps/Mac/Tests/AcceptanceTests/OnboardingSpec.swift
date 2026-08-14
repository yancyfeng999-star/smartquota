import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: First-launch onboarding and compatibility check
///
/// Acceptance: a new temp config root can finish the guide; completed users
/// do not see it again; an incompatible Mac is never reported ready.
@Suite("Feature: Onboarding")
struct OnboardingSpec {

    @Test
    func `new temp directory can complete first-launch onboarding`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let store = FirstLaunchStore(configRoot: env.configRoot)
        var state = store.load()
        #expect(state.shouldPresent(launchMode: .normal))
        #expect(state.currentStep == .privacy)

        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .compatibility)

        let ready = CompatibilityReport.make(
            minimumOSSatisfied: true,
            architecture: "arm64",
            supportedArchitecture: true,
            appDirectoryWritable: true,
            keychainAvailable: true,
            notificationStatus: .authorized,
            providerChecks: [:]
        )
        #expect(state.treatsEnvironmentAsReady(ready))
        state.completeCurrentAndAdvance()

        state.selectProvider("claude")
        state.completeCurrentAndAdvance()
        state.completeCurrentAndAdvance()
        state.recordFirstRefresh(.success)
        state.completeCurrentAndAdvance()
        try store.save(state)

        let reloaded = store.load()
        #expect(reloaded.isCompleted)
        #expect(reloaded.shouldPresentOnFirstLaunch == false)
        #expect(reloaded.selectedProviderId == "claude")
        #expect(reloaded.lastRefreshOutcome == .success)
        #expect(FileManager.default.fileExists(atPath: env.recordURL.path))
        #expect(env.recordURL.path.hasPrefix(env.configRoot.path))
    }

    @Test
    func `completed user does not get the guide again after restart`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        var state = FirstLaunchState.fresh
        state.finish()
        try FirstLaunchStore(configRoot: env.configRoot).save(state)

        let nextLaunch = FirstLaunchStore(configRoot: env.configRoot).load()
        #expect(nextLaunch.isCompleted)
        #expect(nextLaunch.shouldPresentOnFirstLaunch == false)
        #expect(nextLaunch.shouldPresent(launchMode: .normal) == false)
        #expect(nextLaunch.canContinueFromSettings == false)
    }

    @Test
    func `skip keeps continue-onboarding and resume after restart`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let store = FirstLaunchStore(configRoot: env.configRoot)
        var state = store.load()
        state.completeCurrentAndAdvance()
        state.skip()
        try store.save(state)

        let afterSkip = store.load()
        #expect(afterSkip.shouldPresentOnFirstLaunch == false)
        #expect(afterSkip.canContinueFromSettings)
        #expect(afterSkip.currentStep == .compatibility)

        var resumed = afterSkip
        resumed.resumeFromSettings()
        try store.save(resumed)

        let afterResume = store.load()
        #expect(afterResume.skipped == false)
        #expect(afterResume.shouldPresentOnFirstLaunch)
        #expect(afterResume.currentStep == .compatibility)
    }

    @Test
    func `incompatible environment is not reported ready`() async throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let checker = CompatibilityChecker(
            environment: CompatibilityEnvironment(
                osMajorVersion: 14,
                architecture: "i386",
                appDirectory: env.configRoot,
                isDirectoryWritable: { _ in false },
                keychainAvailable: { false },
                notificationStatus: { .denied },
                locateCLI: { _ in nil },
                enabledProviders: {
                    [EnabledProviderDependency(providerId: "claude", cliName: "claude")]
                }
            )
        )
        let report = await checker.check()
        #expect(report.minimumOSSatisfied == false)
        #expect(report.supportedArchitecture == false)
        #expect(report.appDirectoryWritable == false)
        #expect(report.keychainAvailable == false)
        #expect(report.isReady == false)
        #expect(FirstLaunchState.fresh.treatsEnvironmentAsReady(report) == false)
        #expect(OnboardingFollowUp.actions(report: report, missingCredential: true, outcome: .needsConfiguration) == [
            .openSystemSettings, .openConfiguration, .viewHelp, .recheck,
        ])
    }

    @Test
    func `existing settings or prior ready clean markers grandfather as completed`() throws {
        let withSettings = try OnboardingHarness.make()
        defer { withSettings.cleanup() }
        try Data("{}".utf8).write(to: withSettings.settingsURL)
        let settingsStore = FirstLaunchStore(configRoot: withSettings.configRoot)
        let fromSettings = settingsStore.load()
        #expect(fromSettings.isCompleted)
        #expect(fromSettings.shouldPresentOnFirstLaunch == false)
        #expect(FileManager.default.fileExists(atPath: withSettings.recordURL.path))

        let withReady = try OnboardingHarness.make()
        defer { withReady.cleanup() }
        try FileManager.default.createDirectory(at: withReady.recoveryDirectory, withIntermediateDirectories: true)
        try Data("1".utf8).write(to: withReady.readyMarkerURL)
        #expect(FirstLaunchStore(configRoot: withReady.configRoot).load().isCompleted)

        let withClean = try OnboardingHarness.make()
        defer { withClean.cleanup() }
        try FileManager.default.createDirectory(at: withClean.recoveryDirectory, withIntermediateDirectories: true)
        try Data("1".utf8).write(to: withClean.cleanMarkerURL)
        #expect(FirstLaunchStore(configRoot: withClean.configRoot).load().isCompleted)
    }

    @Test
    func `settings created after store init do not grandfather a new install`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let store = FirstLaunchStore(configRoot: env.configRoot)
        try Data("{\"schemaVersion\":2}".utf8).write(to: env.settingsURL)
        let state = store.load()
        #expect(state == .fresh)
        #expect(state.shouldPresent(launchMode: .normal))
    }

    @Test
    func `in-progress first-launch record is not overwritten by existing settings`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        try FirstLaunchStore(configRoot: env.configRoot).save(state)
        try Data("{}".utf8).write(to: env.settingsURL)

        let reloaded = FirstLaunchStore(configRoot: env.configRoot).load()
        #expect(reloaded.currentStep == .compatibility)
        #expect(reloaded.isCompleted == false)
        #expect(reloaded.shouldPresentOnFirstLaunch)
    }

    @Test
    func `continuing first refresh without a check does not complete onboarding`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let store = FirstLaunchStore(configRoot: env.configRoot)
        var state = store.load()
        state.currentStep = .firstRefresh
        state.selectProvider("claude")
        #expect(state.canAdvance == false)
        state.completeCurrentAndAdvance()
        try store.save(state)

        let reloaded = store.load()
        #expect(reloaded.isCompleted == false)
        #expect(reloaded.currentStep == .firstRefresh)
        #expect(reloaded.canContinueFromSettings)
    }

    @Test
    func `safe mode suppresses first-launch presentation`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let state = FirstLaunchStore(configRoot: env.configRoot).load()
        #expect(state.shouldPresent(launchMode: .safeMode(reason: .settingsDecodeFailed)) == false)
        #expect(state.shouldPresent(launchMode: .safeMode(reason: .migrationFailed)) == false)
        #expect(state.shouldPresent(launchMode: .normal))
    }

    @Test
    func `store persists only step completion and strips secret keys`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        try Data("""
        {
          "currentStep": "chooseProvider",
          "completedSteps": ["privacy", "compatibility"],
          "skipped": false,
          "selectedProviderId": "claude",
          "apiKey": "sk-secret",
          "token": "oauth-token",
          "cookie": "session=1",
          "password": "hunter2"
        }
        """.utf8).write(to: env.recordURL)

        let store = FirstLaunchStore(configRoot: env.configRoot)
        let loaded = store.load()
        #expect(loaded.currentStep == .chooseProvider)
        #expect(loaded.selectedProviderId == "claude")
        #expect(loaded.completedSteps == [.privacy, .compatibility])
        try store.save(loaded)

        let raw = try Data(contentsOf: env.recordURL)
        let json = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(Set(json.keys).isSubset(of: FirstLaunchState.persistedKeys))
        let text = String(decoding: raw, as: UTF8.self).lowercased()
        for forbidden in ["apikey", "api_key", "token", "cookie", "password", "sk-secret", "oauth"] {
            #expect(text.contains(forbidden) == false)
        }
    }

    @Test
    func `production factory uses the explicit AppIdentity directory not an implicit home path`() throws {
        let env = try OnboardingHarness.make()
        defer { env.cleanup() }

        let store = FirstLaunchStore.usingAppIdentity(env.configRoot)
        #expect(store.configRoot == env.configRoot)
        #expect(store.configRoot != AppIdentity.configDirectoryURL)

        var state = store.load()
        state.selectProvider("kimi")
        try store.save(state)
        #expect(FileManager.default.fileExists(atPath: env.recordURL.path))
        #expect(store.fileURL.path.hasPrefix(env.configRoot.path))
    }
}

private enum OnboardingHarness {
    struct Env {
        let parent: URL
        let configRoot: URL
        var recordURL: URL { configRoot.appendingPathComponent(FirstLaunchStore.fileName) }
        var settingsURL: URL { configRoot.appendingPathComponent("settings.json") }
        var recoveryDirectory: URL {
            configRoot.appendingPathComponent(CrashRecoveryMarker.directoryName, isDirectory: true)
        }
        var readyMarkerURL: URL {
            recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.ready)
        }
        var cleanMarkerURL: URL {
            recoveryDirectory.appendingPathComponent(CrashRecoveryMarker.clean)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    static func make() throws -> Env {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartquota-onboarding-spec-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("injected-config", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(parent: parent, configRoot: root)
    }
}

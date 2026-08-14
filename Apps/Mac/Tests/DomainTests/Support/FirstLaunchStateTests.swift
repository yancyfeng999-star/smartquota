import Testing
import Foundation
@testable import Domain

@Suite("FirstLaunchState Tests")
struct FirstLaunchStateTests {

    @Test
    func `fresh first launch starts at privacy and should present`() {
        let state = FirstLaunchState.fresh
        #expect(state.currentStep == .privacy)
        #expect(state.completedSteps.isEmpty)
        #expect(state.skipped == false)
        #expect(state.isCompleted == false)
        #expect(state.shouldPresentOnFirstLaunch)
        #expect(state.canContinueFromSettings)
        #expect(state.selectedProviderId == nil)
        #expect(state.lastRefreshOutcome == nil)
    }

    @Test
    func `onboarding steps follow the first-launch flow`() {
        #expect(OnboardingStep.ordered == [
            .privacy,
            .compatibility,
            .chooseProvider,
            .configureProvider,
            .firstRefresh,
            .completed,
        ])
        #expect(OnboardingStep.privacy.advanced() == .compatibility)
        #expect(OnboardingStep.firstRefresh.advanced() == .completed)
        #expect(OnboardingStep.completed.advanced() == .completed)
        #expect(OnboardingStep.privacy.retreated() == .privacy)
        #expect(OnboardingStep.compatibility.retreated() == .privacy)
    }

    @Test
    func `completing each step advances and remembers completion only`() {
        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .compatibility)
        #expect(state.completedSteps == [.privacy])

        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .chooseProvider)
        #expect(state.completedSteps == [.privacy, .compatibility])

        state.selectProvider("claude")
        #expect(state.canAdvance)
        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .configureProvider)

        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .firstRefresh)

        state.recordFirstRefresh(.success)
        state.completeCurrentAndAdvance()
        #expect(state.currentStep == .completed)
        #expect(state.isCompleted)
        #expect(state.shouldPresentOnFirstLaunch == false)
        #expect(state.canContinueFromSettings == false)
    }

    @Test
    func `choose provider cannot advance until a membership is selected`() {
        var state = FirstLaunchState.fresh
        state.currentStep = .chooseProvider
        #expect(state.canAdvance == false)
        state.selectProvider("codex")
        #expect(state.selectedProviderId == "codex")
        #expect(state.canAdvance)
    }

    @Test
    func `skip dismisses auto present but keeps continue from settings`() {
        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        state.skip()
        #expect(state.skipped)
        #expect(state.isCompleted == false)
        #expect(state.shouldPresentOnFirstLaunch == false)
        #expect(state.canContinueFromSettings)
        #expect(state.currentStep == .compatibility)
    }

    @Test
    func `resume from settings clears skip and re-enters the saved step`() {
        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        state.skip()
        state.resumeFromSettings()
        #expect(state.skipped == false)
        #expect(state.shouldPresentOnFirstLaunch)
        #expect(state.currentStep == .compatibility)
    }

    @Test
    func `back returns to the previous step without completing`() {
        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        state.completeCurrentAndAdvance()
        state.goBack()
        #expect(state.currentStep == .compatibility)
        #expect(state.completedSteps.contains(.privacy))
        state.goBack()
        #expect(state.currentStep == .privacy)
        state.goBack()
        #expect(state.currentStep == .privacy)
    }

    @Test
    func `safe mode never presents first-launch onboarding`() {
        let fresh = FirstLaunchState.fresh
        #expect(fresh.shouldPresent(launchMode: .normal))
        #expect(fresh.shouldPresent(launchMode: .safeMode(reason: .migrationFailed)) == false)
        #expect(fresh.shouldPresent(launchMode: .safeMode(reason: .settingsDecodeFailed)) == false)
        #expect(fresh.shouldPresent(launchMode: .safeMode(reason: .previousLaunchDidNotFinish)) == false)

        var skipped = FirstLaunchState.fresh
        skipped.skip()
        #expect(skipped.shouldPresent(launchMode: .normal) == false)
    }

    @Test
    func `closing the guide does not complete skip or quit`() {
        var state = FirstLaunchState.fresh
        state.completeCurrentAndAdvance()
        state.dismissWindow()
        #expect(state.skipped == false)
        #expect(state.isCompleted == false)
        #expect(state.shouldPresentOnFirstLaunch)
        #expect(state.currentStep == .compatibility)
    }

    @Test
    func `first refresh classifies success not logged in and needs configuration`() {
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())
        #expect(FirstRefreshOutcome.classify(snapshot: snapshot, error: nil) == .success)
        #expect(FirstRefreshOutcome.classify(snapshot: nil, error: ProbeError.authenticationRequired) == .notLoggedIn)
        #expect(FirstRefreshOutcome.classify(snapshot: nil, error: ProbeError.sessionExpired(hint: nil)) == .notLoggedIn)
        #expect(FirstRefreshOutcome.classify(snapshot: nil, error: ProbeError.cliNotFound("claude")) == .needsConfiguration)
        #expect(FirstRefreshOutcome.classify(snapshot: nil, error: nil) == .needsConfiguration)

        #expect(FirstRefreshOutcome.success.messageKey == "onboard.refresh.success")
        #expect(FirstRefreshOutcome.notLoggedIn.messageKey == "onboard.refresh.not_logged_in")
        #expect(FirstRefreshOutcome.needsConfiguration.messageKey == "onboard.refresh.needs_config")
        #expect(FirstRefreshOutcome.success.nextStepKey == "onboard.refresh.next_success")
        #expect(FirstRefreshOutcome.notLoggedIn.nextStepKey == "onboard.refresh.next_login")
        #expect(FirstRefreshOutcome.needsConfiguration.nextStepKey == "onboard.refresh.next_config")
    }

    @Test
    func `missing CLI key or permission offers open config help and recheck`() {
        let ready = CompatibilityReport.make(
            minimumOSSatisfied: true,
            architecture: "arm64",
            supportedArchitecture: true,
            appDirectoryWritable: true,
            keychainAvailable: true,
            notificationStatus: .authorized,
            providerChecks: [:]
        )
        #expect(OnboardingFollowUp.actions(report: ready, missingCredential: false, outcome: .success).isEmpty)

        let missingCLI = CompatibilityReport.make(
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
            ]
        )
        #expect(OnboardingFollowUp.actions(report: missingCLI, missingCredential: false, outcome: nil) == [
            .openConfiguration, .viewHelp, .recheck,
        ])

        let denied = CompatibilityReport.make(
            minimumOSSatisfied: true,
            architecture: "x86_64",
            supportedArchitecture: true,
            appDirectoryWritable: true,
            keychainAvailable: false,
            notificationStatus: .denied,
            providerChecks: [:]
        )
        #expect(denied.isReady == false)
        #expect(OnboardingFollowUp.actions(report: denied, missingCredential: false, outcome: nil) == [
            .openConfiguration, .viewHelp, .recheck,
        ])

        #expect(OnboardingFollowUp.actions(report: ready, missingCredential: true, outcome: nil) == [
            .openConfiguration, .viewHelp, .recheck,
        ])
        #expect(OnboardingFollowUp.actions(report: ready, missingCredential: false, outcome: .notLoggedIn) == [
            .openConfiguration, .viewHelp, .recheck,
        ])
    }

    @Test
    func `incompatible report is never treated as ready`() {
        let report = CompatibilityReport.make(
            minimumOSSatisfied: false,
            architecture: "i386",
            supportedArchitecture: false,
            appDirectoryWritable: false,
            keychainAvailable: false,
            notificationStatus: .denied,
            providerChecks: [:]
        )
        #expect(report.isReady == false)
        #expect(FirstLaunchState.fresh.treatsEnvironmentAsReady(report) == false)
    }

    @Test
    func `persisted payload encodes only step fields and never secret keys`() throws {
        var state = FirstLaunchState.fresh
        state.selectProvider("claude")
        state.recordFirstRefresh(.success)
        state.completeCurrentAndAdvance()

        let data = try JSONEncoder().encode(state)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys).isSubset(of: FirstLaunchState.persistedKeys))

        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in ["apikey", "api_key", "token", "cookie", "password", "secret", "keychain"] {
            #expect(text.contains(forbidden) == false)
        }
    }
}

import Foundation

public enum OnboardingStep: String, Codable, Sendable, CaseIterable {
    case privacy
    case compatibility
    case chooseProvider
    case configureProvider
    case firstRefresh
    case completed

    public static let ordered: [OnboardingStep] = [
        .privacy, .compatibility, .chooseProvider, .configureProvider, .firstRefresh, .completed,
    ]

    public func advanced() -> OnboardingStep {
        guard let index = Self.ordered.firstIndex(of: self) else { return .completed }
        let next = index + 1
        return next < Self.ordered.count ? Self.ordered[next] : .completed
    }

    public func retreated() -> OnboardingStep {
        guard let index = Self.ordered.firstIndex(of: self), index > 0 else { return .privacy }
        return Self.ordered[index - 1]
    }
}

public enum FirstRefreshOutcome: String, Codable, Sendable {
    case success
    case notLoggedIn
    case missingCLI
    case needsConfiguration
    case checkFailed

    public var messageKey: String {
        switch self {
        case .success: "onboard.refresh.success"
        case .notLoggedIn: "onboard.refresh.not_logged_in"
        case .missingCLI: "onboard.refresh.missing_cli"
        case .needsConfiguration: "onboard.refresh.needs_config"
        case .checkFailed: "onboard.refresh.check_failed"
        }
    }

    public var nextStepKey: String {
        switch self {
        case .success: "onboard.refresh.next_success"
        case .notLoggedIn: "onboard.refresh.next_login"
        case .missingCLI: "onboard.refresh.next_missing_cli"
        case .needsConfiguration: "onboard.refresh.next_config"
        case .checkFailed: "onboard.refresh.next_check_failed"
        }
    }

    public static func classify(snapshot: UsageSnapshot?, error: Error?) -> FirstRefreshOutcome {
        if let probe = error as? ProbeError {
            switch probe {
            case .authenticationRequired, .sessionExpired:
                return .notLoggedIn
            case .cliNotFound:
                return .missingCLI
            case .parseFailed, .timeout, .executionFailed, .rateLimited, .noData:
                return .checkFailed
            case .updateRequired, .folderTrustRequired, .subscriptionRequired:
                return .needsConfiguration
            }
        }
        if error != nil { return .checkFailed }
        if snapshot != nil { return .success }
        return .needsConfiguration
    }
}

public enum OnboardingFollowUpAction: String, Codable, Sendable, CaseIterable {
    case openSystemSettings
    case openConfiguration
    case viewHelp
    case recheck
}

public enum OnboardingFollowUp: Sendable {
    public static func actions(
        report: CompatibilityReport?,
        missingCredential: Bool,
        outcome: FirstRefreshOutcome?,
        hasSelectedProvider: Bool = false
    ) -> [OnboardingFollowUpAction] {
        let permissionIssue = report.map {
            !$0.keychainAvailable || !$0.notificationStatus.isGranted
        } ?? false
        let reportMissingCLI = report?.hasMissingEnabledCLI == true
        let setupIssue = missingCredential
            || outcome == .notLoggedIn
            || outcome == .needsConfiguration
            || outcome == .missingCLI
            || (reportMissingCLI && hasSelectedProvider)
        let checkFailed = outcome == .checkFailed

        var actions: [OnboardingFollowUpAction] = []
        if permissionIssue {
            actions.append(.openSystemSettings)
        }
        if setupIssue {
            actions.append(.openConfiguration)
        }
        if permissionIssue || setupIssue || checkFailed || reportMissingCLI {
            actions.append(.viewHelp)
            actions.append(.recheck)
        }
        return actions
    }
}

/// Inputs captured before launch mutation (migrate / beginLaunch) so existing
/// 0.3.29 installs can be grandfathered without treating a just-written
/// `settings.json` as a prior install.
public struct FirstLaunchSignals: Sendable, Equatable {
    public var recordExists: Bool
    public var settingsFileExisted: Bool
    public var priorReadyMarkerExisted: Bool
    public var priorCleanMarkerExisted: Bool

    public init(
        recordExists: Bool = false,
        settingsFileExisted: Bool = false,
        priorReadyMarkerExisted: Bool = false,
        priorCleanMarkerExisted: Bool = false
    ) {
        self.recordExists = recordExists
        self.settingsFileExisted = settingsFileExisted
        self.priorReadyMarkerExisted = priorReadyMarkerExisted
        self.priorCleanMarkerExisted = priorCleanMarkerExisted
    }

    public var shouldTreatAsCompletedInstall: Bool {
        !recordExists
            && (settingsFileExisted || priorReadyMarkerExisted || priorCleanMarkerExisted)
    }
}

/// First-launch progress. Persist only these fields — never API keys, tokens, or cookies.
public struct FirstLaunchState: Codable, Equatable, Sendable {
    public static let persistedKeys: Set<String> = [
        "currentStep", "completedSteps", "skipped", "selectedProviderId", "lastRefreshOutcome",
    ]

    public var currentStep: OnboardingStep
    public var completedSteps: [OnboardingStep]
    public var skipped: Bool
    public var selectedProviderId: String?
    public var lastRefreshOutcome: FirstRefreshOutcome?

    public static let fresh = FirstLaunchState(
        currentStep: .privacy,
        completedSteps: [],
        skipped: false,
        selectedProviderId: nil,
        lastRefreshOutcome: nil
    )

    public init(
        currentStep: OnboardingStep,
        completedSteps: [OnboardingStep],
        skipped: Bool,
        selectedProviderId: String?,
        lastRefreshOutcome: FirstRefreshOutcome?
    ) {
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.skipped = skipped
        self.selectedProviderId = selectedProviderId
        self.lastRefreshOutcome = lastRefreshOutcome
    }

    enum CodingKeys: String, CodingKey {
        case currentStep
        case completedSteps
        case skipped
        case selectedProviderId
        case lastRefreshOutcome
    }

    public var isCompleted: Bool {
        currentStep == .completed || completedSteps.contains(.completed)
    }

    public var shouldPresentOnFirstLaunch: Bool {
        !isCompleted && !skipped
    }

    public var canContinueFromSettings: Bool {
        !isCompleted
    }

    public func shouldPresent(launchMode: AppLaunchMode) -> Bool {
        if case .safeMode = launchMode { return false }
        return shouldPresentOnFirstLaunch
    }

    public var canAdvance: Bool {
        switch currentStep {
        case .chooseProvider:
            return selectedProviderId?.isEmpty == false
        case .firstRefresh:
            return lastRefreshOutcome != nil
        case .completed:
            return false
        default:
            return true
        }
    }

    /// Compatibility “打开配置” never skips membership selection.
    public var configurationDestination: OnboardingStep {
        selectedProviderId?.isEmpty == false ? .configureProvider : .chooseProvider
    }

    public static func resolved(
        from signals: FirstLaunchSignals,
        recorded: FirstLaunchState?
    ) -> FirstLaunchState {
        if let recorded { return recorded }
        if signals.shouldTreatAsCompletedInstall {
            var completed = FirstLaunchState.fresh
            completed.finish()
            return completed
        }
        return .fresh
    }

    public mutating func completeCurrentAndAdvance() {
        guard canAdvance else { return }
        if currentStep != .completed, !completedSteps.contains(currentStep) {
            completedSteps.append(currentStep)
        }
        currentStep = currentStep.advanced()
        skipped = false
        if currentStep == .completed, !completedSteps.contains(.completed) {
            completedSteps.append(.completed)
        }
    }

    public mutating func goBack() {
        currentStep = currentStep.retreated()
    }

    public mutating func skip() {
        guard !isCompleted else { return }
        skipped = true
    }

    public mutating func resumeFromSettings() {
        guard !isCompleted else { return }
        skipped = false
    }

    /// Closing the guide hides the window only. It must not skip, complete, or quit.
    public mutating func dismissWindow() {}

    public mutating func selectProvider(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedProviderId = trimmed.isEmpty ? nil : trimmed
    }

    public mutating func recordFirstRefresh(_ outcome: FirstRefreshOutcome) {
        lastRefreshOutcome = outcome
    }

    public mutating func finish() {
        currentStep = .completed
        if !completedSteps.contains(.completed) {
            completedSteps.append(.completed)
        }
        skipped = false
    }

    public func treatsEnvironmentAsReady(_ report: CompatibilityReport) -> Bool {
        report.isReady
    }
}

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
    case needsConfiguration

    public var messageKey: String {
        switch self {
        case .success: "onboard.refresh.success"
        case .notLoggedIn: "onboard.refresh.not_logged_in"
        case .needsConfiguration: "onboard.refresh.needs_config"
        }
    }

    public var nextStepKey: String {
        switch self {
        case .success: "onboard.refresh.next_success"
        case .notLoggedIn: "onboard.refresh.next_login"
        case .needsConfiguration: "onboard.refresh.next_config"
        }
    }

    public static func classify(snapshot: UsageSnapshot?, error: Error?) -> FirstRefreshOutcome {
        if let probe = error as? ProbeError {
            switch probe {
            case .authenticationRequired, .sessionExpired:
                return .notLoggedIn
            default:
                return .needsConfiguration
            }
        }
        if error != nil { return .needsConfiguration }
        if snapshot != nil { return .success }
        return .needsConfiguration
    }
}

public enum OnboardingFollowUpAction: String, Codable, Sendable, CaseIterable {
    case openConfiguration
    case viewHelp
    case recheck
}

public enum OnboardingFollowUp: Sendable {
    public static func actions(
        report: CompatibilityReport?,
        missingCredential: Bool,
        outcome: FirstRefreshOutcome?
    ) -> [OnboardingFollowUpAction] {
        let reportNeeds: Bool
        if let report {
            reportNeeds = report.hasMissingEnabledCLI
                || !report.keychainAvailable
                || !report.notificationStatus.isGranted
                || !report.appDirectoryWritable
        } else {
            reportNeeds = false
        }
        let refreshNeeds = outcome == .notLoggedIn || outcome == .needsConfiguration
        if reportNeeds || missingCredential || refreshNeeds {
            return Array(OnboardingFollowUpAction.allCases)
        }
        return []
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
        case .completed:
            return false
        default:
            return true
        }
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

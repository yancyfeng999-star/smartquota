import Foundation
import Domain
import Mockable

// MARK: - Internal Protocol (for testability)

/// Internal protocol for sending system alerts. Enables testing without UNUserNotificationCenter.
@Mockable
protocol AlertSender: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, categoryIdentifier: String) async throws
}

// MARK: - NotificationAlerter

/// Alerts users when their AI quota status degrades, or when user-configured
/// 5h/7d remaining thresholds are crossed, or weekly reset is near with unused quota.
public final class NotificationAlerter: QuotaAlerter, @unchecked Sendable {

    private let alertSender: AlertSender
    private let thresholdState = ThresholdAlertState()
    /// Reads live thresholds from App settings (MainActor).
    private let thresholdReader: @Sendable () async -> ThresholdConfig

    public struct ThresholdConfig: Sendable {
        public var enabled: Bool
        public var sessionThreshold: Double
        public var weeklyThreshold: Double
        public var nearResetHours: Double
        public var underuseRemaining: Double

        public init(
            enabled: Bool,
            sessionThreshold: Double,
            weeklyThreshold: Double,
            nearResetHours: Double,
            underuseRemaining: Double
        ) {
            self.enabled = enabled
            self.sessionThreshold = sessionThreshold
            self.weeklyThreshold = weeklyThreshold
            self.nearResetHours = nearResetHours
            self.underuseRemaining = underuseRemaining
        }

        public static let `default` = ThresholdConfig(
            enabled: true,
            sessionThreshold: QuotaAlertPolicy.defaultSessionThreshold,
            weeklyThreshold: QuotaAlertPolicy.defaultWeeklyThreshold,
            nearResetHours: QuotaAlertPolicy.defaultNearResetHours,
            underuseRemaining: QuotaAlertPolicy.defaultUnderuseRemaining
        )
    }

    /// Public initializer — thresholds come from `thresholdReader` (wired in App to settings).
    /// Defaults are used until the app injects live settings.
    public init(
        thresholdReader: (@Sendable () async -> ThresholdConfig)? = nil
    ) {
        self.alertSender = SystemAlertSender()
        self.thresholdReader = thresholdReader ?? { .default }
    }

    /// Internal initializer for testing
    init(alertSender: AlertSender, thresholdReader: @escaping @Sendable () async -> ThresholdConfig = { .default }) {
        self.alertSender = alertSender
        self.thresholdReader = thresholdReader
    }

    // MARK: - Public API

    /// Requests permission to send quota alerts.
    public func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - QuotaAlerter

    public func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
        AppLog.notifications.debug("Status change: \(providerId) \(previousStatus) -> \(currentStatus)")

        // Only alert on degradation (getting worse)
        guard currentStatus > previousStatus else {
            AppLog.notifications.debug("Status improved or same, skipping alert")
            return
        }

        guard shouldAlert(for: currentStatus) else {
            AppLog.notifications.debug("Status \(currentStatus) does not require alert")
            return
        }

        let providerName = providerDisplayName(for: providerId)
        let title = "\(providerName) 额度提醒"
        let body = alertBody(for: currentStatus, providerName: providerName)

        AppLog.notifications.notice("Sending quota alert for \(providerId): \(currentStatus)")

        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: "QUOTA_ALERT")
            AppLog.notifications.info("Alert sent successfully")
        } catch {
            AppLog.notifications.error("Failed to send alert: \(error.localizedDescription)")
        }
    }

    public func evaluateSnapshotAlerts(providerId: String, accountId: String, snapshot: UsageSnapshot) async {
        let config = await thresholdReader()
        guard config.enabled else { return }

        let session = snapshot.sessionQuota?.percentRemaining
        let weekly = snapshot.weeklyQuota?.percentRemaining
        let weeklyReset = snapshot.weeklyQuota?.resetsAt

        let evaluations = QuotaAlertPolicy.evaluate(
            sessionRemaining: session,
            weeklyRemaining: weekly,
            weeklyResetsAt: weeklyReset,
            sessionThreshold: config.sessionThreshold,
            weeklyThreshold: config.weeklyThreshold,
            nearResetHours: config.nearResetHours,
            underuseRemaining: config.underuseRemaining
        )

        let name = providerDisplayName(for: providerId)
        for evaluation in evaluations {
            // Alert key uses `providerId.accountId:kind` format for per-account debouncing
            let key = "\(providerId).\(accountId):\(evaluation.kind.rawValue)"
            guard await thresholdState.shouldFire(key: key) else { continue }

            let (title, body) = thresholdCopy(name: name, evaluation: evaluation)
            do {
                try await alertSender.send(
                    title: title,
                    body: body,
                    categoryIdentifier: "QUOTA_THRESHOLD"
                )
            } catch {
                AppLog.notifications.error("Threshold alert failed: \(error.localizedDescription)")
            }
        }
    }

    private func thresholdCopy(
        name: String,
        evaluation: QuotaAlertPolicy.Evaluation
    ) -> (String, String) {
        let rem = Int(evaluation.remaining.rounded())
        switch evaluation.kind {
        case .sessionLow:
            return (
                "\(name) · 5 小时额度偏低",
                "剩余约 \(rem)%（阈值 \(Int(evaluation.threshold))%）。建议放慢使用或等待重置。"
            )
        case .weeklyLow:
            return (
                "\(name) · 7 天额度偏低",
                "剩余约 \(rem)%（阈值 \(Int(evaluation.threshold))%）。注意本周用量。"
            )
        case .weeklyUnderuseNearReset:
            let when: String = {
                guard let d = evaluation.resetsAt else { return "即将" }
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = "M月d日 HH:mm"
                return f.string(from: d)
            }()
            return (
                "\(name) · 7 天额度快重置",
                "重置时间 \(when)，当前仍剩约 \(rem)%。有需要可以多用一些，避免浪费。"
            )
        }
    }

    // MARK: - Helpers (internal for testability)

    func shouldAlert(for status: QuotaStatus) -> Bool {
        switch status {
        case .warning, .critical, .depleted:
            return true
        case .healthy:
            return false
        }
    }

    func providerDisplayName(for providerId: String) -> String {
        switch providerId {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "copilot": return "GitHub Copilot"
        case "antigravity": return "Antigravity"
        case "zai": return "Z.ai"
        case "bedrock": return "AWS Bedrock"
        case "minimax": return "MiniMax"
        case "mimo": return "Xiaomi MiMo"
        case "alibaba": return "Alibaba"
        case "opencode-go": return "OpenCode Go"
        case "omp": return "Oh My Pi"
        case "grok": return "Grok"
        default: return providerId.capitalized
        }
    }

    func alertBody(for status: QuotaStatus, providerName: String) -> String {
        switch status {
        case .warning:
            return "Your \(providerName) quota is running low. Consider pacing your usage."
        case .critical:
            return "Your \(providerName) quota is critically low! Save important work."
        case .depleted:
            return "Your \(providerName) quota is depleted. Usage may be blocked."
        case .healthy:
            return "Your \(providerName) quota has recovered."
        }
    }
}

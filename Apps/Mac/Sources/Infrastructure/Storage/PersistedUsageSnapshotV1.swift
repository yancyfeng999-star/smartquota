import Foundation
import Domain

/// Codable persistence model for `UsageSnapshot`.
///
/// Maps between the domain `UsageSnapshot` (non-Codable) and on-disk JSON.
/// Version 1 schema — bump the version when the shape changes.
struct PersistedUsageSnapshotV1: Codable {
    let version: Int
    let providerId: String
    let quotas: [PersistedQuota]
    let capturedAt: Date
    let accountEmail: String?
    let accountOrganization: String?
    let loginMethod: String?
    let accountTier: PersistedAccountTier?
    let costUsage: PersistedCostUsage?
    let bedrockUsage: PersistedBedrockUsageSummary?
    let dailyUsageReport: PersistedDailyUsageReport?
    let extensionMetrics: [PersistedExtensionMetric]?
    let accountExternalId: String?
    let accountIdentitySource: PersistedAccountIdentitySource?

    // MARK: - Domain ↔ Persisted Mapping

    static func from(_ snapshot: UsageSnapshot) -> PersistedUsageSnapshotV1 {
        PersistedUsageSnapshotV1(
            version: 1,
            providerId: snapshot.providerId,
            quotas: snapshot.quotas.map(PersistedQuota.from),
            capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier.flatMap(PersistedAccountTier.from),
            costUsage: snapshot.costUsage.flatMap(PersistedCostUsage.from),
            bedrockUsage: snapshot.bedrockUsage.flatMap(PersistedBedrockUsageSummary.from),
            dailyUsageReport: snapshot.dailyUsageReport.flatMap(PersistedDailyUsageReport.from),
            extensionMetrics: snapshot.extensionMetrics?.map(PersistedExtensionMetric.from),
            accountExternalId: snapshot.accountExternalId,
            accountIdentitySource: snapshot.accountIdentitySource.flatMap(PersistedAccountIdentitySource.from)
        )
    }

    func toDomain() -> UsageSnapshot {
        UsageSnapshot(
            providerId: providerId,
            quotas: quotas.map(\.asDomain),
            capturedAt: capturedAt,
            accountEmail: accountEmail,
            accountOrganization: accountOrganization,
            loginMethod: loginMethod,
            accountTier: accountTier?.asDomain,
            costUsage: costUsage?.asDomain,
            bedrockUsage: bedrockUsage?.asDomain,
            dailyUsageReport: dailyUsageReport?.asDomain,
            extensionMetrics: extensionMetrics?.map(\.asDomain),
            accountExternalId: accountExternalId,
            accountIdentitySource: accountIdentitySource?.asDomain
        )
    }
}

// MARK: - Quota

struct PersistedQuota: Codable {
    let percentRemaining: Double
    let quotaType: PersistedQuotaType
    let providerId: String
    let resetsAt: Date?
    let resetText: String?
    let windowDuration: Double?
    let dollarRemaining: Double?
    let dollarUsed: Double?
    let dollarCap: Double?
    let group: String?
    let compactTitle: String?
    let menuBarTitle: String?

    static func from(_ quota: UsageQuota) -> PersistedQuota {
        PersistedQuota(
            percentRemaining: quota.percentRemaining,
            quotaType: PersistedQuotaType.from(quota.quotaType),
            providerId: quota.providerId,
            resetsAt: quota.resetsAt,
            resetText: quota.resetText,
            windowDuration: quota.windowDuration,
            dollarRemaining: quota.dollarRemaining.flatMap { NSDecimalNumber(decimal: $0).doubleValue },
            dollarUsed: quota.dollarUsed.flatMap { NSDecimalNumber(decimal: $0).doubleValue },
            dollarCap: quota.dollarCap.flatMap { NSDecimalNumber(decimal: $0).doubleValue },
            group: quota.group,
            compactTitle: quota.compactTitle,
            menuBarTitle: quota.menuBarTitle
        )
    }

    var asDomain: UsageQuota {
        UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: quotaType.asDomain,
            providerId: providerId,
            resetsAt: resetsAt,
            resetText: resetText,
            windowDuration: windowDuration,
            dollarRemaining: dollarRemaining.map { Decimal($0) },
            dollarUsed: dollarUsed.map { Decimal($0) },
            dollarCap: dollarCap.map { Decimal($0) },
            group: group,
            compactTitle: compactTitle,
            menuBarTitle: menuBarTitle
        )
    }
}

// MARK: - QuotaType

enum PersistedQuotaType: Codable {
    case session
    case weekly
    case modelSpecific(String)
    case timeLimit(String)

    static func from(_ type: QuotaType) -> PersistedQuotaType {
        switch type {
        case .session: return .session
        case .weekly: return .weekly
        case .modelSpecific(let name): return .modelSpecific(name)
        case .timeLimit(let name): return .timeLimit(name)
        }
    }

    var asDomain: QuotaType {
        switch self {
        case .session: return .session
        case .weekly: return .weekly
        case .modelSpecific(let name): return .modelSpecific(name)
        case .timeLimit(let name): return .timeLimit(name)
        }
    }
}

// MARK: - AccountTier

enum PersistedAccountTier: Codable {
    case claudeMax
    case claudePro
    case claudeApi
    case custom(String)

    static func from(_ tier: AccountTier) -> PersistedAccountTier? {
        switch tier {
        case .claudeMax: return .claudeMax
        case .claudePro: return .claudePro
        case .claudeApi: return .claudeApi
        case .custom(let badge): return .custom(badge)
        }
    }

    var asDomain: AccountTier {
        switch self {
        case .claudeMax: return .claudeMax
        case .claudePro: return .claudePro
        case .claudeApi: return .claudeApi
        case .custom(let badge): return .custom(badge)
        }
    }
}

// MARK: - AccountIdentitySource

enum PersistedAccountIdentitySource: Codable {
    case email
    case cliProfile
    case apiToken
    case userDefined
    case external

    static func from(_ source: AccountIdentitySource) -> PersistedAccountIdentitySource? {
        switch source {
        case .email: return .email
        case .cliProfile: return .cliProfile
        case .apiToken: return .apiToken
        case .userDefined: return .userDefined
        case .external: return .external
        }
    }

    var asDomain: AccountIdentitySource {
        switch self {
        case .email: return .email
        case .cliProfile: return .cliProfile
        case .apiToken: return .apiToken
        case .userDefined: return .userDefined
        case .external: return .external
        }
    }
}

// MARK: - CostUsage

struct PersistedCostUsage: Codable {
    let kind: PersistedCostKind
    let totalCost: Double
    let budget: Double?
    let apiDuration: Double
    let wallDuration: Double
    let linesAdded: Int
    let linesRemoved: Int
    let providerId: String
    let capturedAt: Date
    let resetsAt: Date?
    let resetText: String?

    enum PersistedCostKind: Codable {
        case apiCost
        case extraUsage
    }

    static func from(_ usage: CostUsage) -> PersistedCostUsage {
        PersistedCostUsage(
            kind: usage.kind == .apiCost ? .apiCost : .extraUsage,
            totalCost: NSDecimalNumber(decimal: usage.totalCost).doubleValue,
            budget: usage.budget.flatMap { NSDecimalNumber(decimal: $0).doubleValue },
            apiDuration: usage.apiDuration,
            wallDuration: usage.wallDuration,
            linesAdded: usage.linesAdded,
            linesRemoved: usage.linesRemoved,
            providerId: usage.providerId,
            capturedAt: usage.capturedAt,
            resetsAt: usage.resetsAt,
            resetText: usage.resetText
        )
    }

    var asDomain: CostUsage {
        CostUsage(
            totalCost: Decimal(totalCost),
            budget: budget.map { Decimal($0) },
            apiDuration: apiDuration,
            wallDuration: wallDuration,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            providerId: providerId,
            kind: kind == .apiCost ? .apiCost : .extraUsage,
            capturedAt: capturedAt,
            resetsAt: resetsAt,
            resetText: resetText
        )
    }
}

// MARK: - BedrockUsageSummary

struct PersistedBedrockUsageSummary: Codable {
    let modelUsages: [PersistedBedrockModelUsage]
    let region: String
    let capturedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let dailyBudget: Double?

    static func from(_ summary: BedrockUsageSummary) -> PersistedBedrockUsageSummary {
        PersistedBedrockUsageSummary(
            modelUsages: summary.modelUsages.map(PersistedBedrockModelUsage.from),
            region: summary.region,
            capturedAt: summary.capturedAt,
            periodStart: summary.periodStart,
            periodEnd: summary.periodEnd,
            dailyBudget: summary.dailyBudget.flatMap { NSDecimalNumber(decimal: $0).doubleValue }
        )
    }

    var asDomain: BedrockUsageSummary {
        BedrockUsageSummary(
            modelUsages: modelUsages.map(\.asDomain),
            region: region,
            capturedAt: capturedAt,
            periodStart: periodStart,
            periodEnd: periodEnd,
            dailyBudget: dailyBudget.map { Decimal($0) }
        )
    }
}

struct PersistedBedrockModelUsage: Codable {
    let modelId: String
    let modelDisplayName: String
    let modelVendor: String
    let inputPricePer1M: Double
    let outputPricePer1M: Double
    let invocations: Int
    let inputTokens: Int
    let outputTokens: Int

    static func from(_ usage: BedrockModelUsage) -> PersistedBedrockModelUsage {
        PersistedBedrockModelUsage(
            modelId: usage.model.id,
            modelDisplayName: usage.model.displayName,
            modelVendor: usage.model.vendor,
            inputPricePer1M: NSDecimalNumber(decimal: usage.model.inputPricePer1M).doubleValue,
            outputPricePer1M: NSDecimalNumber(decimal: usage.model.outputPricePer1M).doubleValue,
            invocations: usage.invocations,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )
    }

    var asDomain: BedrockModelUsage {
        BedrockModelUsage(
            model: BedrockModel(
                id: modelId,
                displayName: modelDisplayName,
                vendor: modelVendor,
                inputPricePer1M: Decimal(inputPricePer1M),
                outputPricePer1M: Decimal(outputPricePer1M)
            ),
            invocations: invocations,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}

// MARK: - DailyUsageReport

struct PersistedDailyUsageReport: Codable {
    let today: PersistedDailyUsageStat
    let previous: PersistedDailyUsageStat

    static func from(_ report: DailyUsageReport) -> PersistedDailyUsageReport {
        PersistedDailyUsageReport(
            today: PersistedDailyUsageStat.from(report.today),
            previous: PersistedDailyUsageStat.from(report.previous)
        )
    }

    var asDomain: DailyUsageReport {
        DailyUsageReport(today: today.asDomain, previous: previous.asDomain)
    }
}

struct PersistedDailyUsageStat: Codable {
    let date: Date
    let totalCost: Double
    let totalTokens: Int
    let workingTime: Double
    let sessionCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cachedSavings: Double

    static func from(_ stat: DailyUsageStat) -> PersistedDailyUsageStat {
        PersistedDailyUsageStat(
            date: stat.date,
            totalCost: NSDecimalNumber(decimal: stat.totalCost).doubleValue,
            totalTokens: stat.totalTokens,
            workingTime: stat.workingTime,
            sessionCount: stat.sessionCount,
            inputTokens: stat.inputTokens,
            outputTokens: stat.outputTokens,
            cacheCreationTokens: stat.cacheCreationTokens,
            cacheReadTokens: stat.cacheReadTokens,
            cachedSavings: NSDecimalNumber(decimal: stat.cachedSavings).doubleValue
        )
    }

    var asDomain: DailyUsageStat {
        DailyUsageStat(
            date: date,
            totalCost: Decimal(totalCost),
            totalTokens: totalTokens,
            workingTime: workingTime,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            cachedSavings: Decimal(cachedSavings)
        )
    }
}

// MARK: - ExtensionMetric

struct PersistedExtensionMetric: Codable {
    let label: String
    let value: String
    let unit: String
    let icon: String?
    let color: String?
    let delta: PersistedMetricDelta?
    let progress: Double?
    let group: String?

    static func from(_ metric: ExtensionMetric) -> PersistedExtensionMetric {
        PersistedExtensionMetric(
            label: metric.label,
            value: metric.value,
            unit: metric.unit,
            icon: metric.icon,
            color: metric.color,
            delta: metric.delta.map(PersistedMetricDelta.from),
            progress: metric.progress,
            group: metric.group
        )
    }

    var asDomain: ExtensionMetric {
        ExtensionMetric(
            label: label,
            value: value,
            unit: unit,
            icon: icon,
            color: color,
            delta: delta?.asDomain,
            progress: progress,
            group: group
        )
    }
}

struct PersistedMetricDelta: Codable {
    let vs: String
    let value: String
    let percent: Double?

    static func from(_ delta: MetricDelta) -> PersistedMetricDelta {
        PersistedMetricDelta(
            vs: delta.vs,
            value: delta.value,
            percent: delta.percent
        )
    }

    var asDomain: MetricDelta {
        MetricDelta(vs: vs, value: value, percent: percent)
    }
}

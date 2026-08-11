import Foundation
import Domain

/// Probes Kimi coding-plan usage.
///
/// Two auth/API paths:
/// 1. **Coding API key** (`sk-kimi-...`) → `GET https://api.kimi.com/coding/v1/usages`
///    (verified with Kimi Desktop local key; returns 5h + weekly + optional monthly)
/// 2. **Web session / cookie** → legacy billing GetUsages RPC
public struct KimiUsageProbe: UsageProbe {

    private let networkClient: any NetworkClient
    private let tokenProvider: any KimiTokenProviding
    private let timeout: TimeInterval

    /// Rate limits (5h + weekly) for coding key
    private static let codingUsageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!
    /// Monthly totalQuota lives on agent-gw (Desktop Kimi Work / FEATURE_WORK)
    private static let agentUsageURL = URL(string: "https://agent-gw.kimi.com/coding/v1/usages")!
    private static let billingUsageURL = URL(
        string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"
    )!

    /// Known tier mappings based on weekly limit (legacy billing path)
    private static let tierByLimit: [Int: String] = [
        1024: "Andante",
        2048: "Moderato",
        7168: "Allegretto",
    ]

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        tokenProvider: any KimiTokenProviding = KimiCookieTokenProvider(),
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.tokenProvider = tokenProvider
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        do {
            _ = try tokenProvider.resolveToken()
            return true
        } catch {
            return false
        }
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Kimi probe...")

        let token: String
        do {
            token = try tokenProvider.resolveToken()
        } catch {
            throw ProbeError.authenticationRequired
        }

        // Prefer the richer coding API when we have a coding key; otherwise
        // fall back to the cookie/JWT billing RPC path.
        if token.hasPrefix("sk-kimi") {
            return try await probeCodingAPI(apiKey: token)
        }
        return try await probeBillingAPI(token: token)
    }

    // MARK: - Coding API (sk-kimi)

    private func probeCodingAPI(apiKey: String) async throws -> UsageSnapshot {
        // 1) api.kimi.com → 5H + weekly (totalQuota often empty here)
        let primaryData = try await getCodingJSON(url: Self.codingUsageURL, apiKey: apiKey)
        if let raw = String(data: primaryData, encoding: .utf8) {
            AppLog.probes.debug("Kimi coding raw response: \(raw.prefix(2000))")
        }
        var snapshot = try Self.parseCodingResponse(primaryData, providerId: "kimi")

        // 2) agent-gw → real monthly totalQuota (Desktop Kimi Work)
        if snapshot.quotas.contains(where: {
            if case .timeLimit(let n) = $0.quotaType {
                return n.localizedCaseInsensitiveContains("month")
            }
            return false
        }) == false {
            do {
                let agentData = try await getCodingJSON(url: Self.agentUsageURL, apiKey: apiKey)
                if let raw = String(data: agentData, encoding: .utf8) {
                    AppLog.probes.debug("Kimi agent-gw raw response: \(raw.prefix(1200))")
                }
                if let monthly = try Self.parseMonthlyOnly(from: agentData, providerId: "kimi") {
                    var quotas = snapshot.quotas
                    quotas.append(monthly)
                    snapshot = UsageSnapshot(
                        providerId: snapshot.providerId,
                        quotas: quotas,
                        capturedAt: snapshot.capturedAt,
                        accountEmail: snapshot.accountEmail,
                        accountOrganization: snapshot.accountOrganization,
                        loginMethod: snapshot.loginMethod,
                        accountTier: snapshot.accountTier,
                        costUsage: snapshot.costUsage,
                        bedrockUsage: snapshot.bedrockUsage,
                        dailyUsageReport: snapshot.dailyUsageReport,
                        extensionMetrics: snapshot.extensionMetrics
                    )
                }
            } catch {
                AppLog.probes.warning("Kimi agent-gw monthly fetch failed: \(error.localizedDescription)")
            }
        }

        AppLog.probes.info("Kimi coding probe success: \(snapshot.quotas.count) quotas")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
        return snapshot
    }

    private func getCodingJSON(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Desktop Kimi Work", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            throw ProbeError.executionFailed("Kimi request failed (\(url.host ?? "?")): \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ProbeError.executionFailed("Kimi HTTP \(httpResponse.statusCode) @ \(url.host ?? ""): \(body)")
        }
    }

    /// Parses agent-gw payload that mainly carries `totalQuota` (monthly).
    static func parseMonthlyOnly(from data: Data, providerId: String) throws -> UsageQuota? {
        let decoded: KimiCodingUsageResponse
        do {
            decoded = try JSONDecoder().decode(KimiCodingUsageResponse.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Failed to decode Kimi agent-gw response: \(error.localizedDescription)")
        }
        guard let total = decoded.totalQuota,
              let limitStr = total.limit,
              let limit = Int(limitStr),
              limit > 0 else {
            return nil
        }
        let nums = parseStringNumbers(limit: limitStr, used: total.used, remaining: total.remaining)
        let remainingPct = Double(nums.remaining) / Double(nums.limit) * 100.0
        return UsageQuota(
            percentRemaining: remainingPct,
            quotaType: .timeLimit("Monthly"),
            providerId: providerId,
            resetsAt: parseISO8601(total.resetTime),
            resetText: "used \(nums.used)/\(nums.limit) 总额",
            compactTitle: "总额"
        )
    }

    /// Parses:
    /// ```
    /// {
    ///   "user":{"membership":{"level":"LEVEL_INTERMEDIATE"}},
    ///   "usage":{"limit":"100","remaining":"100","resetTime":"..."},
    ///   "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{...}}],
    ///   "totalQuota":{"limit":"100","used":"11","remaining":"89","resetTime":"..."} // optional
    /// }
    /// ```
    static func parseCodingResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoded: KimiCodingUsageResponse
        do {
            decoded = try JSONDecoder().decode(KimiCodingUsageResponse.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Failed to decode Kimi coding response: \(error.localizedDescription)")
        }

        var quotas: [UsageQuota] = []

        // Weekly (usage)
        if let usage = decoded.usage {
            let nums = parseStringNumbers(limit: usage.limit, used: usage.used, remaining: usage.remaining)
            let remainingPct = nums.limit > 0 ? Double(nums.remaining) / Double(nums.limit) * 100.0 : 100.0
            quotas.append(UsageQuota(
                percentRemaining: remainingPct,
                quotaType: .weekly,
                providerId: providerId,
                resetsAt: parseISO8601(usage.resetTime),
                resetText: "used \(nums.used)/\(nums.limit) weekly"
            ))
        }

        // 5h window from limits
        if let rateLimit = decoded.limits?.first(where: {
            $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE"
        }) ?? decoded.limits?.first {
            let nums = parseStringNumbers(
                limit: rateLimit.detail.limit,
                used: rateLimit.detail.used,
                remaining: rateLimit.detail.remaining
            )
            let remainingPct = nums.limit > 0 ? Double(nums.remaining) / Double(nums.limit) * 100.0 : 100.0
            quotas.append(UsageQuota(
                percentRemaining: remainingPct,
                quotaType: .session,
                providerId: providerId,
                resetsAt: parseISO8601(rateLimit.detail.resetTime),
                resetText: "used \(nums.used)/\(nums.limit) (5h)",
                windowDuration: windowSeconds(duration: rateLimit.window.duration, unit: rateLimit.window.timeUnit)
            ))
        }

        // Optional monthly / total pool
        if let total = decoded.totalQuota,
           let limitStr = total.limit,
           let limit = Int(limitStr),
           limit > 0 {
            let nums = parseStringNumbers(limit: limitStr, used: total.used, remaining: total.remaining)
            let remainingPct = Double(nums.remaining) / Double(nums.limit) * 100.0
            quotas.append(UsageQuota(
                percentRemaining: remainingPct,
                quotaType: .timeLimit("Monthly"),
                providerId: providerId,
                resetsAt: parseISO8601(total.resetTime),
                resetText: "used \(nums.used)/\(nums.limit) total"
            ))
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("Kimi coding response contained no quotas")
        }

        let tierName = decoded.user?.membership?.level?
            .replacingOccurrences(of: "LEVEL_", with: "")
            .capitalized
        let tier = tierName.map { AccountTier.custom($0) }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountTier: tier
        )
    }

    // MARK: - Billing API (web session)

    private func probeBillingAPI(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.billingUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]])
        Self.applyBillingHeaders(&request, token: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Kimi billing probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Kimi billing API request failed: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ProbeError.executionFailed("Kimi billing API HTTP \(httpResponse.statusCode): \(body)")
        }

        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Kimi billing raw response: \(rawString.prefix(2000))")
        }

        let snapshot = try Self.parseBillingResponse(data, providerId: "kimi")
        AppLog.probes.info("Kimi billing probe success: \(snapshot.quotas.count) quotas")
        return snapshot
    }

    /// Legacy billing GetUsages parser (cookie/JWT path)
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        try parseBillingResponse(data, providerId: providerId)
    }

    static func parseBillingResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoded: KimiUsageResponse
        do {
            decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Failed to decode Kimi response: \(error.localizedDescription)")
        }

        guard let coding = decoded.usages.first(where: { $0.scope == "FEATURE_CODING" }) else {
            throw ProbeError.parseFailed("Missing FEATURE_CODING scope in response")
        }

        let weekly = parseUsageNumbers(detail: coding.detail)
        var quotas: [UsageQuota] = []

        let weeklyPercentRemaining: Double
        if weekly.limit > 0 {
            weeklyPercentRemaining = (Double(weekly.remaining) / Double(weekly.limit)) * 100.0
        } else {
            weeklyPercentRemaining = 100.0
        }

        quotas.append(UsageQuota(
            percentRemaining: weeklyPercentRemaining,
            quotaType: .weekly,
            providerId: providerId,
            resetsAt: parseISO8601(coding.detail.resetTime),
            resetText: "used \(weekly.used)/\(weekly.limit) requests"
        ))

        let fiveHourRate = coding.limits?.first(where: {
            $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE"
        }) ?? coding.limits?.first

        if let rateLimit = fiveHourRate {
            let rate = parseUsageNumbers(detail: rateLimit.detail)
            let ratePercentRemaining: Double
            if rate.limit > 0 {
                ratePercentRemaining = (Double(rate.remaining) / Double(rate.limit)) * 100.0
            } else {
                ratePercentRemaining = 100.0
            }

            quotas.append(UsageQuota(
                percentRemaining: ratePercentRemaining,
                quotaType: .session,
                providerId: providerId,
                resetsAt: parseISO8601(rateLimit.detail.resetTime),
                resetText: "used \(rate.used)/\(rate.limit) requests (5h)",
                windowDuration: windowSeconds(duration: rateLimit.window.duration, unit: rateLimit.window.timeUnit)
            ))
        }

        let tier = tierByLimit[weekly.limit].map { AccountTier.custom($0) }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountTier: tier
        )
    }

    // MARK: - Helpers

    private static func applyBillingHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("en-US", forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) {
            return value
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func parseUsageNumbers(detail: KimiUsageResponse.Usage.Detail) -> (used: Int, limit: Int, remaining: Int) {
        parseStringNumbers(limit: detail.limit, used: detail.used, remaining: detail.remaining)
    }

    private static func parseStringNumbers(limit: String, used: String?, remaining: String?) -> (used: Int, limit: Int, remaining: Int) {
        let limitValue = Int(limit) ?? 0
        let rawUsed = Int(used ?? "")
        let rawRemaining = Int(remaining ?? "")

        let usedValue: Int
        let remainingValue: Int

        if let rawUsed, let rawRemaining {
            usedValue = rawUsed
            remainingValue = rawRemaining
        } else if let rawUsed {
            usedValue = rawUsed
            remainingValue = max(0, limitValue - rawUsed)
        } else if let rawRemaining {
            usedValue = max(0, limitValue - rawRemaining)
            remainingValue = rawRemaining
        } else {
            usedValue = 0
            remainingValue = max(0, limitValue)
        }

        return (used: usedValue, limit: limitValue, remaining: remainingValue)
    }

    private static func windowSeconds(duration: Int, unit: String) -> TimeInterval? {
        switch unit {
        case "TIME_UNIT_MINUTE":
            return TimeInterval(duration * 60)
        case "TIME_UNIT_HOUR":
            return TimeInterval(duration * 3600)
        case "TIME_UNIT_SECOND":
            return TimeInterval(duration)
        default:
            return nil
        }
    }
}

// MARK: - Coding API Response

struct KimiCodingUsageResponse: Decodable {
    struct User: Decodable {
        struct Membership: Decodable {
            let level: String?
        }
        let membership: Membership?
    }

    struct Detail: Decodable {
        let limit: String
        let used: String?
        let remaining: String?
        let resetTime: String?
    }

    struct RateLimit: Decodable {
        struct Window: Decodable {
            let duration: Int
            let timeUnit: String
        }
        let window: Window
        let detail: Detail
    }

    struct TotalQuota: Decodable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String?
    }

    let user: User?
    let usage: Detail?
    let limits: [RateLimit]?
    let totalQuota: TotalQuota?
}

// MARK: - Billing API Response

struct KimiUsageResponse: Decodable {
    struct Usage: Decodable {
        struct Detail: Decodable {
            let limit: String
            let used: String?
            let remaining: String?
            let resetTime: String
        }

        struct RateLimit: Decodable {
            struct Window: Decodable {
                let duration: Int
                let timeUnit: String
            }

            let window: Window
            let detail: Detail
        }

        let scope: String
        let detail: Detail
        let limits: [RateLimit]?
    }

    let usages: [Usage]
}

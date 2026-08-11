import Foundation
import Domain

/// Codex API-based usage probe that fetches quota data directly from the ChatGPT backend API.
///
/// This probe uses the user's OAuth credentials (from `~/.codex/auth.json`)
/// to call the usage API endpoint. It automatically refreshes expired tokens.
///
/// Usage URL: `https://chatgpt.com/backend-api/wham/usage`
/// Token Refresh URL: `https://auth.openai.com/oauth/token`
public struct CodexAPIUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: CodexCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    // API endpoints
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!

    // OAuth configuration (from Codex JS reference)
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public init(
        credentialLoader: CodexCredentialLoader = CodexCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        credentialLoader.loadCredentials() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard var credentials = credentialLoader.loadCredentials() else {
            AppLog.probes.error("Codex API: No credentials found")
            throw ProbeError.authenticationRequired
        }

        // Check if token needs refresh (based on last_refresh age)
        if credentialLoader.needsRefresh(lastRefresh: credentials.lastRefresh) {
            AppLog.probes.info("Codex API: Token needs refresh (last_refresh > 8 days)")
            do {
                credentials = try await refreshToken(credentials)
            } catch {
                AppLog.probes.warning("Codex API: Proactive refresh failed: \(error.localizedDescription), trying with existing token")
                // Don't throw here - try the existing token first
                if case ProbeError.sessionExpired = error {
                    throw error
                }
            }
        }

        // Fetch usage data
        let (data, httpResponse): (Data, HTTPURLResponse)
        do {
            (data, httpResponse) = try await fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId
            )
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token might have been invalidated, try refreshing once
            AppLog.probes.info("Codex API: Got 401, attempting token refresh...")
            do {
                credentials = try await refreshToken(credentials)
                (data, httpResponse) = try await fetchUsage(
                    accessToken: credentials.accessToken,
                    accountId: credentials.accountId
                )
            } catch {
                AppLog.probes.error("Codex API: Retry after refresh failed: \(error.localizedDescription)")
                throw error
            }
        }

        return try parseUsageResponse(data: data, httpResponse: httpResponse, credentials: credentials)
    }

    // MARK: - Token Refresh

    private func refreshToken(_ credentials: CodexCredentialResult) async throws -> CodexCredentialResult {
        guard let refreshToken = credentials.refreshToken else {
            AppLog.probes.error("Codex API: No refresh token available")
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        // Form-urlencoded body (matching Codex JS reference)
        let bodyString = "grant_type=refresh_token"
            + "&client_id=" + Self.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            + "&refresh_token=" + refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        request.httpBody = bodyString.data(using: .utf8)

        AppLog.probes.debug("Codex API: Refreshing token...")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        // Handle error responses
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            if let rawBody = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Codex API: Token refresh error response: \(rawBody)")
            }

            // Check for specific error codes
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let code = extractErrorCode(from: errorData)

                if code == "refresh_token_expired" || code == "refresh_token_reused" || code == "refresh_token_invalidated" {
                    AppLog.probes.error("Codex API: Session expired (\(code ?? "unknown")) - run `codex` to re-authenticate")
                    throw ProbeError.sessionExpired(hint: "Run `codex` in terminal to log in again.")
                }
            }

            AppLog.probes.error("Codex API: Token expired or invalid (HTTP \(httpResponse.statusCode))")
            throw ProbeError.sessionExpired(hint: "Run `codex` in terminal to log in again.")
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            AppLog.probes.error("Codex API: Token refresh failed with HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        // Parse refresh response
        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = responseDict["access_token"] as? String,
              !newAccessToken.isEmpty else {
            AppLog.probes.error("Codex API: No access token in refresh response")
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        // Update credentials
        var updatedCredentials = credentials
        updatedCredentials.accessToken = newAccessToken
        if let newRefreshToken = responseDict["refresh_token"] as? String {
            updatedCredentials.refreshToken = newRefreshToken
        }
        if let idToken = responseDict["id_token"] as? String {
            updatedCredentials.idToken = idToken
            var fullData = updatedCredentials.fullData
            if var tokens = fullData["tokens"] as? [String: Any] {
                tokens["id_token"] = idToken
                fullData["tokens"] = tokens
                updatedCredentials.fullData = fullData
            }
        }
        updatedCredentials.lastRefresh = ISO8601DateFormatter().string(from: Date())

        // Save updated credentials
        credentialLoader.saveCredentials(updatedCredentials)

        AppLog.probes.info("Codex API: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Usage Fetch

    private func fetchUsage(accessToken: String, accountId: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = timeout

        AppLog.probes.debug("Codex API: Fetching usage...")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Codex API: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Codex API: Response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Codex API: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        return (data, httpResponse)
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(data: Data, httpResponse: HTTPURLResponse, credentials: CodexCredentialResult) throws -> UsageSnapshot {
        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Codex API: Raw response: \(rawString.prefix(500))")
        }

        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Failed to parse usage response as JSON")
        }

        var quotas: [UsageQuota] = []
        let nowSeconds = Date().timeIntervalSince1970

        let rateLimit = responseDict["rate_limit"] as? [String: Any]
        let primaryWindow = rateLimit?["primary_window"] as? [String: Any]
        let secondaryWindow = rateLimit?["secondary_window"] as? [String: Any]

        // Prefer headers; fall back to body. Classify 5h/7d/月 by window duration
        // (Pro 20X often only returns a 7-day primary window — must NOT label as 5H).
        let headerPrimary = readHeaderDouble(httpResponse, key: "x-codex-primary-used-percent")
        let headerSecondary = readHeaderDouble(httpResponse, key: "x-codex-secondary-used-percent")

        if let used = headerPrimary ?? (primaryWindow?["used_percent"] as? Double) {
            let type = quotaType(forWindowSeconds: windowSeconds(primaryWindow), fallback: .session)
            let resets = resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow)
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - used),
                quotaType: type,
                providerId: "codex",
                resetsAt: resets,
                resetText: formatResetText(resets),
                windowDuration: windowSeconds(primaryWindow)
            ))
        }
        if let used = headerSecondary ?? (secondaryWindow?["used_percent"] as? Double) {
            // Headers-only secondary has no duration → default weekly (not session)
            let type = quotaType(forWindowSeconds: windowSeconds(secondaryWindow), fallback: .weekly)
            // Avoid duplicate keys if both windows collapse to the same type
            if !quotas.contains(where: { $0.quotaType == type }) {
                let resets = resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow)
                quotas.append(UsageQuota(
                    percentRemaining: max(0, 100 - used),
                    quotaType: type,
                    providerId: "codex",
                    resetsAt: resets,
                    resetText: formatResetText(resets),
                    windowDuration: windowSeconds(secondaryWindow)
                ))
            }
        }

        // GPT-5.3-Codex-Spark has its own bucket under additional_rate_limits
        // (not the plan credits balance). Prefer the weekly window as a card row.
        for extra in parseAdditionalRateLimits(
            responseDict["additional_rate_limits"],
            nowSeconds: nowSeconds
        ) {
            // Avoid duplicate quota keys
            if !quotas.contains(where: { $0.quotaType == extra.quotaType }) {
                quotas.append(extra)
            }
        }

        // Credits (加油包 / 额外积分) — second-row card meter next to Spark weekly.
        var costUsage: CostUsage?
        let creditsHeader = readHeaderDouble(httpResponse, key: "x-codex-credits-balance")
        let creditsBody: Double? = {
            guard let credits = responseDict["credits"] as? [String: Any] else { return nil }
            if let n = credits["balance"] as? Double { return n }
            if let s = credits["balance"] as? String { return Double(s) }
            return nil
        }()
        if let creditsRemaining = creditsHeader ?? creditsBody, creditsRemaining.isFinite {
            let balance = Decimal(creditsRemaining)
            costUsage = CostUsage(
                totalCost: 0,
                budget: balance,
                apiDuration: 0,
                providerId: "codex",
                capturedAt: Date(),
                resetsAt: nil,
                resetText: "积分 \(Self.formatCredits(creditsRemaining))"
            )
            // Uncapped top-up balance: keep percentRemaining at 100 (AmpCode-style).
            // Zero credits is idle, not "rate limits exhausted" — overall status
            // also excludes uncapped dollar balances via affectsOverallStatus.
            quotas.append(UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Credits"),
                providerId: "codex",
                resetsAt: nil,
                resetText: nil,
                dollarRemaining: balance,
                compactTitle: "积分"
            ))
        }

        // Parse plan type
        var accountTier: AccountTier?
        if let planType = responseDict["plan_type"] as? String, !planType.isEmpty {
            accountTier = parsePlanType(planType)
        }

        AppLog.probes.info("Codex API: Parsed \(quotas.count) quotas, tier=\(accountTier?.badgeText ?? "unknown")")

        let identity = credentialLoader.resolveAccountIdentity(credentials)

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: accountTier,
            costUsage: costUsage,
            accountExternalId: identity?.externalId,
            accountIdentitySource: identity?.source
        )
    }

    /// Parse `additional_rate_limits[]` — e.g. GPT-5.3-Codex-Spark weekly bucket.
    private func parseAdditionalRateLimits(_ raw: Any?, nowSeconds: TimeInterval) -> [UsageQuota] {
        guard let items = raw as? [[String: Any]] else { return [] }
        var out: [UsageQuota] = []

        for item in items {
            let name = (item["limit_name"] as? String) ?? ""
            let feature = (item["metered_feature"] as? String) ?? ""
            let blob = "\(name) \(feature)".lowercased()
            let isSpark = blob.contains("spark") || blob.contains("bengalfox")
            guard isSpark else { continue }

            let rateLimit = (item["rate_limit"] as? [String: Any]) ?? item
            let primary = rateLimit["primary_window"] as? [String: Any]
            let secondary = rateLimit["secondary_window"] as? [String: Any]

            // Prefer weekly window for the Spark row (user: “使用限额每周”)
            let weeklyWindow: [String: Any]? = {
                if let secondary, isWeeklyWindow(secondary) { return secondary }
                if let primary, isWeeklyWindow(primary) { return primary }
                // Fallback: secondary if present, else nil (don't invent 5h as weekly)
                if let secondary { return secondary }
                return nil
            }()

            guard let win = weeklyWindow else { continue }
            guard let used = usedPercent(win) else { continue }

            let remaining = max(0, min(100, 100 - used))
            let resets = resetsAtDate(nowSeconds: nowSeconds, window: win)
            let duration = windowSeconds(win)
            out.append(UsageQuota(
                percentRemaining: remaining,
                quotaType: .modelSpecific("GPT-5.3-Codex-Spark"),
                providerId: "codex",
                resetsAt: resets,
                resetText: formatResetText(resets),
                windowDuration: duration,
                compactTitle: "GPT-5.3 周额度"
            ))
        }
        return out
    }

    private func isWeeklyWindow(_ window: [String: Any]) -> Bool {
        guard let seconds = windowSeconds(window) else {
            // Unknown length but named secondary → treat as weekly candidate
            return true
        }
        // 1 day … 10 days
        return seconds > 6 * 3600 && seconds <= 10 * 24 * 3600
    }

    private func usedPercent(_ window: [String: Any]) -> Double? {
        if let u = window["used_percent"] as? Double, u.isFinite { return u }
        if let u = window["used_percent"] as? Int { return Double(u) }
        if let u = window["used_percent"] as? String, let d = Double(u), d.isFinite { return d }
        return nil
    }

    // MARK: - Helpers

    private func readHeaderDouble(_ response: HTTPURLResponse, key: String) -> Double? {
        guard let value = response.value(forHTTPHeaderField: key) else { return nil }
        let n = Double(value)
        return n?.isFinite == true ? n : nil
    }

    /// Formats credit balances like 5.3 / 139.9 without a $ sign.
    private static func formatCredits(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func windowSeconds(_ window: [String: Any]?) -> TimeInterval? {
        guard let window else { return nil }
        if let s = window["limit_window_seconds"] as? Double { return s }
        if let s = window["limit_window_seconds"] as? Int { return TimeInterval(s) }
        return nil
    }

    /// Map Codex rate-limit window length → 5H / 7d / 月.
    private func quotaType(forWindowSeconds seconds: TimeInterval?, fallback: QuotaType = .session) -> QuotaType {
        guard let seconds, seconds > 0 else {
            return fallback
        }
        // ≤ 6h → 5H session
        if seconds <= 6 * 3600 { return .session }
        // ≤ 10 days → weekly / 7d (Pro often uses 604800 = 7d)
        if seconds <= 10 * 24 * 3600 { return .weekly }
        // Longer → monthly
        return .timeLimit("Monthly")
    }

    private func resetsAtDate(nowSeconds: TimeInterval, window: [String: Any]?) -> Date? {
        guard let window else { return nil }
        if let resetAt = window["reset_at"] as? Double {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAt = window["reset_at"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(resetAt))
        }
        if let resetAfterSeconds = window["reset_after_seconds"] as? Double {
            return Date(timeIntervalSince1970: nowSeconds + resetAfterSeconds)
        }
        if let resetAfterSeconds = window["reset_after_seconds"] as? Int {
            return Date(timeIntervalSince1970: nowSeconds + TimeInterval(resetAfterSeconds))
        }
        return nil
    }

    private func formatResetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return nil }

        let days = Int(seconds / 86400)
        let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            return "Resets in \(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }

    private func parsePlanType(_ planType: String) -> AccountTier {
        switch planType.lowercased() {
        case "plus":
            return .custom("PLUS")
        case "pro":
            return .custom("PRO")
        case "free":
            return .custom("FREE")
        default:
            return .custom(planType.uppercased())
        }
    }

    private func extractErrorCode(from errorData: [String: Any]) -> String? {
        // Try nested: { "error": { "code": "..." } }
        if let errorObj = errorData["error"] as? [String: Any],
           let code = errorObj["code"] as? String {
            return code
        }
        // Try flat: { "error": "..." }
        if let errorStr = errorData["error"] as? String {
            return errorStr
        }
        // Try top-level: { "code": "..." }
        if let code = errorData["code"] as? String {
            return code
        }
        return nil
    }
}

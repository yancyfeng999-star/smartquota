import Foundation
import Domain

/// Infrastructure adapter that probes Cursor's usage API to fetch quota data.
///
/// Cursor stores its authentication in a local SQLite database. This probe:
/// 1. Reads the access token from `state.vscdb`
/// 2. Decodes the JWT to extract the user ID
/// 3. Calls `https://cursor.com/api/usage-summary` with cookie auth
/// 4. Parses the response into quota percentages
///
/// The auth cookie format is: `WorkosCursorSessionToken={userId}::{accessToken}`
///
/// Official individual usage is two monthly pools (Cursor settings / dashboard):
/// - **Cursor Models** (`autoPercentUsed`): Grok / Composer
/// - **Other Models** (`apiPercentUsed`): third-party API usage
///
/// ```json
/// {
///   "membershipType": "ultra",
///   "individualUsage": {
///     "plan": {
///       "autoPercentUsed": 1,
///       "apiPercentUsed": 5,
///       "totalPercentUsed": 1.8
///     }
///   }
/// }
/// ```
public struct CursorUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private let dbPathOverride: String?

    private static let usageSummaryURL = "https://cursor.com/api/usage-summary"

    static let cursorModelsQuotaName = "Cursor Models"
    static let otherModelsQuotaName = "Other Models"

    /// The default path to Cursor's SQLite database on macOS
    static let defaultDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15.0,
        dbPathOverride: String? = nil
    ) {
        self.networkClient = networkClient
        self.timeout = timeout
        self.dbPathOverride = dbPathOverride
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath
        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        if !dbExists {
            AppLog.probes.debug("Cursor: Database not found at \(dbPath)")
        }
        return dbExists
    }

    public func probe() async throws -> UsageSnapshot {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath

        guard FileManager.default.fileExists(atPath: dbPath) else {
            AppLog.probes.error("Cursor: Database not found at \(dbPath)")
            throw ProbeError.cliNotFound("Cursor (database not found)")
        }

        AppLog.probes.info("Cursor: Reading auth token from database...")

        let accessToken = try readAccessToken(from: dbPath)
        let userId = try Self.extractUserIdFromJWT(accessToken)
        let cookie = "WorkosCursorSessionToken=\(userId)::\(accessToken)"

        AppLog.probes.info("Cursor: Fetching usage summary...")

        let response = try await fetchUsageSummary(cookie: cookie)
        let snapshot = try Self.parseUsageSummary(response)

        AppLog.probes.info("Cursor: Probe success - \(snapshot.quotas.count) quotas found")
        return snapshot
    }

    // MARK: - Token Extraction

    /// Reads the access token from Cursor's SQLite database using the sqlite3 CLI.
    private func readAccessToken(from dbPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.probes.error("Cursor: Failed to run sqlite3 - \(error.localizedDescription)")
            throw ProbeError.executionFailed("Failed to read Cursor database: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            AppLog.probes.error("Cursor: sqlite3 exited with status \(process.terminationStatus)")
            throw ProbeError.executionFailed("sqlite3 exited with status \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !token.isEmpty else {
            AppLog.probes.error("Cursor: No access token found in database (not logged in?)")
            throw ProbeError.authenticationRequired
        }

        return token
    }

    /// Extracts the user ID (`sub` claim) from a JWT token by base64-decoding the payload.
    static func extractUserIdFromJWT(_ token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw ProbeError.parseFailed("Invalid JWT format")
        }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw ProbeError.parseFailed("Failed to decode JWT payload")
        }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let sub = json["sub"] as? String, !sub.isEmpty else {
            throw ProbeError.parseFailed("JWT payload missing 'sub' claim")
        }

        return sub
    }

    // MARK: - API Call

    private func fetchUsageSummary(cookie: String) async throws -> Data {
        guard let url = URL(string: Self.usageSummaryURL) else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Cursor: API response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            AppLog.probes.error("Cursor: Authentication failed (401) - token may be expired")
            throw ProbeError.sessionExpired(hint: "Re-authenticate in Cursor settings.")
        case 403:
            AppLog.probes.error("Cursor: Forbidden (403)")
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Cursor: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Response Parsing (static for testability)

    /// Current dashboard: `autoPercentUsed` = Cursor Models, `apiPercentUsed` = Other Models.
    /// Older payloads without those fields still fall back to a single Monthly request meter.
    public static func parseUsageSummary(_ data: Data) throws -> UsageSnapshot {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProbeError.parseFailed("Response is not a JSON object")
            }
            json = parsed
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        var quotas: [UsageQuota] = []

        let membershipType = json["membershipType"] as? String ?? "unknown"
        let limitType = json["limitType"] as? String ?? ""

        let cycleStart = Self.parseISO8601(json["billingCycleStart"] as? String)
        let cycleEnd = Self.parseISO8601(json["billingCycleEnd"] as? String)
        let windowDuration: TimeInterval? = {
            guard let cycleStart, let cycleEnd else { return nil }
            let span = cycleEnd.timeIntervalSince(cycleStart)
            return span > 0 ? span : nil
        }()

        let individualUsage = json["individualUsage"] as? [String: Any]
        let planUsage = individualUsage?["plan"] as? [String: Any]
        let parsedTwoPools = Self.appendTwoPoolQuotas(
            from: planUsage,
            autoOverride: Self.percentFromDisplayMessage(json["autoModelSelectedDisplayMessage"] as? String),
            apiOverride: Self.percentFromDisplayMessage(json["namedModelSelectedDisplayMessage"] as? String),
            resetsAt: cycleEnd,
            windowDuration: windowDuration,
            into: &quotas
        )

        if !parsedTwoPools {
            Self.appendLegacyMonthlyQuota(
                from: planUsage,
                resetsAt: cycleEnd,
                windowDuration: windowDuration,
                into: &quotas
            )
        }

        if quotas.isEmpty {
            Self.appendPoolsFromDisplayMessages(
                autoMessage: json["autoModelSelectedDisplayMessage"] as? String,
                namedMessage: json["namedModelSelectedDisplayMessage"] as? String,
                resetsAt: cycleEnd,
                windowDuration: windowDuration,
                into: &quotas
            )
        }

        if let onDemand = individualUsage?["onDemand"] as? [String: Any],
           let enabled = onDemand["enabled"] as? Bool, enabled {
            let used = Self.intValue(from: onDemand, key: "used") ?? 0
            let limit = Self.intValue(from: onDemand, key: "limit") ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("On-Demand"),
                    providerId: "cursor",
                    resetsAt: cycleEnd,
                    resetText: "\(used)/\(limit) on-demand",
                    windowDuration: windowDuration
                ))
            }
        }

        if limitType == "team",
           let teamUsage = json["teamUsage"] as? [String: Any],
           let teamOnDemand = teamUsage["onDemand"] as? [String: Any],
           let teamEnabled = teamOnDemand["enabled"] as? Bool, teamEnabled {
            let used = Self.intValue(from: teamOnDemand, key: "used") ?? 0
            let limit = Self.intValue(from: teamOnDemand, key: "limit") ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("Team"),
                    providerId: "cursor",
                    resetsAt: cycleEnd,
                    resetText: "\(used)/\(limit) team credits",
                    windowDuration: windowDuration
                ))
            }
        }

        if let isUnlimited = json["isUnlimited"] as? Bool, isUnlimited {
            quotas.append(UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Monthly"),
                providerId: "cursor",
                resetText: "Unlimited"
            ))
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No usage data found in Cursor response")
        }

        return UsageSnapshot(
            providerId: "cursor",
            quotas: quotas,
            capturedAt: Date(),
            accountTier: Self.accountTier(from: membershipType)
        )
    }

    /// Returns true when the official two-pool percentages were present.
    @discardableResult
    private static func appendTwoPoolQuotas(
        from planUsage: [String: Any]?,
        autoOverride: Double?,
        apiOverride: Double?,
        resetsAt: Date?,
        windowDuration: TimeInterval?,
        into quotas: inout [UsageQuota]
    ) -> Bool {
        guard let planUsage else { return false }
        if let enabled = planUsage["enabled"] as? Bool, enabled == false {
            return false
        }

        // Settings UI rounds via the display messages ("You've used 1%"); raw
        // `autoPercentUsed` can be 0.061 while the bar still says 1%.
        let autoPct = autoOverride ?? Self.doubleValue(from: planUsage, key: "autoPercentUsed")
        let apiPct = apiOverride ?? Self.doubleValue(from: planUsage, key: "apiPercentUsed")
        guard autoPct != nil || apiPct != nil else { return false }

        if let autoPct {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - autoPct),
                quotaType: .timeLimit(cursorModelsQuotaName),
                providerId: "cursor",
                resetsAt: resetsAt,
                windowDuration: windowDuration
            ))
        }
        if let apiPct {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - apiPct),
                quotaType: .timeLimit(otherModelsQuotaName),
                providerId: "cursor",
                resetsAt: resetsAt,
                windowDuration: windowDuration
            ))
        }
        return true
    }

    private static func appendLegacyMonthlyQuota(
        from planUsage: [String: Any]?,
        resetsAt: Date?,
        windowDuration: TimeInterval?,
        into quotas: inout [UsageQuota]
    ) {
        guard let planUsage,
              let enabled = planUsage["enabled"] as? Bool, enabled else { return }

        let used = Self.intValue(from: planUsage, key: "used") ?? 0
        let limit = Self.intValue(from: planUsage, key: "limit") ?? 0
        let breakdown = planUsage["breakdown"] as? [String: Any]
        let breakdownTotal = breakdown.flatMap { Self.intValue(from: $0, key: "total") } ?? 0
        let effectiveLimit = max(limit, breakdownTotal)
        guard effectiveLimit > 0 else { return }

        let percentRemaining: Double
        let effectiveUsed: Int
        if let totalPercentUsed = Self.doubleValue(from: planUsage, key: "totalPercentUsed") {
            percentRemaining = 100 - totalPercentUsed
            effectiveUsed = Int((totalPercentUsed * Double(effectiveLimit) / 100).rounded())
        } else {
            effectiveUsed = used
            percentRemaining = Double(effectiveLimit - used) / Double(effectiveLimit) * 100
        }

        quotas.append(UsageQuota(
            percentRemaining: max(0, percentRemaining),
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            resetsAt: resetsAt,
            resetText: "\(effectiveUsed)/\(effectiveLimit) requests",
            windowDuration: windowDuration
        ))
    }

    private static func appendPoolsFromDisplayMessages(
        autoMessage: String?,
        namedMessage: String?,
        resetsAt: Date?,
        windowDuration: TimeInterval?,
        into quotas: inout [UsageQuota]
    ) {
        guard let autoUsed = percentFromDisplayMessage(autoMessage),
              let apiUsed = percentFromDisplayMessage(namedMessage) else { return }

        quotas.append(UsageQuota(
            percentRemaining: max(0, 100 - autoUsed),
            quotaType: .timeLimit(cursorModelsQuotaName),
            providerId: "cursor",
            resetsAt: resetsAt,
            windowDuration: windowDuration
        ))
        quotas.append(UsageQuota(
            percentRemaining: max(0, 100 - apiUsed),
            quotaType: .timeLimit(otherModelsQuotaName),
            providerId: "cursor",
            resetsAt: resetsAt,
            windowDuration: windowDuration
        ))
    }

    static func accountTier(from membershipType: String) -> AccountTier? {
        let normalized = membershipType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "pro": return .custom("PRO")
        case "pro_plus", "proplus", "pro+": return .custom("PRO+")
        case "ultra": return .custom("ULTRA")
        case "start": return .custom("START")
        case "free", "hobby": return .custom("HOBBY")
        case "business", "team", "teams": return .custom("TEAMS")
        case "enterprise": return .custom("ENTERPRISE")
        default:
            return membershipType.isEmpty ? nil : .custom(membershipType.uppercased())
        }
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func percentFromDisplayMessage(_ message: String?) -> Double? {
        guard let message, let percentIndex = message.firstIndex(of: "%") else { return nil }
        let before = message[..<percentIndex]
        guard let start = before.lastIndex(where: { !$0.isNumber && $0 != "." }) else {
            return Double(before)
        }
        let number = before[before.index(after: start)...]
        return Double(number)
    }

    /// Safely extracts an Int from a JSON dictionary value that could be Int, Double, or NSNumber.
    private static func intValue(from dict: [String: Any], key: String) -> Int? {
        if let intVal = dict[key] as? Int {
            return intVal
        }
        if let doubleVal = dict[key] as? Double {
            return Int(doubleVal)
        }
        return nil
    }

    private static func doubleValue(from dict: [String: Any], key: String) -> Double? {
        if let doubleVal = dict[key] as? Double {
            return doubleVal
        }
        if let intVal = dict[key] as? Int {
            return Double(intVal)
        }
        return nil
    }
}

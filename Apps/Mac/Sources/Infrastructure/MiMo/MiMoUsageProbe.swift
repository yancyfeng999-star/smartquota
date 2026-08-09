import Foundation
import Domain

/// Probes Xiaomi MiMo **Token Plan** usage from the open platform console API.
///
/// - Uses browser / manual cookies (`api-platform_serviceToken` + `userId`).
/// - Does **not** read pay-as-you-go cash balance (`/balance`).
/// - Endpoints:
///   - `GET /api/v1/tokenPlan/detail` — plan name + period end
///   - `GET /api/v1/tokenPlan/usage` — used / limit credits
public struct MiMoUsageProbe: UsageProbe, @unchecked Sendable {
    private let networkClient: any NetworkClient
    private let settingsRepository: any MiMoSettingsRepository
    private let cookieProvider: any MiMoCookieProviding
    private let timeout: TimeInterval
    private let apiBaseURL: URL

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any MiMoSettingsRepository,
        cookieProvider: any MiMoCookieProviding = MiMoBrowserCookieProvider(),
        timeout: TimeInterval = 20,
        apiBaseURL: URL = URL(string: "https://platform.xiaomimimo.com/api/v1")!
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.cookieProvider = cookieProvider
        self.timeout = timeout
        self.apiBaseURL = apiBaseURL
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        (try? resolveCookie()) != nil
    }

    public func probe() async throws -> UsageSnapshot {
        let cookie = try resolveCookie()
        AppLog.probes.info("Starting MiMo Token Plan probe...")

        async let detailData = fetchJSON(path: "tokenPlan/detail", cookie: cookie)
        async let usageData = fetchJSON(path: "tokenPlan/usage", cookie: cookie)

        let detail = try await detailData
        let usage = try await usageData

        let snapshot = try Self.buildSnapshot(
            detailData: detail,
            usageData: usage,
            providerId: "mimo"
        )
        AppLog.probes.info(
            "MiMo probe success: \(snapshot.quotas.count) quotas, tier=\(snapshot.accountTier?.badgeText ?? "—")"
        )
        return snapshot
    }

    // MARK: - Cookie

    private func resolveCookie() throws -> String {
        switch settingsRepository.mimoCookieSource() {
        case .manual:
            guard let cookie = settingsRepository.getMimoManualCookie(),
                  let normalized = Self.normalizeCookieHeader(cookie)
            else {
                throw ProbeError.authenticationRequired
            }
            return normalized
        case .auto:
            if let cookie = cookieProvider.extractBrowserCookies(),
               let normalized = Self.normalizeCookieHeader(cookie) {
                return normalized
            }
            // Fall back to manual cookie if auto fails
            if let cookie = settingsRepository.getMimoManualCookie(),
               let normalized = Self.normalizeCookieHeader(cookie) {
                return normalized
            }
            throw ProbeError.authenticationRequired
        }
    }

    /// Requires `api-platform_serviceToken` + `userId`; keeps optional ph/slh.
    static func normalizeCookieHeader(_ raw: String) -> String? {
        var byName: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let name = String(piece[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(piece[piece.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !name.isEmpty, !value.isEmpty else { continue }
            byName[name] = value
        }
        let required = ["api-platform_serviceToken", "userId"]
        guard required.allSatisfy({ byName[$0] != nil }) else { return nil }
        let order = ["api-platform_serviceToken", "userId", "api-platform_ph", "api-platform_slh"]
        return order.compactMap { name in
            guard let value = byName[name] else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }

    // MARK: - Network

    private func fetchJSON(path: String, cookie: String) async throws -> Data {
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://platform.xiaomimimo.com", forHTTPHeaderField: "Origin")
        request.setValue(
            "https://platform.xiaomimimo.com/console/plan-manage",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("Asia/Shanghai", forHTTPHeaderField: "x-timeZone")

        let (data, response) = try await networkClient.request(request)
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProbeError.authenticationRequired
        }
        guard http.statusCode == 200 else {
            throw ProbeError.executionFailed("MiMo API HTTP \(http.statusCode) for \(path)")
        }
        if let text = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("MiMo \(path): \(text.prefix(400))")
        }
        return data
    }

    // MARK: - Parse (static for tests)

    static func buildSnapshot(
        detailData: Data,
        usageData: Data,
        providerId: String
    ) throws -> UsageSnapshot {
        let detail = try decodeEnvelope(detailData)
        let usage = try decodeEnvelope(usageData)

        guard detail.code == 0 else {
            throw ProbeError.executionFailed(detail.message.isEmpty ? "detail code \(detail.code)" : detail.message)
        }
        guard usage.code == 0 else {
            throw ProbeError.executionFailed(usage.message.isEmpty ? "usage code \(usage.code)" : usage.message)
        }

        let planName = string(detail.data?["planName"]) ?? string(detail.data?["planCode"])
        let periodEnd = parsePeriodEnd(string(detail.data?["currentPeriodEnd"]))
        let expired = bool(detail.data?["expired"]) == true

        let meter = pickPlanMeter(from: usage.data)
        guard let meter else {
            throw ProbeError.noData
        }

        let used = meter.used
        let limit = meter.limit
        guard limit > 0 else {
            throw ProbeError.noData
        }

        let remaining = max(0, min(100, (1 - used / limit) * 100))
        // Prefer API percent when present (0–1 scale); else computed remaining
        let remainingFromAPI: Double? = {
            guard let p = meter.percent, p >= 0, p <= 1 else { return nil }
            return max(0, min(100, (1 - p) * 100))
        }()
        let percentRemaining = remainingFromAPI ?? remaining

        var quotas: [UsageQuota] = []
        quotas.append(
            UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .timeLimit("Monthly"),
                providerId: providerId,
                resetsAt: periodEnd,
                resetText: formatUsedLimit(used: used, limit: limit),
                windowDuration: periodEnd.map { max(0, $0.timeIntervalSinceNow) },
                compactTitle: "Token Plan"
            )
        )

        var tiers: AccountTier?
        if let planName, !planName.isEmpty {
            let label = planName.localizedCaseInsensitiveContains("token")
                ? planName
                : "\(planName) Token Plan"
            tiers = .custom(label)
        }
        if expired {
            // Still show data but tier can hint expired
            if tiers == nil { tiers = .custom("Expired") }
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "console-cookie",
            accountTier: tiers,
            costUsage: nil
        )
    }

    // MARK: - JSON helpers

    private struct Envelope {
        let code: Int
        let message: String
        let data: [String: Any]?
    }

    private static func decodeEnvelope(_ data: Data) throws -> Envelope {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Invalid JSON")
        }
        let code = int(obj["code"]) ?? -1
        let message = string(obj["message"]) ?? ""
        let dataObj = obj["data"] as? [String: Any]
        return Envelope(code: code, message: message, data: dataObj)
    }

    private struct PlanMeter {
        let used: Double
        let limit: Double
        let percent: Double?
    }

    /// Prefer `usage.items` plan_total_token; fall back to monthUsage.
    private static func pickPlanMeter(from data: [String: Any]?) -> PlanMeter? {
        guard let data else { return nil }

        if let usage = data["usage"] as? [String: Any],
           let items = usage["items"] as? [[String: Any]] {
            if let plan = items.first(where: {
                (string($0["name"]) ?? "").lowercased().contains("plan_total")
            }) ?? items.first {
                if let m = meter(from: plan, fallbackPercent: double(usage["percent"])) {
                    return m
                }
            }
        }

        if let month = data["monthUsage"] as? [String: Any],
           let items = month["items"] as? [[String: Any]],
           let first = items.first {
            return meter(from: first, fallbackPercent: double(month["percent"]))
        }
        return nil
    }

    private static func meter(from item: [String: Any], fallbackPercent: Double?) -> PlanMeter? {
        guard let used = double(item["used"]),
              let limit = double(item["limit"]),
              limit > 0
        else { return nil }
        let percent = double(item["percent"]) ?? fallbackPercent
        return PlanMeter(used: used, limit: limit, percent: percent)
    }

    private static func parsePeriodEnd(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // console shows UTC
        for f in formats {
            formatter.dateFormat = f
            if let d = formatter.date(from: raw) { return d }
        }
        return nil
    }

    private static func formatUsedLimit(used: Double, limit: Double) -> String {
        "\(formatCredits(used)) / \(formatCredits(limit))"
    }

    private static func formatCredits(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        return String(format: "%.0f", value)
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func bool(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return nil
    }
}

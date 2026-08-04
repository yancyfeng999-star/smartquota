import Foundation
import Domain

/// Probes MiniMax Coding Plan API for usage quota information.
/// Supports both international (minimax.io) and China (minimaxi.com) regions.
/// Authentication: Bearer token from env var, stored API key, or local MiniMax Agent config.
public struct MiniMaxUsageProbe: UsageProbe, @unchecked Sendable {
    private let networkClient: any NetworkClient
    private let settingsRepository: any MiniMaxSettingsRepository
    private let timeout: TimeInterval
    private let fileManager: FileManager
    private let homeDirectory: URL

    /// Resolves the API URL based on the configured region.
    var apiURL: String {
        settingsRepository.minimaxRegion().codingPlanRemainsURL
    }

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any MiniMaxSettingsRepository,
        timeout: TimeInterval = 30,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // 1) Environment variable
        let envVarName = settingsRepository.minimaxAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "MINIMAX_API_KEY" : envVarName
        if let envValue = ProcessInfo.processInfo.environment[effectiveEnvVar], !envValue.isEmpty {
            AppLog.probes.debug("MiniMax: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // 2) Stored API key (Settings UI / Keychain-backed store)
        if let storedKey = settingsRepository.getMinimaxApiKey(), !storedKey.isEmpty {
            AppLog.probes.debug("MiniMax: Using stored API key")
            return storedKey
        }

        // 3) Local MiniMax Agent config: ~/.minimax/config.yaml
        //    Prefer custom_providers.minimaxtokenplan.apiKey (Coding Plan key).
        if let localKey = loadLocalCodingPlanKey() {
            AppLog.probes.debug("MiniMax: Using local ~/.minimax/config.yaml coding-plan key")
            return localKey
        }

        return nil
    }

    /// Reads `sk-cp-...` from local MiniMax Agent config without requiring Settings paste.
    func loadLocalCodingPlanKey() -> String? {
        let configURL = homeDirectory.appendingPathComponent(".minimax/config.yaml")
        guard fileManager.fileExists(atPath: configURL.path),
              let text = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return nil
        }

        // Prefer keys under the token-plan custom provider block.
        if let key = firstApiKey(in: text, preferSectionContaining: "minimaxtokenplan") {
            return key
        }

        // Fallback: any sk-cp key in the file.
        return firstApiKey(in: text, preferSectionContaining: nil)
    }

    private func firstApiKey(in text: String, preferSectionContaining sectionHint: String?) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var inPreferredSection = sectionHint == nil
        var preferredKey: String?
        var anyKey: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }

            if let sectionHint {
                // crude YAML section tracking for provider names
                if line.contains(sectionHint) {
                    inPreferredSection = true
                } else if line.hasSuffix(":") && !line.hasPrefix(" ") && !line.hasPrefix("-") && !line.contains("apiKey") {
                    // top-level-ish key may leave section; keep loose matching
                }
            }

            guard let key = extractApiKeyValue(from: rawLine) else { continue }
            if anyKey == nil { anyKey = key }
            if inPreferredSection {
                preferredKey = key
                // keep scanning only if we want the last one; first preferred is fine
                break
            }
        }

        return preferredKey ?? anyKey
    }

    private func extractApiKeyValue(from line: String) -> String? {
        // Match `apiKey: sk-cp-...` or `api_key: sk-cp-...`
        let pattern = #"(?i)(?:apiKey|api_key)\s*:\s*[\"']?(sk-cp-[A-Za-z0-9_\-]+)[\"']?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              let keyRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        let key = String(line[keyRange])
        return key.count > 20 ? key : nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("MiniMax: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("MiniMax: No API key configured (check env var, settings, or ~/.minimax/config.yaml)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting MiniMax probe...")

        // Prefer the verified modern endpoint first, then fall back to the
        // older openplatform path (kept as fallback).
        let region = settingsRepository.minimaxRegion()
        let candidateURLs = [
            "\(region.apiBaseURL)/v1/token_plan/remains",
            region.codingPlanRemainsURL,
        ]

        var lastError: Error = ProbeError.executionFailed("MiniMax: no endpoint succeeded")
        for urlString in candidateURLs {
            guard let url = URL(string: urlString) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = timeout

            do {
                let (data, response) = try await networkClient.request(request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ProbeError.executionFailed("Invalid response")
                }

                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw ProbeError.authenticationRequired
                }
                guard httpResponse.statusCode == 200 else {
                    throw ProbeError.executionFailed("MiniMax API returned HTTP \(httpResponse.statusCode)")
                }

                if let responseText = String(data: data, encoding: .utf8) {
                    AppLog.probes.debug("MiniMax API response (\(urlString)): \(responseText.prefix(500))")
                }

                // Reject soft-failures that still return HTTP 200
                if let softError = softAPIErrorMessage(in: data) {
                    AppLog.probes.warning("MiniMax soft error on \(urlString): \(softError)")
                    lastError = ProbeError.executionFailed(softError)
                    continue
                }

                let snapshot = try Self.parseResponse(data, providerId: "minimax")
                AppLog.probes.info("MiniMax probe success via \(urlString): \(snapshot.quotas.count) quotas")
                for quota in snapshot.quotas {
                    AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
                }
                return snapshot
            } catch {
                lastError = error
                AppLog.probes.warning("MiniMax endpoint failed \(urlString): \(error.localizedDescription)")
            }
        }

        throw lastError
    }

    private func softAPIErrorMessage(in data: Data) -> String? {
        // MiniMax often returns HTTP 200 with base_resp.status_code != 0
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let base = obj["base_resp"] as? [String: Any],
           let code = base["status_code"] as? Int,
           code != 0 {
            let msg = (base["status_msg"] as? String) ?? "status_code=\(code)"
            return msg
        }
        return nil
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the MiniMax Coding Plan remains API response into a UsageSnapshot.
    ///
    /// Live CN Token Plan responses look like:
    /// ```
    /// model_remains: [{
    ///   model_name: "general",
    ///   current_interval_remaining_percent: 99,   // 5h remaining %
    ///   current_weekly_remaining_percent: 99,     // weekly remaining %
    ///   end_time / weekly_end_time: epoch ms
    ///   current_interval_status / current_weekly_status: 1=limited, 3=unlimited
    /// }]
    /// ```
    /// Older request-count style responses only have total/usage counts.
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: MiniMaxRemainsResponse
        do {
            response = try decoder.decode(MiniMaxRemainsResponse.self, from: data)
        } catch {
            AppLog.probes.error("MiniMax parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("MiniMax raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        if response.baseResp.statusCode != 0 {
            let message = response.baseResp.statusMsg ?? "Unknown error"
            AppLog.probes.error("MiniMax API error: \(response.baseResp.statusCode) - \(message)")
            throw ProbeError.executionFailed("MiniMax API error: \(message)")
        }

        let modelRemains = response.modelRemains ?? []
        guard !modelRemains.isEmpty else {
            AppLog.probes.error("MiniMax: Empty model_remains in response")
            throw ProbeError.noData
        }

        // Prefer the general/text coding pool; fall back to first entry.
        let primary = modelRemains.first(where: { $0.modelName.lowercased() == "general" })
            ?? modelRemains[0]

        var quotas: [UsageQuota] = []

        // --- 5h / interval window ---
        if let sessionQuota = makeIntervalQuota(from: primary, providerId: providerId) {
            quotas.append(sessionQuota)
        }

        // --- weekly window ---
        if let weeklyQuota = makeWeeklyQuota(from: primary, providerId: providerId) {
            quotas.append(weeklyQuota)
        }

        // Optional: expose non-primary pools (e.g. video / extra models)
        for model in modelRemains where model.modelName.lowercased() != primary.modelName.lowercased() {
            if let extra = makeModelSpecificQuota(from: model, providerId: providerId) {
                quotas.append(extra)
            }
        }

        guard !quotas.isEmpty else {
            throw ProbeError.noData
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date()
        )
    }

    private static func makeIntervalQuota(from model: ModelRemain, providerId: String) -> UsageQuota? {
        // status 3 = unlimited window
        if model.currentIntervalStatus == 3 {
            return UsageQuota(
                percentRemaining: 100,
                quotaType: .session,
                providerId: providerId,
                resetsAt: model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                resetText: "Unlimited 5h window",
                windowDuration: windowDurationSeconds(start: model.startTime, end: model.endTime)
            )
        }

        if let pct = model.currentIntervalRemainingPercent {
            return UsageQuota(
                percentRemaining: Double(pct),
                quotaType: .session,
                providerId: providerId,
                resetsAt: model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                resetText: "5h remaining \(pct)%",
                windowDuration: windowDurationSeconds(start: model.startTime, end: model.endTime)
            )
        }

        // Legacy request-count shape
        let total = model.currentIntervalTotalCount ?? 0
        let remainingCount = model.currentIntervalUsageCount ?? 0
        guard total > 0 else { return nil }
        // Upstream note: usage_count is remaining, not used
        let clampedRemaining = min(max(remainingCount, 0), total)
        let remaining = Double(clampedRemaining) / Double(total) * 100.0
        let usedCount = total - clampedRemaining
        return UsageQuota(
            percentRemaining: remaining,
            quotaType: .session,
            providerId: providerId,
            resetsAt: model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
            resetText: "\(usedCount)/\(total) requests",
            windowDuration: windowDurationSeconds(start: model.startTime, end: model.endTime)
        )
    }

    private static func makeWeeklyQuota(from model: ModelRemain, providerId: String) -> UsageQuota? {
        if model.currentWeeklyStatus == 3 {
            return UsageQuota(
                percentRemaining: 100,
                quotaType: .weekly,
                providerId: providerId,
                resetsAt: model.weeklyEndTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                resetText: "Unlimited weekly",
                windowDuration: windowDurationSeconds(start: model.weeklyStartTime, end: model.weeklyEndTime)
            )
        }

        if let pct = model.currentWeeklyRemainingPercent {
            return UsageQuota(
                percentRemaining: Double(pct),
                quotaType: .weekly,
                providerId: providerId,
                resetsAt: model.weeklyEndTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                resetText: "Weekly remaining \(pct)%",
                windowDuration: windowDurationSeconds(start: model.weeklyStartTime, end: model.weeklyEndTime)
            )
        }

        let total = model.currentWeeklyTotalCount ?? 0
        let remainingCount = model.currentWeeklyUsageCount ?? 0
        guard total > 0 else { return nil }
        let clampedRemaining = min(max(remainingCount, 0), total)
        let remaining = Double(clampedRemaining) / Double(total) * 100.0
        let usedCount = total - clampedRemaining
        return UsageQuota(
            percentRemaining: remaining,
            quotaType: .weekly,
            providerId: providerId,
            resetsAt: model.weeklyEndTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
            resetText: "\(usedCount)/\(total) weekly requests",
            windowDuration: windowDurationSeconds(start: model.weeklyStartTime, end: model.weeklyEndTime)
        )
    }

    private static func makeModelSpecificQuota(from model: ModelRemain, providerId: String) -> UsageQuota? {
        if model.currentIntervalStatus == 3 {
            return nil // unlimited secondary pool — skip noise
        }

        if let pct = model.currentIntervalRemainingPercent {
            return UsageQuota(
                percentRemaining: Double(pct),
                quotaType: .modelSpecific(model.modelName),
                providerId: providerId,
                resetsAt: model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                resetText: "\(model.modelName) interval",
                windowDuration: windowDurationSeconds(start: model.startTime, end: model.endTime)
            )
        }

        let total = model.currentIntervalTotalCount ?? 0
        let remainingCount = model.currentIntervalUsageCount ?? 0
        guard total > 0 else { return nil }
        let clampedRemaining = min(max(remainingCount, 0), total)
        let remaining = Double(clampedRemaining) / Double(total) * 100.0
        let usedCount = total - clampedRemaining
        return UsageQuota(
            percentRemaining: remaining,
            quotaType: .modelSpecific(model.modelName),
            providerId: providerId,
            resetsAt: model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
            resetText: "\(usedCount)/\(total) requests",
            windowDuration: windowDurationSeconds(start: model.startTime, end: model.endTime)
        )
    }

    private static func windowDurationSeconds(start: Int64?, end: Int64?) -> TimeInterval? {
        guard let start, let end, end > start else { return nil }
        return TimeInterval(end - start) / 1000.0
    }
}

// MARK: - Response Models (Internal)

struct MiniMaxRemainsResponse: Decodable {
    let baseResp: BaseResp
    let modelRemains: [ModelRemain]?
}

struct BaseResp: Decodable {
    let statusCode: Int
    let statusMsg: String?
}

struct ModelRemain: Decodable {
    let modelName: String

    // Percent-based Token Plan fields (authoritative for CN coding plan)
    let currentIntervalRemainingPercent: Int?
    let currentWeeklyRemainingPercent: Int?
    let currentIntervalStatus: Int?
    let currentWeeklyStatus: Int?

    // Legacy / count-based fields
    let currentIntervalTotalCount: Int?
    let currentIntervalUsageCount: Int?
    let currentWeeklyTotalCount: Int?
    let currentWeeklyUsageCount: Int?

    // Timestamps (epoch ms)
    let startTime: Int64?
    let endTime: Int64?
    let weeklyStartTime: Int64?
    let weeklyEndTime: Int64?
    let remainsTime: Int?
    let weeklyRemainsTime: Int?
}

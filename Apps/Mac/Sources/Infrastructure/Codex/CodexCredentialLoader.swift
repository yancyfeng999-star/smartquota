import Foundation
import Domain

/// Codex OAuth credentials loaded from `~/.codex/auth.json`.
public struct CodexCredentialResult: @unchecked Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var accountId: String?
    public var lastRefresh: String?
    public var idToken: String?
    public var fullData: [String: Any]

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        accountId: String? = nil,
        lastRefresh: String? = nil,
        idToken: String? = nil,
        fullData: [String: Any]
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.lastRefresh = lastRefresh
        self.idToken = idToken
        self.fullData = fullData
    }
}

/// Loads Codex OAuth credentials from `~/.codex/auth.json`.
///
/// The auth file has the format:
/// ```json
/// {
///   "tokens": {
///     "access_token": "...",
///     "refresh_token": "...",
///     "account_id": "..."
///   },
///   "last_refresh": "2025-01-15T10:00:00.000Z"
/// }
/// ```
public struct CodexCredentialLoader: Sendable {
    private let homeDirectory: String

    /// Refresh age threshold: 8 days (matching Codex JS reference)
    private static let refreshAgeMs: Double = 8 * 24 * 60 * 60 * 1000

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    /// The path to the auth file.
    public var authFilePath: String {
        (homeDirectory as NSString).appendingPathComponent(".codex/auth.json")
    }

    /// Loads credentials from `~/.codex/auth.json`.
    /// Returns nil if no valid OAuth credentials are found.
    /// Note: API key auth (`OPENAI_API_KEY`) is not supported for usage API.
    public func loadCredentials() -> CodexCredentialResult? {
        let path = authFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            // Check for OAuth tokens (not API key)
            guard let tokens = json["tokens"] as? [String: Any],
                  let accessToken = tokens["access_token"] as? String,
                  !accessToken.isEmpty else {
                return nil
            }

            let refreshToken = tokens["refresh_token"] as? String
            let accountId = tokens["account_id"] as? String
            let lastRefresh = json["last_refresh"] as? String
            let idToken = tokens["id_token"] as? String

            return CodexCredentialResult(
                accessToken: accessToken,
                refreshToken: refreshToken,
                accountId: accountId,
                lastRefresh: lastRefresh,
                idToken: idToken,
                fullData: json
            )
        } catch {
            AppLog.credentials.error("Failed to load Codex credentials from file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Checks if the token needs to be refreshed based on `last_refresh` date.
    /// Refresh is needed if `last_refresh` is nil or older than 8 days.
    public func needsRefresh(lastRefresh: String?) -> Bool {
        guard let lastRefresh else { return true }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lastDate = formatter.date(from: lastRefresh)

        if lastDate == nil {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            lastDate = formatter.date(from: lastRefresh)
        }

        guard let lastDate else { return true }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let lastMs = lastDate.timeIntervalSince1970 * 1000
        return nowMs - lastMs > Self.refreshAgeMs
    }

    /// Saves updated credentials back to the auth file.
    public func saveCredentials(_ result: CodexCredentialResult) {
        var updatedData = result.fullData

        // Update the tokens section
        var tokens: [String: Any] = [
            "access_token": result.accessToken
        ]
        if let refreshToken = result.refreshToken {
            tokens["refresh_token"] = refreshToken
        }
        if let accountId = result.accountId {
            tokens["account_id"] = accountId
        }
        if let idToken = result.idToken {
            tokens["id_token"] = idToken
        }
        // Preserve any other token fields (like id_token)
        if let existingTokens = updatedData["tokens"] as? [String: Any] {
            for (key, value) in existingTokens {
                if tokens[key] == nil {
                    tokens[key] = value
                }
            }
        }
        updatedData["tokens"] = tokens

        if let lastRefresh = result.lastRefresh {
            updatedData["last_refresh"] = lastRefresh
        }

        let path = authFilePath
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: updatedData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
            AppLog.credentials.info("Saved updated Codex credentials to file")
        } catch {
            AppLog.credentials.error("Failed to save Codex credentials to file: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Identity

    /// Resolves the current account identity from credentials.
    ///
    /// Priority:
    /// 1. Email from `id_token` JWT payload (non-sensitive `email` claim only)
    /// 2. `account_id` from auth file
    ///
    /// Returns `(externalId, identitySource)` or `nil` if no identity is available.
    public func resolveAccountIdentity(_ credentials: CodexCredentialResult) -> (externalId: String, source: AccountIdentitySource)? {
        // Try email from id_token first
        if let idToken = credentials.idToken,
           let email = Self.extractEmailFromJWT(idToken), !email.isEmpty {
            AppLog.credentials.info("Codex account identity: resolved from id_token email")
            return (email, .email)
        }

        // Fall back to account_id
        if let accountId = credentials.accountId, !accountId.isEmpty {
            AppLog.credentials.info("Codex account identity: resolved from account_id")
            return (accountId, .external)
        }

        return nil
    }

    /// Extracts only the `email` claim from a JWT's payload section.
    ///
    /// This deliberately parses only the payload (not the header or signature)
    /// and extracts only the non-sensitive `email` claim. The `sub` claim
    /// (which contains a persistent user ID) is intentionally NOT extracted
    /// to avoid storing or logging a stable cross-service identifier.
    ///
    /// Returns nil if the JWT is malformed, missing the email claim, or
    /// the payload cannot be decoded.
    static func extractEmailFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        // JWT payload is base64url-encoded
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: base64) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        return json["email"] as? String
    }
}

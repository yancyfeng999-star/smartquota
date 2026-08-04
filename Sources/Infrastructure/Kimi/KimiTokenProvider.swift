import Foundation
import SweetCookieKit
import Domain

/// Protocol for resolving Kimi authentication tokens.
/// Enables testability by allowing mock implementations.
public protocol KimiTokenProviding: Sendable {
    func resolveToken() throws -> String
}

/// Resolved Kimi credential with its source kind.
public enum KimiCredentialKind: Sendable, Equatable {
    /// Coding API key (`sk-kimi-...`) — use coding/v1/usages
    case codingAPIKey
    /// Web session / cookie JWT — use billing GetUsages
    case webSession
}

public struct KimiResolvedCredential: Sendable, Equatable {
    public let token: String
    public let kind: KimiCredentialKind

    public init(token: String, kind: KimiCredentialKind) {
        self.token = token
        self.kind = kind
    }
}

/// Resolves Kimi authentication from (in order):
/// 1. `KIMI_AUTH_TOKEN` / `KIMI_API_KEY` / `KIMI_CODE_API_KEY` env vars
/// 2. Local Kimi Desktop coding key (`~/Library/Application Support/kimi-desktop/...`)
/// 3. Browser `kimi-auth` cookie
public struct KimiCookieTokenProvider: KimiTokenProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let applicationSupportDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public func resolveToken() throws -> String {
        try resolveCredential().token
    }

    public func resolveCredential() throws -> KimiResolvedCredential {
        // 1. Environment variables
        for envName in ["KIMI_CODE_API_KEY", "KIMI_API_KEY", "KIMI_AUTH_TOKEN"] {
            if let envToken = ProcessInfo.processInfo.environment[envName]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !envToken.isEmpty {
                let kind: KimiCredentialKind = envToken.hasPrefix("sk-kimi") ? .codingAPIKey : .webSession
                AppLog.probes.debug("Kimi: Using token from \(envName) (\(kind))")
                return KimiResolvedCredential(token: envToken, kind: kind)
            }
        }

        // 2. Local Kimi Desktop coding key
        if let localKey = loadLocalCodingAPIKey() {
            AppLog.probes.debug("Kimi: Using local kimi-desktop coding API key")
            return KimiResolvedCredential(token: localKey, kind: .codingAPIKey)
        }

        // 3. Browser cookie
        if let browserToken = fetchFromBrowser() {
            AppLog.probes.debug("Kimi: Using token from browser cookie")
            return KimiResolvedCredential(token: browserToken, kind: .webSession)
        }

        AppLog.probes.error("Kimi: No authentication token found")
        throw ProbeError.authenticationRequired
    }

    /// Reads sk-kimi key from Kimi Desktop local config.
    func loadLocalCodingAPIKey() -> String? {
        let candidates: [URL] = [
            applicationSupportDirectory
                .appendingPathComponent("kimi-desktop/daimon-share/daimon/config.json"),
            applicationSupportDirectory
                .appendingPathComponent("kimi-desktop/daimon-share/config.toml"),
            homeDirectory.appendingPathComponent(".kimi-code/credentials/kimi-code.json"),
            homeDirectory.appendingPathComponent(".kimi/credentials.json"),
        ]

        for url in candidates {
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            if url.pathExtension == "json" {
                if let key = extractJSONCodingKey(from: text) {
                    return key
                }
            } else {
                if let key = extractTOMLOrTextCodingKey(from: text) {
                    return key
                }
            }
        }
        return nil
    }

    private func extractJSONCodingKey(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            // fallback regex
            return extractTOMLOrTextCodingKey(from: text)
        }

        // Walk common shapes:
        // credentials.kimiCode.apiKey
        // apiKey / key / api_key
        func walk(_ any: Any) -> String? {
            if let dict = any as? [String: Any] {
                for keyName in ["apiKey", "api_key", "key"] {
                    if let value = dict[keyName] as? String,
                       value.hasPrefix("sk-kimi"),
                       value.count > 20 {
                        return value
                    }
                }
                // prefer nested kimiCode
                if let kimiCode = dict["kimiCode"] {
                    if let found = walk(kimiCode) { return found }
                }
                if let credentials = dict["credentials"] {
                    if let found = walk(credentials) { return found }
                }
                for (_, value) in dict {
                    if let found = walk(value) { return found }
                }
            } else if let arr = any as? [Any] {
                for value in arr {
                    if let found = walk(value) { return found }
                }
            }
            return nil
        }

        return walk(obj) ?? extractTOMLOrTextCodingKey(from: text)
    }

    private func extractTOMLOrTextCodingKey(from text: String) -> String? {
        let pattern = #"sk-kimi-[A-Za-z0-9_\-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let keyRange = Range(match.range, in: text)
        else { return nil }
        let key = String(text[keyRange])
        return key.count > 20 ? key : nil
    }

    private func fetchFromBrowser() -> String? {
        let cookieClient = BrowserCookieClient()
        let query = BrowserCookieQuery(
            domains: ["www.kimi.com", "kimi.com"],
            domainMatch: .suffix,
            includeExpired: false
        )

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    if let auth = cookies.first(where: { $0.name == "kimi-auth" }),
                       !auth.value.isEmpty {
                        return auth.value
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

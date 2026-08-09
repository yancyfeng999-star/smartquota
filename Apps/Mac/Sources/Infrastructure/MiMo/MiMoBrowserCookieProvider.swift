import Foundation
import SweetCookieKit
import Domain

/// Reads Xiaomi MiMo open-platform session cookies from local browsers.
public struct MiMoBrowserCookieProvider: MiMoCookieProviding {
    public init() {}

    public func extractBrowserCookies() -> String? {
        let cookieClient = BrowserCookieClient()
        let query = BrowserCookieQuery(
            domains: [
                "platform.xiaomimimo.com",
                "xiaomimimo.com",
            ],
            domainMatch: .suffix,
            includeExpired: false
        )

        let required: Set<String> = [
            "api-platform_serviceToken",
            "userId",
        ]
        let optional: Set<String> = [
            "api-platform_ph",
            "api-platform_slh",
        ]
        let wanted = required.union(optional)

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    var byName: [String: String] = [:]
                    for cookie in cookies where wanted.contains(cookie.name) {
                        let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        guard !value.isEmpty else { continue }
                        byName[cookie.name] = value
                    }
                    guard required.isSubset(of: Set(byName.keys)) else { continue }

                    let header = byName.keys.sorted().compactMap { name -> String? in
                        guard let value = byName[name] else { return nil }
                        return "\(name)=\(value)"
                    }.joined(separator: "; ")

                    AppLog.probes.debug("MiMo: Found browser cookies from \(browser)")
                    return header
                }
            } catch {
                continue
            }
        }
        AppLog.probes.debug("MiMo: No browser cookies found")
        return nil
    }
}

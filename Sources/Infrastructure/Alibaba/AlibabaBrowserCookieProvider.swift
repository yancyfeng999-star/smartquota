import Foundation
import SweetCookieKit
import Domain

/// Resolves Alibaba Cloud authentication cookies from browser cookie stores.
///
/// Searches for aliyun.com / alibabacloud.com cookies across all supported browsers
/// using SweetCookieKit. Used when cookie source is set to "auto".
public struct AlibabaBrowserCookieProvider: AlibabaCookieProviding {
    public init() {}

    public func extractBrowserCookies() -> String? {
        let cookieClient = BrowserCookieClient()
        let query = BrowserCookieQuery(
            domains: [
                "aliyun.com",
                "console.aliyun.com",
                "bailian.console.aliyun.com",
                "alibabacloud.com",
                "console.alibabacloud.com",
                "modelstudio.console.alibabacloud.com",
            ],
            domainMatch: .suffix,
            includeExpired: false
        )

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    // Look for authentication-related cookies
                    let authCookieNames: Set<String> = [
                        "login_aliyunid_ticket",
                        "login_aliyunid_csrf",
                        "sec_token",
                        "aliyun_choice",
                        "cna",
                    ]
                    let matchedCookies = cookies.filter { authCookieNames.contains($0.name) }
                    if !matchedCookies.isEmpty {
                        let cookieString = matchedCookies
                            .map { "\($0.name)=\($0.value)" }
                            .joined(separator: "; ")
                        AppLog.probes.debug("Alibaba: Found browser cookies from \(browser)")
                        return cookieString
                    }
                }
            } catch {
                continue
            }
        }
        AppLog.probes.debug("Alibaba: No browser cookies found")
        return nil
    }
}

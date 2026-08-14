import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("GitHubReleaseChecker")
struct GitHubReleaseCheckerTests {
    @Test
    func `picks newest mac release and ignores windows`() async throws {
        let json = """
        [
          {
            "tag_name": "windows-v0.1.0",
            "html_url": "https://github.com/example/smartquota/releases/tag/windows-v0.1.0",
            "draft": false,
            "prerelease": false,
            "assets": [
              { "name": "SmartQuota-Setup-0.1.0-x64.exe", "browser_download_url": "https://example.com/setup.exe" }
            ]
          },
          {
            "tag_name": "v0.3.2",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.3.2",
            "draft": false,
            "prerelease": false,
            "assets": [
              { "name": "SmartQuota-0.3.2.dmg", "browser_download_url": "https://example.com/0.3.2.dmg" }
            ]
          },
          {
            "tag_name": "v0.3.4",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.3.4",
            "draft": false,
            "prerelease": false,
            "assets": [
              { "name": "智额-0.3.4.dmg", "browser_download_url": "https://example.com/0.3.4.dmg" }
            ]
          },
          {
            "tag_name": "v0.9.0-beta",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.9.0-beta",
            "draft": false,
            "prerelease": true,
            "assets": [
              { "name": "SmartQuota-0.9.0.dmg", "browser_download_url": "https://example.com/beta.dmg" }
            ]
          }
        ]
        """.data(using: .utf8)!

        let client = MockNetworkClient()
        given(client)
            .request(.any)
            .willReturn((json, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/x/y/releases")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!))

        let checker = GitHubReleaseChecker(networkClient: client)
        let latest = try await checker.fetchLatestMacRelease()
        #expect(latest.version.description == "0.3.4")
        #expect(latest.downloadURL?.absoluteString == "https://example.com/0.3.4.dmg")
        #expect(latest.sha256 == nil, "legacy assets without digest stay nil")

        let available = try await checker.check(currentVersionString: "0.3.2")
        guard case .updateAvailable(_, let rel) = available else {
            Issue.record("expected update available")
            return
        }
        #expect(rel.version.description == "0.3.4")

        let current = try await checker.check(currentVersionString: "0.3.4")
        #expect(current == .upToDate(current: AppVersion(string: "0.3.4")!))
    }

    @Test
    func `throws when only windows releases exist`() async throws {
        let json = """
        [
          {
            "tag_name": "windows-v0.1.0",
            "html_url": "https://github.com/example/smartquota/releases/tag/windows-v0.1.0",
            "draft": false,
            "prerelease": false,
            "assets": [
              { "name": "Setup.exe", "browser_download_url": "https://example.com/setup.exe" }
            ]
          }
        ]
        """.data(using: .utf8)!

        let client = MockNetworkClient()
        given(client)
            .request(.any)
            .willReturn((json, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/x/y/releases")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!))

        let checker = GitHubReleaseChecker(networkClient: client)
        do {
            _ = try await checker.fetchLatestMacRelease()
            Issue.record("expected throw")
        } catch let error as ManualUpdateError {
            #expect(error == .noMacReleaseFound)
        }
    }

    @Test
    func `parses notes date size checksum and ignores prerelease`() async throws {
        let json = """
        [
          {
            "tag_name": "v0.9.0-beta",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.9.0-beta",
            "body": "Beta only",
            "published_at": "2026-08-13T00:00:00Z",
            "draft": false,
            "prerelease": true,
            "assets": [
              {
                "name": "SmartQuota-0.9.0.pkg",
                "browser_download_url": "https://example.com/beta.pkg",
                "size": 10,
                "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
              }
            ]
          },
          {
            "tag_name": "v0.3.29",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.3.29",
            "body": "安全更新说明。\\nmacOS 15.1 或更高。",
            "published_at": "2026-08-14T12:00:00Z",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "SmartQuota-0.3.29.pkg",
                "browser_download_url": "https://example.com/0.3.29.pkg",
                "size": 4096,
                "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
              },
              {
                "name": "SHA256SUMS-github.txt",
                "browser_download_url": "https://example.com/SHA256SUMS-github.txt",
                "size": 80
              }
            ]
          }
        ]
        """.data(using: .utf8)!

        let client = MockNetworkClient()
        given(client)
            .request(.any)
            .willReturn((json, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/x/y/releases")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!))

        let latest = try await GitHubReleaseChecker(networkClient: client).fetchLatestMacRelease()
        #expect(latest.version.description == "0.3.29")
        #expect(latest.releaseNotes.contains("安全更新说明"))
        #expect(latest.publishedAt != nil)
        #expect(latest.assetSize == 4096)
        #expect(latest.sha256 == String(repeating: "a", count: 64))
        #expect(latest.minimumOS?.majorVersion == 15)
        #expect(latest.minimumOS?.minorVersion == 1)
    }

    @Test
    func `fills sha256 from checksums asset when digest is missing`() async throws {
        let list = """
        [
          {
            "tag_name": "v0.3.29",
            "html_url": "https://github.com/example/smartquota/releases/tag/v0.3.29",
            "body": "macOS 15.0",
            "published_at": "2026-08-14T00:00:00Z",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "SmartQuota-0.3.29.pkg",
                "browser_download_url": "https://example.com/0.3.29.pkg",
                "size": 88
              },
              {
                "name": "SHA256SUMS-github.txt",
                "browser_download_url": "https://example.com/SHA256SUMS-github.txt",
                "size": 90
              }
            ]
          }
        ]
        """.data(using: .utf8)!
        let sums = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  SmartQuota-0.3.29.pkg\n"
            .data(using: .utf8)!

        let client = RoutingNetworkClient { request in
            let url = request.url?.absoluteString ?? ""
            let body = url.contains("SHA256SUMS") ? sums : list
            return (body, HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let latest = try await GitHubReleaseChecker(networkClient: client).fetchLatestMacRelease()
        #expect(latest.sha256 == String(repeating: "c", count: 64))
        #expect(latest.assetSize == 88)
    }
}

private struct RoutingNetworkClient: NetworkClient {
    let handler: @Sendable (URLRequest) -> (Data, URLResponse)

    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        handler(request)
    }
}

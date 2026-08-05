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
}

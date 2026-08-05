import Foundation
import Domain

/// Fetches the latest **Mac** release from public GitHub Releases.
///
/// Free path via public GitHub Releases (no Sparkle, no private update server).
public struct GitHubReleaseChecker: Sendable {
    private let networkClient: any NetworkClient
    private let apiURL: URL

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        apiURL: URL = AppIdentity.githubReleasesAPIURL
    ) {
        self.networkClient = networkClient
        self.apiURL = apiURL
    }

    /// Returns the newest non-draft, non-prerelease Mac release.
    public func fetchLatestMacRelease() async throws -> RemoteRelease {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SmartQuota (manual-update-check)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            throw ManualUpdateError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ManualUpdateError.network("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ManualUpdateError.network("HTTP \(http.statusCode)")
        }

        let decoded: [GitHubReleaseDTO]
        do {
            decoded = try JSONDecoder().decode([GitHubReleaseDTO].self, from: data)
        } catch {
            throw ManualUpdateError.decode(error.localizedDescription)
        }

        let candidates: [RemoteRelease] = decoded.compactMap { dto in
            guard !dto.draft, !dto.prerelease else { return nil }
            let assetNames = dto.assets.map(\.name)
            guard ReleaseTagClassifier.isMacCandidate(tag: dto.tagName, assetNames: assetNames) else {
                return nil
            }
            guard let version = AppVersion(string: dto.tagName) else { return nil }
            guard let htmlURL = URL(string: dto.htmlURL) else { return nil }

            let pairs: [(name: String, url: URL)] = dto.assets.compactMap { asset in
                guard let url = URL(string: asset.browserDownloadURL) else { return nil }
                return (asset.name, url)
            }
            let download = ManualUpdateEvaluator.preferredDownloadURL(assetNamesAndURLs: pairs)

            return RemoteRelease(
                version: version,
                tagName: dto.tagName,
                htmlURL: htmlURL,
                downloadURL: download
            )
        }

        guard let latest = ManualUpdateEvaluator.pickLatest(candidates) else {
            throw ManualUpdateError.noMacReleaseFound
        }
        return latest
    }

    /// Compare installed bundle version with the latest Mac release.
    public func check(currentVersionString: String) async throws -> ManualUpdateResult {
        guard let current = AppVersion(string: currentVersionString) else {
            throw ManualUpdateError.invalidCurrentVersion
        }
        let latest = try await fetchLatestMacRelease()
        return ManualUpdateEvaluator.evaluate(current: current, latest: latest)
    }
}

// MARK: - GitHub API DTOs

private struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubAssetDTO: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

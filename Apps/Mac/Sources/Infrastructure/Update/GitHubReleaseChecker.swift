import Foundation
import Domain

/// Fetches the latest **Mac** release from public GitHub Releases.
///
/// Free path via public GitHub Releases (no Sparkle, no private update server).
/// Stable releases only; Beta channel is owned by a later task.
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

        var checksumURLs: [AppVersion: URL] = [:]
        var nameHints: [AppVersion: [String]] = [:]

        let candidates: [RemoteRelease] = decoded.compactMap { dto in
            guard !dto.draft, !dto.prerelease else { return nil }
            let assetNames = dto.assets.map(\.name)
            guard ReleaseTagClassifier.isMacCandidate(tag: dto.tagName, assetNames: assetNames) else {
                return nil
            }
            guard let version = AppVersion(string: dto.tagName) else { return nil }
            guard let htmlURL = URL(string: dto.htmlURL) else { return nil }

            let pairs: [(name: String, url: URL, size: Int64?, digest: String?)] = dto.assets.compactMap { asset in
                guard let url = URL(string: asset.browserDownloadURL) else { return nil }
                return (asset.name, url, asset.size, asset.digest)
            }
            let download = ManualUpdateEvaluator.preferredDownloadURL(
                assetNamesAndURLs: pairs.map { ($0.name, $0.url) }
            )
            let chosen = pairs.first { $0.url == download }
            var sha = ReleaseMetadataParser.sha256(fromGitHubDigest: chosen?.digest)
            if sha == nil {
                let names = pairs.map(\.name) + [download?.lastPathComponent].compactMap { $0 }
                sha = ReleaseMetadataParser.sha256(fromChecksums: dto.body ?? "", matching: names)
            }
            if sha == nil, let sums = pairs.first(where: { Self.isChecksumsAsset($0.name) }) {
                checksumURLs[version] = sums.url
                nameHints[version] = pairs.map(\.name) + [download?.lastPathComponent].compactMap { $0 }
            }

            return RemoteRelease(
                version: version,
                tagName: dto.tagName,
                htmlURL: htmlURL,
                downloadURL: download,
                releaseNotes: dto.body ?? "",
                publishedAt: Self.parseDate(dto.publishedAt),
                minimumOS: ReleaseMetadataParser.minimumOS(from: dto.body ?? ""),
                assetSize: chosen?.size,
                sha256: sha
            )
        }

        guard var latest = ManualUpdateEvaluator.pickLatest(candidates) else {
            throw ManualUpdateError.noMacReleaseFound
        }

        if (latest.sha256 == nil || latest.sha256?.isEmpty == true),
           let sumsURL = checksumURLs[latest.version] {
            let names = nameHints[latest.version] ?? []
            if let filled = try? await fetchChecksum(from: sumsURL, matching: names) {
                latest = RemoteRelease(
                    version: latest.version,
                    tagName: latest.tagName,
                    htmlURL: latest.htmlURL,
                    downloadURL: latest.downloadURL,
                    releaseNotes: latest.releaseNotes,
                    publishedAt: latest.publishedAt,
                    minimumOS: latest.minimumOS,
                    assetSize: latest.assetSize,
                    sha256: filled
                )
            }
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

    private func fetchChecksum(from url: URL, matching names: [String]) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("SmartQuota (manual-update-check)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return ReleaseMetadataParser.sha256(fromChecksums: text, matching: names)
    }

    private static func isChecksumsAsset(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("sha256") && lower.hasSuffix(".txt")
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

// MARK: - GitHub API DTOs

private struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let publishedAt: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubAssetDTO: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String
    let size: Int64?
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

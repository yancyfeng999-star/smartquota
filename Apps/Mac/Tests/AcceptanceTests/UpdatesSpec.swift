import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Updates
///
/// Users inspect release notes, then confirm download/install in the update area.
///
/// Behaviors covered:
/// - already latest / new version / low OS / no asset
/// - download timeout / cancel / install fail keeps current app
@Suite("Feature: Updates")
struct UpdatesSpec {
    private let runningOS = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)

    @Test
    func `already latest does not offer download`() async throws {
        let json = releaseJSON(
            tag: "v0.3.28",
            notes: "已发布。\nmacOS 15.0 或更高。",
            assets: [pkgAsset(version: "0.3.28")]
        )
        let latest = try await checker(json: json).fetchLatestMacRelease()
        let assessment = ManualUpdateEvaluator.assess(
            current: AppVersion(string: "0.3.28")!,
            latest: latest,
            runningOS: runningOS
        )
        #expect(assessment == .upToDate(current: AppVersion(string: "0.3.28")!))
        #expect(!assessment.allowsDownload)
        let snapshot = UpdateDetailsSnapshot.make(assessment: assessment)
        #expect(snapshot.currentVersion == "0.3.28")
        #expect(snapshot.latestVersion == nil)
    }

    @Test
    func `new version exposes notes size date and min OS then allows download`() async throws {
        let json = releaseJSON(
            tag: "v0.3.29",
            notes: "变更说明：安全更新体验。\nmacOS 15.0 或更高。",
            assets: [pkgAsset(version: "0.3.29", size: 4_096)],
            published: "2026-08-14T00:00:00Z"
        )
        let checker = checker(json: json)
        let result = try await checker.check(currentVersionString: "0.3.28")
        guard case .updateAvailable(let current, let latest) = result else {
            Issue.record("expected updateAvailable")
            return
        }
        #expect(current.description == "0.3.28")
        #expect(latest.version.description == "0.3.29")
        #expect(latest.releaseNotes.contains("安全更新体验"))
        #expect(latest.assetSize == 4_096)
        #expect(latest.sha256 == String(repeating: "a", count: 64))
        #expect(latest.minimumOS?.majorVersion == 15)
        #expect(latest.publishedAt != nil)

        let assessment = ManualUpdateEvaluator.assess(current: current, latest: latest, runningOS: runningOS)
        #expect(assessment.allowsDownload)
        let snapshot = UpdateDetailsSnapshot.make(assessment: assessment)
        #expect(snapshot.latestVersion == "0.3.29")
        #expect(snapshot.assetSize == 4_096)
        #expect(snapshot.minimumOSLabel == "15.0")
        #expect(snapshot.releaseNotes.contains("安全更新体验"))
    }

    @Test
    func `low OS shows block reason and does not download`() async throws {
        let json = releaseJSON(
            tag: "v0.3.29",
            notes: "需要 Minimum macOS: 16.0",
            assets: [pkgAsset(version: "0.3.29")]
        )
        let latest = try await checker(json: json).fetchLatestMacRelease()
        let assessment = ManualUpdateEvaluator.assess(
            current: AppVersion(string: "0.3.28")!,
            latest: latest,
            runningOS: runningOS
        )
        guard case .unsupportedOS(_, _, let required, _) = assessment else {
            Issue.record("expected unsupportedOS, got \(assessment)")
            return
        }
        #expect(required.majorVersion == 16)
        #expect(!assessment.allowsDownload)

        let downloader = ReleaseDownloader(transport: FailingIfCalledTransport())
        var downloaded = false
        if assessment.allowsDownload {
            downloaded = true
            _ = try? await downloader.download(from: latest.downloadURL!)
        }
        #expect(!downloaded)
    }

    @Test
    func `missing asset shows error and falls back to release page`() async throws {
        let json = releaseJSON(
            tag: "v0.3.29",
            notes: "只有说明，没有安装包。\nmacOS 15.0",
            assets: [
                [
                    "name": "notes.txt",
                    "browser_download_url": "https://example.com/notes.txt",
                    "size": 12,
                ],
            ]
        )
        let latest = try await checker(json: json).fetchLatestMacRelease()
        let assessment = ManualUpdateEvaluator.assess(
            current: AppVersion(string: "0.3.28")!,
            latest: latest,
            runningOS: runningOS
        )
        #expect(!assessment.allowsDownload)
        #expect(assessment.shouldOpenReleasePage)
        #expect(latest.openURL.absoluteString.contains("/releases/tag/v0.3.29"))
        #expect(ReleaseDownloader.installerDownloadURL(from: latest) == nil)
    }

    @Test
    func `download timeout cleans temp file`() async throws {
        let transport = ScriptedReleaseDownloadTransport(behavior: .hang)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updates-timeout-\(UUID().uuidString)", isDirectory: true)
        let downloader = ReleaseDownloader(
            directory: dir,
            maxBytes: 1_024,
            timeout: 0.05,
            transport: transport
        )
        do {
            _ = try await downloader.download(from: URL(string: "https://example.com/SmartQuota-0.3.29.pkg")!)
            Issue.record("expected timeout")
        } catch let error as ManualUpdateError {
            #expect(error == .downloadTimeout)
        }
        #expect(remainingFiles(in: dir).isEmpty)
    }

    @Test
    func `cancel download cleans temp file`() async throws {
        let transport = ScriptedReleaseDownloadTransport(behavior: .hang)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updates-cancel-\(UUID().uuidString)", isDirectory: true)
        let downloader = ReleaseDownloader(
            directory: dir,
            maxBytes: 1_024,
            timeout: 5,
            transport: transport
        )
        async let download: URL = downloader.download(from: URL(string: "https://example.com/SmartQuota-0.3.29.pkg")!)
        try await Task.sleep(nanoseconds: 30_000_000)
        downloader.cancel()
        do {
            _ = try await download
            Issue.record("expected cancel")
        } catch let error as ManualUpdateError {
            #expect(error == .downloadCancelled)
        }
        #expect(remainingFiles(in: dir).isEmpty)
    }

    @Test
    func `install fail keeps current app launchable and does not claim update`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("updates-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = try writeFakeApp(in: root, name: "智额.app", version: "0.3.28")
        let missing = root.appendingPathComponent("missing.pkg")

        do {
            _ = try SilentPkgInstaller.scheduleReplace(
                pkgURL: missing,
                destinationApp: dest,
                currentVersion: AppVersion(string: "0.3.28")!
            )
            Issue.record("expected install failure")
        } catch let error as ManualUpdateError {
            guard case .install = error else {
                Issue.record("expected install error, got \(error)")
                return
            }
        }

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(InstalledAppVersion.read(fromAppBundle: dest)?.description == "0.3.28")
        #expect(SilentPkgInstaller.applyScriptLeavesCurrentAppUntilIncomingReady())
    }

    // MARK: - Helpers

    private func checker(json: Data) -> GitHubReleaseChecker {
        let client = MockNetworkClient()
        given(client)
            .request(.any)
            .willReturn((json, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/x/y/releases")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!))
        return GitHubReleaseChecker(networkClient: client)
    }

    private func releaseJSON(
        tag: String,
        notes: String,
        assets: [[String: Any]],
        published: String = "2026-08-14T00:00:00Z",
        prerelease: Bool = false
    ) -> Data {
        let payload: [[String: Any]] = [
            [
                "tag_name": tag,
                "html_url": "https://github.com/example/smartquota/releases/tag/\(tag)",
                "body": notes,
                "published_at": published,
                "draft": false,
                "prerelease": prerelease,
                "assets": assets,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func pkgAsset(version: String, size: Int = 2048) -> [String: Any] {
        [
            "name": "SmartQuota-\(version).pkg",
            "browser_download_url": "https://example.com/SmartQuota-\(version).pkg",
            "size": size,
            "digest": "sha256:\(String(repeating: "a", count: 64))",
        ]
    }

    private func remainingFiles(in directory: URL) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return en.compactMap { item in
            guard let url = item as? URL else { return nil }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return url.lastPathComponent
            }
            return nil
        }
    }

    private func writeFakeApp(in directory: URL, name: String, version: String) throws -> URL {
        let app = directory.appendingPathComponent(name, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleIdentifier": "com.smartquota.app",
        ]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}

private struct FailingIfCalledTransport: ReleaseDownloadTransport {
    func download(
        from request: URLRequest,
        to destination: URL,
        maxBytes: Int64,
        timeout: TimeInterval,
        onProgress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        throw ManualUpdateError.network("download should not start")
    }
}

private struct ScriptedReleaseDownloadTransport: ReleaseDownloadTransport {
    enum Behavior: Sendable {
        case hang
        case data(Data)
    }

    let behavior: Behavior

    func download(
        from request: URLRequest,
        to destination: URL,
        maxBytes: Int64,
        timeout: TimeInterval,
        onProgress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        switch behavior {
        case .hang:
            for _ in 0..<200 {
                if isCancelled() || Task.isCancelled { throw ManualUpdateError.downloadCancelled }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw ManualUpdateError.downloadTimeout
        case .data(let data):
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination)
            onProgress?(1)
        }
    }
}

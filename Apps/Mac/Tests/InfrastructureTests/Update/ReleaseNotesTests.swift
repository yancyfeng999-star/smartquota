import Testing
import Foundation
@testable import Domain

@Suite("Release notes and update eligibility")
struct ReleaseNotesTests {
    private let current = AppVersion(string: "0.3.28")!
    private let published = Date(timeIntervalSince1970: 1_786_694_400)

    @Test
    func `parses minimum macOS from release notes`() throws {
        let notes = """
        ## 系统
        macOS **15.2** 或更高。
        """
        let os = try #require(ReleaseMetadataParser.minimumOS(from: notes))
        #expect(os.majorVersion == 15)
        #expect(os.minorVersion == 2)
        #expect(os.patchVersion == 0)

        let minLabel = ReleaseMetadataParser.minimumOS(from: "Minimum macOS: 16.0")
        #expect(minLabel?.majorVersion == 16)
        #expect(ReleaseMetadataParser.minimumOS(from: "最低 macOS 版本：15")?.majorVersion == 15)
    }

    @Test
    func `parses sha256 from github digest and checksums file`() {
        #expect(
            ReleaseMetadataParser.sha256(fromGitHubDigest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
                == String(repeating: "a", count: 64)
        )
        let sums = """
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  SmartQuota-0.3.29.pkg
        cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  智额-0.3.29.dmg
        """
        #expect(
            ReleaseMetadataParser.sha256(fromChecksums: sums, matching: ["SmartQuota-0.3.29.pkg"])
                == String(repeating: "b", count: 64)
        )
        #expect(ReleaseMetadataParser.sha256(fromGitHubDigest: "md5:abc") == nil)
    }

    @Test
    func `snapshot shows current new date notes size and minimum OS`() {
        let latest = sampleRelease(
            version: "0.3.29",
            notes: "修复更新说明展示。\nmacOS 15.0 或更高。",
            size: 12_345_678,
            sha: String(repeating: "d", count: 64),
            minOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let assessment = ManualUpdateEvaluator.assess(
            current: current,
            latest: latest,
            runningOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
        )
        let snapshot = UpdateDetailsSnapshot.make(assessment: assessment)
        #expect(snapshot.currentVersion == "0.3.28")
        #expect(snapshot.latestVersion == "0.3.29")
        #expect(snapshot.publishedAt == published)
        #expect(snapshot.releaseNotes.contains("修复更新说明展示"))
        #expect(snapshot.assetSize == 12_345_678)
        #expect(snapshot.minimumOSLabel == "15.0")
        #expect(snapshot.allowsDownload)
        #expect(!snapshot.shouldOpenReleasePage)
    }

    @Test
    func `low OS and missing asset or checksum block download`() {
        let tooNewOS = sampleRelease(
            version: "0.3.29",
            minOS: OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        )
        let low = ManualUpdateEvaluator.assess(
            current: current,
            latest: tooNewOS,
            runningOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        #expect(!low.allowsDownload)
        guard case .unsupportedOS = low else {
            Issue.record("expected unsupportedOS")
            return
        }

        let noAsset = sampleRelease(version: "0.3.29", download: nil)
        let missingAsset = ManualUpdateEvaluator.assess(
            current: current,
            latest: noAsset,
            runningOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        #expect(!missingAsset.allowsDownload)
        #expect(missingAsset.shouldOpenReleasePage)

        let noSum = sampleRelease(version: "0.3.29", sha: nil)
        let missingSum = ManualUpdateEvaluator.assess(
            current: current,
            latest: noSum,
            runningOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        #expect(!missingSum.allowsDownload)
        #expect(missingSum.shouldOpenReleasePage)
    }

    @Test
    func `install guard rejects equal or older target and rereads bundle version`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-notes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = try writeFakeApp(in: dir, version: "0.3.28")
        #expect(throws: ManualUpdateError.targetNotNewer) {
            try UpdateInstallGuard.verifyExpandedApp(app, currentVersion: current)
        }

        let newer = try writeFakeApp(in: dir.appendingPathComponent("new", isDirectory: true), version: "0.3.29")
        let verified = try UpdateInstallGuard.verifyExpandedApp(newer, currentVersion: current)
        #expect(verified.description == "0.3.29")
        #expect(InstalledAppVersion.read(fromAppBundle: newer)?.description == "0.3.29")
    }

    private func sampleRelease(
        version: String,
        notes: String = "notes",
        size: Int64? = 100,
        sha: String? = String(repeating: "a", count: 64),
        minOS: OperatingSystemVersion? = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
        download: URL? = URL(string: "https://example.com/SmartQuota-0.3.29.pkg")
    ) -> RemoteRelease {
        RemoteRelease(
            version: AppVersion(string: version)!,
            tagName: "v\(version)",
            htmlURL: URL(string: "https://github.com/example/smartquota/releases/tag/v\(version)")!,
            downloadURL: download,
            releaseNotes: notes,
            publishedAt: published,
            minimumOS: minOS,
            assetSize: size,
            sha256: sha
        )
    }

    private func writeFakeApp(in directory: URL, version: String) throws -> URL {
        let app = directory.appendingPathComponent("智额.app", isDirectory: true)
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

import Testing
import Foundation
@testable import Domain

@Suite("AppVersion / ManualUpdate")
struct AppVersionTests {
    @Test
    func `parses common tag shapes`() {
        #expect(AppVersion(string: "0.3.4")?.description == "0.3.4")
        #expect(AppVersion(string: "v0.3.4")?.description == "0.3.4")
        #expect(AppVersion(string: "mac-v0.3.4")?.description == "0.3.4")
        #expect(AppVersion(string: "mac-0.3.4")?.description == "0.3.4")
        #expect(AppVersion(string: "v1.2")?.description == "1.2.0")
    }

    @Test
    func `rejects windows tags and junk`() {
        #expect(AppVersion(string: "windows-v0.1.0") == nil)
        #expect(AppVersion(string: "") == nil)
        #expect(AppVersion(string: "not-a-version") == nil)
    }

    @Test
    func `compares versions correctly`() {
        let a = AppVersion(string: "0.3.3")!
        let b = AppVersion(string: "0.3.4")!
        let c = AppVersion(string: "1.0.0")!
        #expect(a < b)
        #expect(b < c)
        #expect(!(b < a))
        #expect(a == AppVersion(string: "v0.3.3"))
    }

    @Test
    func `classifies mac vs windows candidates`() {
        #expect(ReleaseTagClassifier.isWindowsTag("windows-v0.1.0"))
        #expect(
            ReleaseTagClassifier.isMacCandidate(
                tag: "v0.3.2",
                assetNames: ["SmartQuota-0.3.2.dmg"]
            )
        )
        #expect(
            !ReleaseTagClassifier.isMacCandidate(
                tag: "windows-v0.1.0",
                assetNames: ["SmartQuota-Setup-0.1.0-x64.exe"]
            )
        )
    }

    @Test
    func `evaluate detects newer release`() {
        let current = AppVersion(string: "0.3.3")!
        let latest = RemoteRelease(
            version: AppVersion(string: "0.3.4")!,
            tagName: "v0.3.4",
            htmlURL: URL(string: "https://example.com/r")!,
            downloadURL: URL(string: "https://example.com/a.dmg")!
        )
        let result = ManualUpdateEvaluator.evaluate(current: current, latest: latest)
        guard case .updateAvailable(let cur, let rel) = result else {
            Issue.record("expected updateAvailable")
            return
        }
        #expect(cur == current)
        #expect(rel.version.description == "0.3.4")
    }

    @Test
    func `evaluate up to date when equal or older remote`() {
        let current = AppVersion(string: "0.3.4")!
        let latest = RemoteRelease(
            version: AppVersion(string: "0.3.4")!,
            tagName: "v0.3.4",
            htmlURL: URL(string: "https://example.com/r")!,
            downloadURL: nil
        )
        #expect(ManualUpdateEvaluator.evaluate(current: current, latest: latest) == .upToDate(current: current))
    }

    @Test
    func `prefers smartquota pkg over dmg and other installers`() {
        let urls = [
            (name: "SmartQuota-0.3.4.dmg", url: URL(string: "https://x/b.dmg")!),
            (name: "智额-0.3.4.pkg", url: URL(string: "https://x/a.pkg")!),
            (name: "SmartQuota-0.3.4.pkg", url: URL(string: "https://x/c.pkg")!),
            (name: "notes.txt", url: URL(string: "https://x/n.txt")!),
        ]
        let preferred = ManualUpdateEvaluator.preferredDownloadURL(assetNamesAndURLs: urls)
        #expect(preferred?.absoluteString == "https://x/c.pkg")
    }

    @Test
    func `prefers any pkg when no smartquota pkg`() {
        let urls = [
            (name: "智额-0.3.4.dmg", url: URL(string: "https://x/b.dmg")!),
            (name: "智额-0.3.4.pkg", url: URL(string: "https://x/a.pkg")!),
        ]
        let preferred = ManualUpdateEvaluator.preferredDownloadURL(assetNamesAndURLs: urls)
        #expect(preferred?.absoluteString == "https://x/a.pkg")
    }

    @Test
    func `pickLatest chooses highest version`() {
        let r1 = RemoteRelease(
            version: AppVersion(string: "0.3.1")!,
            tagName: "v0.3.1",
            htmlURL: URL(string: "https://x/1")!,
            downloadURL: nil
        )
        let r2 = RemoteRelease(
            version: AppVersion(string: "0.3.3")!,
            tagName: "v0.3.3",
            htmlURL: URL(string: "https://x/3")!,
            downloadURL: nil
        )
        #expect(ManualUpdateEvaluator.pickLatest([r1, r2])?.version.description == "0.3.3")
    }
}

import Foundation
import Domain

/// Downloads a GitHub release installer (dmg/pkg) to the user's Downloads folder.
/// Reports 0…1 progress via callback. Free path — not silent install.
public final class ReleaseDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destinationFileName: String = "SmartQuota-update.dmg"
    private var session: URLSession?

    public override init() {
        super.init()
    }

    /// Downloads `url` into `~/Downloads/<fileName>` (overwrites same name).
    /// - Parameter onProgress: fraction 0…1 (best-effort when Content-Length known).
    public func download(
        from url: URL,
        fileName: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw ManualUpdateError.network("Invalid download URL")
        }

        destinationFileName = Self.safeFileName(fileName ?? url.lastPathComponent)
        progressHandler = onProgress

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("SmartQuota (release-download)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            progressHandler?(fraction)
        } else if totalBytesWritten > 0 {
            // Unknown size: show indeterminate-ish pulse via capped growth
            let fake = min(0.95, Double(totalBytesWritten) / (12 * 1024 * 1024))
            progressHandler?(fake)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let name = destinationFileName
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dest = downloads.appendingPathComponent(name, isDirectory: false)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            // location is temporary — must copy/move before this method returns
            try fm.copyItem(at: location, to: dest)
            progressHandler?(1)
            let cont = continuation
            continuation = nil
            cont?.resume(returning: dest)
        } catch {
            let cont = continuation
            continuation = nil
            cont?.resume(throwing: ManualUpdateError.network(error.localizedDescription))
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            let cont = continuation
            continuation = nil
            cont?.resume(throwing: ManualUpdateError.network(error.localizedDescription))
        }
        // Invalidate when done
        session.finishTasksAndInvalidate()
        self.session = nil
    }

    /// Prefer a direct installer asset URL; otherwise nil (caller may open the release page).
    public static func installerDownloadURL(from release: RemoteRelease) -> URL? {
        if let d = release.downloadURL {
            let path = d.path.lowercased()
            if path.hasSuffix(".dmg") || path.hasSuffix(".pkg") || path.hasSuffix(".zip") {
                return d
            }
        }
        let open = release.openURL
        let path = open.path.lowercased()
        if path.hasSuffix(".dmg") || path.hasSuffix(".pkg") || path.hasSuffix(".zip") {
            return open
        }
        return nil
    }

    private static func safeFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "SmartQuota-update.dmg" }
        let base = (trimmed as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") })
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "SmartQuota-update.dmg"
        }
        return cleaned
    }
}

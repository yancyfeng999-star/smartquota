import CryptoKit
import Foundation
import os
import Domain

/// Streams an installer to a temporary file with a size cap, timeout, cancel, and cleanup.
public protocol ReleaseDownloadTransport: Sendable {
    func download(
        from request: URLRequest,
        to destination: URL,
        maxBytes: Int64,
        timeout: TimeInterval,
        onProgress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws
}

/// Downloads a GitHub release installer (prefer `.pkg`) into a temp directory.
/// Reports 0…1 progress via callback. Installation is handled separately by `SilentPkgInstaller`.
public final class ReleaseDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let defaultMaxBytes = ReleaseDownloadPolicy.maxBytes
    public static let defaultTimeout = ReleaseDownloadPolicy.timeout

    private let fileManager: FileManager
    private let directory: URL
    private let maxBytes: Int64
    private let timeout: TimeInterval
    private let transport: (any ReleaseDownloadTransport)?

    private struct SessionState {
        var cancelled = false
        var aborted = false
        var progressHandler: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<URL, Error>?
        var destinationURL: URL?
        var session: URLSession?
        var downloadTask: URLSessionDownloadTask?
    }

    private let state = OSAllocatedUnfairLock(initialState: SessionState())

    public init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        maxBytes: Int64 = ReleaseDownloader.defaultMaxBytes,
        timeout: TimeInterval = ReleaseDownloader.defaultTimeout,
        transport: (any ReleaseDownloadTransport)? = nil
    ) {
        self.fileManager = fileManager
        self.directory = directory
            ?? fileManager.temporaryDirectory.appendingPathComponent("smartquota-downloads", isDirectory: true)
        self.maxBytes = maxBytes
        self.timeout = timeout
        self.transport = transport
        super.init()
    }

    public func cancel() {
        abortInFlight(with: .downloadCancelled)
    }

    /// True while a live `URLSession` download is still registered.
    var hasActiveSession: Bool {
        state.withLock { $0.session != nil || $0.downloadTask != nil }
    }

    /// Downloads `url` into a unique temp file. Cleans up on timeout, cancel, or failure.
    public func download(
        from url: URL,
        fileName: String? = nil,
        expectedSize: Int64? = nil,
        expectedSHA256: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw ManualUpdateError.network("Invalid download URL")
        }
        if let expectedSize, expectedSize > maxBytes {
            throw ManualUpdateError.downloadTooLarge(maxBytes: maxBytes)
        }

        state.withLock { current in
            current.cancelled = false
            current.aborted = false
        }

        let work = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            throw ManualUpdateError.network(error.localizedDescription)
        }
        let dest = work.appendingPathComponent(Self.safeFileName(fileName ?? url.lastPathComponent), isDirectory: false)

        do {
            try await downloadWithTimeout(
                from: url,
                to: dest,
                onProgress: onProgress
            )
            if isCancelled || isAborted {
                throw isCancelled ? ManualUpdateError.downloadCancelled : ManualUpdateError.downloadTimeout
            }
            let size = try fileSize(at: dest)
            if size > maxBytes {
                throw ManualUpdateError.downloadTooLarge(maxBytes: maxBytes)
            }
            if let expectedSize, size != expectedSize {
                throw ManualUpdateError.checksumMismatch
            }
            if let expectedSHA256 {
                let digest = try Self.sha256Hex(of: dest)
                if digest != expectedSHA256.lowercased() {
                    throw ManualUpdateError.checksumMismatch
                }
            }
            onProgress?(1)
            return dest
        } catch {
            try? fileManager.removeItem(at: work)
            if let update = error as? ManualUpdateError {
                switch update {
                case .downloadTimeout, .downloadCancelled, .downloadTooLarge, .checksumMismatch:
                    throw update
                default:
                    break
                }
            }
            if isCancelled {
                throw ManualUpdateError.downloadCancelled
            }
            throw mapDownloadError(error)
        }
    }

    public func download(
        release: RemoteRelease,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let url = Self.installerDownloadURL(from: release) else {
            throw ManualUpdateError.missingReleaseAsset
        }
        let checksum = release.sha256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard ReleaseMetadataParser.isSHA256Hex(checksum) else {
            throw ManualUpdateError.missingChecksum
        }
        return try await download(
            from: url,
            fileName: url.lastPathComponent,
            expectedSize: release.assetSize,
            expectedSHA256: checksum,
            onProgress: onProgress
        )
    }

    /// Prefer a direct installer asset URL; otherwise nil (caller may open the release page).
    public static func installerDownloadURL(from release: RemoteRelease) -> URL? {
        ManualUpdateEvaluator.preferredInstallerURL(from: release)
    }

    // MARK: - Private

    private var isCancelled: Bool {
        state.withLock { $0.cancelled }
    }

    private var isAborted: Bool {
        state.withLock { $0.aborted }
    }

    /// Cancel the in-flight URLSession (not only a sleeper task) and drop the dest so a late finish cannot copy.
    private func abortInFlight(with error: ManualUpdateError) {
        let snapshot = state.withLock { current -> (URLSession?, URLSessionDownloadTask?, CheckedContinuation<URL, Error>?) in
            current.aborted = true
            if error == .downloadCancelled {
                current.cancelled = true
            }
            current.destinationURL = nil
            current.progressHandler = nil
            let session = current.session
            let task = current.downloadTask
            let cont = current.continuation
            current.session = nil
            current.downloadTask = nil
            current.continuation = nil
            return (session, task, cont)
        }
        snapshot.1?.cancel()
        snapshot.0?.invalidateAndCancel()
        snapshot.2?.resume(throwing: error)
    }

    private func downloadWithTimeout(
        from url: URL,
        to dest: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.performDownload(from: url, to: dest, onProgress: onProgress)
            }
            group.addTask {
                let nanos = UInt64(max(self.timeout, 0.01) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                try Task.checkCancellation()
                self.abortInFlight(with: .downloadTimeout)
                throw ManualUpdateError.downloadTimeout
            }
            do {
                try await group.next()
            } catch {
                group.cancelAll()
                throw error
            }
            group.cancelAll()
        }
    }

    private func performDownload(
        from url: URL,
        to dest: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("SmartQuota (release-download)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        if let transport {
            try await transport.download(
                from: request,
                to: dest,
                maxBytes: maxBytes,
                timeout: timeout,
                onProgress: onProgress,
                isCancelled: { [weak self] in self?.isCancelled ?? false }
            )
            return
        }

        try await downloadViaURLSession(request: request, destination: dest, onProgress: onProgress)
    }

    private func downloadViaURLSession(
        request: URLRequest,
        destination: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = timeout
            // Resource timeout is a backstop; the sleeper must invalidate the session itself.
            config.timeoutIntervalForResource = timeout + 30
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: request)
            let shouldStart = state.withLock { current -> ManualUpdateError? in
                if current.aborted {
                    return current.cancelled ? .downloadCancelled : .downloadTimeout
                }
                current.continuation = cont
                current.progressHandler = onProgress
                current.destinationURL = destination
                current.session = session
                current.downloadTask = task
                return nil
            }
            if let error = shouldStart {
                task.cancel()
                session.invalidateAndCancel()
                cont.resume(throwing: error)
                return
            }
            task.resume()
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func mapDownloadError(_ error: Error) -> ManualUpdateError {
        if let update = error as? ManualUpdateError {
            return update
        }
        if let url = error as? URLError {
            if url.code == .timedOut { return .downloadTimeout }
            if url.code == .cancelled { return .downloadCancelled }
            return .network(url.localizedDescription)
        }
        return .network(error.localizedDescription)
    }

    static func sha256Hex(of url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func safeFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "SmartQuota-update.pkg" }
        let base = (trimmed as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") })
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "SmartQuota-update.pkg"
        }
        return cleaned
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > maxBytes || totalBytesWritten > maxBytes {
            downloadTask.cancel()
            finish(.failure(ManualUpdateError.downloadTooLarge(maxBytes: maxBytes)))
            return
        }
        if isCancelled || isAborted {
            downloadTask.cancel()
            finish(.failure(isCancelled ? ManualUpdateError.downloadCancelled : ManualUpdateError.downloadTimeout))
            return
        }
        let handler = state.withLock { $0.progressHandler }
        if totalBytesExpectedToWrite > 0 {
            let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            handler?(fraction)
        } else if totalBytesWritten > 0 {
            let fake = min(0.95, Double(totalBytesWritten) / Double(max(maxBytes, 1)))
            handler?(fake)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = state.withLock { current -> URL? in
            if current.aborted { return nil }
            return current.destinationURL
        }
        guard let dest else { return }
        do {
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: location, to: dest)
            let keep = state.withLock { current in
                !current.aborted && current.destinationURL == dest
            }
            if !keep {
                try? fileManager.removeItem(at: dest)
                return
            }
            state.withLock { $0.progressHandler }?(1)
            finish(.success(dest))
        } catch {
            finish(.failure(ManualUpdateError.network(error.localizedDescription)))
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error, !isAborted {
            finish(.failure(mapDownloadError(error)))
        }
        if !isAborted {
            session.finishTasksAndInvalidate()
        }
        state.withLock { current in
            if current.session === session {
                current.session = nil
            }
            current.downloadTask = nil
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let cont = state.withLock { current -> CheckedContinuation<URL, Error>? in
            if current.aborted, case .success = result {
                return nil
            }
            let pending = current.continuation
            current.continuation = nil
            return pending
        }
        switch result {
        case .success(let url):
            cont?.resume(returning: url)
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }
}

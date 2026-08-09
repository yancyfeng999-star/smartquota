import Foundation
import Domain

/// Installs a local `.pkg` **without** opening Installer.app (no wizard UI).
///
/// Strategy:
/// 1. Expand the package with `pkgutil --expand-full`
/// 2. Locate the embedded `.app`
/// 3. Replace the running app bundle (or `/Applications/<name>.app`) via `ditto`
/// 4. Hand off to a short shell script that waits for this process to exit, then relaunches
///
/// If the destination is not writable, falls back to `/usr/sbin/installer -pkg … -target /`
/// via a one-shot admin shell (may show the **system** password sheet — not an app dialog).
public enum SilentPkgInstaller: Sendable {

    public struct Result: Sendable, Equatable {
        public let installedAppURL: URL
        public let usedAdminInstaller: Bool
    }

    /// Install `pkgURL` and schedule relaunch of the app after this process quits.
    @MainActor
    public static func installAndRelaunch(pkgURL: URL) async throws -> Result {
        guard pkgURL.pathExtension.lowercased() == "pkg" else {
            throw ManualUpdateError.install("Not a .pkg file")
        }
        guard FileManager.default.fileExists(atPath: pkgURL.path) else {
            throw ManualUpdateError.install("Package not found")
        }

        let fm = FileManager.default
        let expandRoot = fm.temporaryDirectory
            .appendingPathComponent("SmartQuota-pkg-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? fm.removeItem(at: expandRoot)
        }

        try runProcess(
            "/usr/sbin/pkgutil",
            arguments: ["--expand-full", pkgURL.path, expandRoot.path]
        )

        guard let embeddedApp = findAppBundle(under: expandRoot) else {
            throw ManualUpdateError.install("No .app inside package")
        }

        let destination = preferredInstallDestination(forEmbeddedAppName: embeddedApp.lastPathComponent)
        var usedAdmin = false

        let parentWritable = canWrite(toDirectory: destination.deletingLastPathComponent())
        let canUserReplace = canWrite(toAppBundle: destination)
            || (!fm.fileExists(atPath: destination.path) && parentWritable)

        if canUserReplace {
            try replaceApp(from: embeddedApp, to: destination)
        } else {
            // Needs elevation for /Applications (or locked bundle)
            try runInstallerAsAdmin(pkgURL: pkgURL)
            usedAdmin = true
        }

        try scheduleRelaunch(appURL: destination, afterPid: ProcessInfo.processInfo.processIdentifier)
        return Result(installedAppURL: destination, usedAdminInstaller: usedAdmin)
    }

    // MARK: - Destination

    /// Prefer replacing the running bundle when installed under Applications; otherwise `/Applications/<name>.app`.
    private static func preferredInstallDestination(forEmbeddedAppName appName: String) -> URL {
        let applications = URL(fileURLWithPath: "/Applications/\(appName)", isDirectory: true)
        let running = Bundle.main.bundleURL
        guard running.pathExtension == "app" else { return applications }

        let path = running.path
        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications") + "/"
        // Replace in place when the user is running a “real” install (not DerivedData / random folder).
        if path.hasPrefix("/Applications/")
            || path.hasPrefix(homeApps)
            || path.contains("/Desktop/")
            || path.hasSuffix("/\(appName)") {
            return running
        }
        return applications
    }

    private static func canWrite(toAppBundle url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return fm.isWritableFile(atPath: url.path)
        }
        return canWrite(toDirectory: url.deletingLastPathComponent())
    }

    private static func canWrite(toDirectory url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    // MARK: - Expand / copy

    private static func findAppBundle(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var found: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        // Prefer top-level-ish apps; pick shortest path (closest to expand root)
        return found.min(by: { $0.path.count < $1.path.count })
    }

    private static func replaceApp(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        // Stage next to destination, then swap — safer while the old app is still running.
        let staging = parent.appendingPathComponent(
            destination.deletingPathExtension().lastPathComponent + ".smartquota-update.app",
            isDirectory: true
        )
        if fm.fileExists(atPath: staging.path) {
            try fm.removeItem(at: staging)
        }
        try runProcess(
            "/usr/bin/ditto",
            arguments: ["--norsrc", "--noextattr", source.path, staging.path]
        )

        let backup = parent.appendingPathComponent(
            destination.deletingPathExtension().lastPathComponent + ".smartquota-backup.app",
            isDirectory: true
        )
        if fm.fileExists(atPath: backup.path) {
            try? fm.removeItem(at: backup)
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: destination, to: backup)
        }
        do {
            try fm.moveItem(at: staging, to: destination)
        } catch {
            // Roll back
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: destination)
            }
            try? fm.removeItem(at: staging)
            throw ManualUpdateError.install(error.localizedDescription)
        }
        try? fm.removeItem(at: backup)

        // Clear quarantine on the replaced app so Gatekeeper is less noisy on relaunch.
        _ = try? runProcess(
            "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", destination.path]
        )
    }

    // MARK: - Admin installer fallback (no Installer.app UI)

    private static func runInstallerAsAdmin(pkgURL: URL) throws {
        // `installer` has no GUI; only the system auth sheet may appear for admin rights.
        let pkg = shellEscape(pkgURL.path)
        let appleScript = """
        do shell script "/usr/sbin/installer -pkg \(pkg) -target /" with administrator privileges
        """
        try runProcess("/usr/bin/osascript", arguments: ["-e", appleScript])
    }

    // MARK: - Relaunch after quit

    /// Detached script: wait until `pid` exits, then `open` the installed app.
    private static func scheduleRelaunch(appURL: URL, afterPid pid: Int32) throws {
        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory
            .appendingPathComponent("smartquota-relaunch-\(pid).sh")
        let appPath = appURL.path
        let body = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.4
        /usr/bin/open \(shellEscape(appPath))
        rm -f "$0"
        """
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Detach so relaunch survives our termination
        process.qualityOfService = .userInitiated
        try process.run()
    }

    // MARK: - Process helpers

    @discardableResult
    private static func runProcess(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw ManualUpdateError.install(error.localizedDescription)
        }
        process.waitUntilExit()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let outText = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = errText.isEmpty ? outText : errText
            throw ManualUpdateError.install(detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }
        return outText
    }

    private static func shellEscape(_ path: String) -> String {
        // Single-quote for AppleScript / bash safety
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

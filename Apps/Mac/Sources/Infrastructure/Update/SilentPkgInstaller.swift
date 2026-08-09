import Foundation
import Domain

/// User-level silent update — **no Installer.app, no admin password sheet**.
///
/// Matches the SmartBalance / 智余 model:
/// 1. `pkgutil --expand-full` → find embedded `.app`
/// 2. Verify destination is **writable by the current user** (else fail with message)
/// 3. Write `apply.sh` + `nohup` it so it outlives this process
/// 4. Caller quits; script waits for our PID, then replaces the app and reopens
///
/// Never calls `installer` / `osascript … administrator privileges`.
public enum SilentPkgInstaller: Sendable {

    public struct Result: Sendable, Equatable {
        public let installedAppURL: URL
        public let workDirectory: URL
    }

    private static let logRelativePath = "Library/Logs/SmartQuota/update.log"

    /// Expand pkg, stage apply script, return. Caller should then `NSApp.terminate`.
    @MainActor
    public static func installAndRelaunch(pkgURL: URL) async throws -> Result {
        guard pkgURL.pathExtension.lowercased() == "pkg" else {
            throw ManualUpdateError.install("Not a .pkg file")
        }
        guard FileManager.default.fileExists(atPath: pkgURL.path) else {
            throw ManualUpdateError.install("Package not found")
        }

        let fm = FileManager.default
        // Persist until apply.sh finishes (do NOT delete here).
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("SmartQuota-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        log("begin expand pkg=\(pkgURL.path) work=\(workDir.path)")

        let expandRoot = workDir.appendingPathComponent("expanded", isDirectory: true)
        do {
            try runProcess(
                "/usr/sbin/pkgutil",
                arguments: ["--expand-full", pkgURL.path, expandRoot.path]
            )
        } catch {
            try? fm.removeItem(at: workDir)
            throw error
        }

        guard let embeddedApp = findAppBundle(under: expandRoot) else {
            try? fm.removeItem(at: workDir)
            throw ManualUpdateError.install("No .app inside package")
        }

        let destination = preferredInstallDestination(forEmbeddedAppName: embeddedApp.lastPathComponent)
        log("embedded=\(embeddedApp.path) dest=\(destination.path)")

        guard isUserWritableInstallLocation(destination) else {
            try? fm.removeItem(at: workDir)
            let msg = """
            无法写入 \(destination.path)（当前用户无写权限）。\
            请将智额装到「应用程序」且由本用户安装后再更新；\
            不会请求管理员密码。
            """
            log("not writable: \(destination.path)")
            throw ManualUpdateError.install(msg)
        }

        // Stage a clean copy under workDir so expand tree can stay intact / simpler paths in script
        let stagedApp = workDir.appendingPathComponent(embeddedApp.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: stagedApp.path) {
            try fm.removeItem(at: stagedApp)
        }
        try runProcess(
            "/usr/bin/ditto",
            arguments: ["--norsrc", "--noextattr", embeddedApp.path, stagedApp.path]
        )

        let pid = ProcessInfo.processInfo.processIdentifier
        try writeAndSpawnApplyScript(
            workDir: workDir,
            stagedApp: stagedApp,
            destination: destination,
            afterPid: pid
        )

        log("apply.sh spawned; waiting for app quit pid=\(pid)")
        return Result(installedAppURL: destination, workDirectory: workDir)
    }

    // MARK: - Destination / writability

    /// Prefer the running bundle when it is a real `.app`; else `/Applications/<name>.app`.
    private static func preferredInstallDestination(forEmbeddedAppName appName: String) -> URL {
        let applications = URL(fileURLWithPath: "/Applications/\(appName)", isDirectory: true)
        let running = Bundle.main.bundleURL
        guard running.pathExtension.lowercased() == "app" else { return applications }

        let path = running.path
        // DerivedData / random build folders → still target Applications (real install).
        if path.contains("/DerivedData/")
            || path.contains("/.build/")
            || path.contains("/Build/Products/") {
            return applications
        }
        return running
    }

    /// True if we can replace/create the app as the **current user** (no elevation).
    private static func isUserWritableInstallLocation(_ destination: URL) -> Bool {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()

        if fm.fileExists(atPath: destination.path) {
            // Existing bundle: need write on the bundle (or ability to rename it away).
            if fm.isWritableFile(atPath: destination.path) { return true }
            // Sometimes the bundle root reports non-writable while parent allows rename.
            return fm.isWritableFile(atPath: parent.path) && canCreateProbeFile(in: parent)
        }

        // New install path
        return canCreateProbeFile(in: parent)
    }

    private static func canCreateProbeFile(in directory: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            // Do not create /Applications ourselves without rights
            return fm.isWritableFile(atPath: directory.path)
        }
        guard fm.isWritableFile(atPath: directory.path) else { return false }
        let probe = directory.appendingPathComponent(".smartquota-write-probe-\(UUID().uuidString)")
        let ok = fm.createFile(atPath: probe.path, contents: Data(), attributes: nil)
        if ok { try? fm.removeItem(at: probe) }
        return ok
    }

    // MARK: - Expand helpers

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
        return found.min(by: { $0.path.count < $1.path.count })
    }

    // MARK: - apply.sh (post-quit replace)

    private static func writeAndSpawnApplyScript(
        workDir: URL,
        stagedApp: URL,
        destination: URL,
        afterPid pid: Int32
    ) throws {
        let fm = FileManager.default
        let scriptURL = workDir.appendingPathComponent("apply.sh")
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent(logRelativePath)
        let logDir = (logPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let dest = destination.path
        let src = stagedApp.path
        let preupdate = destination.deletingPathExtension().path + ".preupdate.app"
        let work = workDir.path

        // shell-escaped literals
        let eDest = shellEscape(dest)
        let eSrc = shellEscape(src)
        let ePre = shellEscape(preupdate)
        let eWork = shellEscape(work)
        let eLog = shellEscape(logPath)

        let body = """
        #!/bin/bash
        set +e
        LOG=\(eLog)
        log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }
        log "apply.sh start pid_wait=\(pid) src=\(src) dest=\(dest)"

        # 1) Wait until old app process exits
        while kill -0 \(pid) 2>/dev/null; do
          sleep 0.2
        done
        sleep 0.6
        log "old process exited"

        # 2) Move old app aside
        if [ -d \(eDest) ]; then
          rm -rf \(ePre)
          mv \(eDest) \(ePre) || {
            log "ERROR: cannot move old app"
            exit 1
          }
        fi

        # 3) Install new app
        /usr/bin/ditto --norsrc --noextattr \(eSrc) \(eDest) || {
          log "ERROR: ditto failed; restore preupdate if any"
          if [ -d \(ePre) ]; then mv \(ePre) \(eDest); fi
          exit 1
        }

        # 4) Clear quarantine
        /usr/bin/xattr -dr com.apple.quarantine \(eDest) 2>/dev/null || true

        # 5) Remove backup
        rm -rf \(ePre)

        # 6) Relaunch
        /usr/bin/open \(eDest)
        log "opened new app"

        # 7) Cleanup work dir
        rm -rf \(eWork)
        log "done"
        """

        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // nohup so script survives parent termination
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/bash", scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        do {
            try process.run()
        } catch {
            throw ManualUpdateError.install("Failed to start apply script: \(error.localizedDescription)")
        }
        // Do not wait — script runs after we quit
    }

    // MARK: - Process / log

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
            log("process failed \(launchPath) \(arguments) → \(detail)")
            throw ManualUpdateError.install(detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }
        return outText
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func log(_ message: String) {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(logRelativePath)
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

import Foundation
import Domain

/// 下载后的 .pkg 静默安装：解包 → 退出后 ditto 覆盖当前 App → 自动重新打开。
/// 对齐智余 `PackageSilentInstaller`：不弹 Installer、不弹确认框、**不索要管理员密码**。
/// 需要当前安装目录可写（本机 ad-hoc / 用户自己拖进应用程序 通常可写）。
public enum SilentPkgInstaller: Sendable {

    /// 解包 pkg，调度替换脚本后立即返回；调用方应随后 `NSApp.terminate`。
    /// Does not claim the running bundle is already the new version.
    @MainActor
    public static func installAndRelaunch(
        pkgURL: URL,
        currentVersion: AppVersion,
        destinationApp: URL? = nil
    ) async throws -> Result {
        let dest = destinationApp ?? preferredDestination()
        let incoming = try scheduleReplace(
            pkgURL: pkgURL,
            destinationApp: dest,
            currentVersion: currentVersion
        )
        return Result(
            installedAppURL: dest,
            incomingVersion: incoming,
            previousVersion: currentVersion
        )
    }

    public struct Result: Sendable, Equatable {
        public let installedAppURL: URL
        public let incomingVersion: AppVersion
        public let previousVersion: AppVersion
    }

    /// Expand, verify the incoming bundle is newer, then schedule replace-after-quit.
    /// On any failure the current `destinationApp` is left untouched.
    @discardableResult
    public static func scheduleReplace(
        pkgURL: URL,
        destinationApp: URL,
        currentVersion: AppVersion
    ) throws -> AppVersion {
        guard pkgURL.pathExtension.lowercased() == "pkg" else {
            throw ManualUpdateError.install("Not a .pkg file")
        }
        guard FileManager.default.fileExists(atPath: pkgURL.path) else {
            throw ManualUpdateError.install("Package not found")
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("smartquota-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let expanded = work.appendingPathComponent("expanded", isDirectory: true)
        do {
            try runPkgUtilExpand(pkg: pkgURL, to: expanded)
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }

        guard let newApp = findAppBundle(in: expanded) else {
            try? fm.removeItem(at: work)
            throw ManualUpdateError.install("安装包内未找到 App")
        }

        let incomingVersion: AppVersion
        do {
            incomingVersion = try UpdateInstallGuard.verifyExpandedApp(newApp, currentVersion: currentVersion)
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }

        let destDir = destinationApp.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: destDir.path) || fm.isWritableFile(atPath: destinationApp.path) else {
            try? fm.removeItem(at: work)
            throw ManualUpdateError.install(
                "无法写入 \(destinationApp.path)（请确认智额装在「应用程序」且当前用户可写；不会请求管理员密码）"
            )
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = work.appendingPathComponent("apply.sh")
        let logURL = (fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory)
            .appendingPathComponent("Logs/SmartQuota", isDirectory: true)
        try? fm.createDirectory(at: logURL, withIntermediateDirectories: true)
        let logFile = logURL.appendingPathComponent("update.log")

        let script = makeApplyScript(
            newApp: newApp,
            destinationApp: destinationApp,
            work: work,
            logFile: logFile,
            pid: pid
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // 后台子 shell，父进程退出后仍继续（与智余一致）
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", "nohup \(shellEscape(scriptURL.path)) >/dev/null 2>&1 &"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            try? fm.removeItem(at: work)
            throw ManualUpdateError.install("Failed to start apply script: \(error.localizedDescription)")
        }
        appendLog("Silent PKG install scheduled \(currentVersion) → \(incomingVersion) at \(destinationApp.path)")
        return incomingVersion
    }

    /// Incoming copy is created first; the live app is only moved after that copy exists.
    public static func applyScriptLeavesCurrentAppUntilIncomingReady() -> Bool {
        let script = makeApplyScript(
            newApp: URL(fileURLWithPath: "/tmp/new.app"),
            destinationApp: URL(fileURLWithPath: "/tmp/智额.app"),
            work: URL(fileURLWithPath: "/tmp/work"),
            logFile: URL(fileURLWithPath: "/tmp/update.log"),
            pid: 1
        )
        let copiesIncomingFirst = script.contains("${DEST}.incoming") && script.contains("ditto")
        let parksCurrent = script.contains("mv \"$DEST\" \"$PRE\"")
        let noBlindDelete = !script.contains("|| rm -rf \"$DEST\"")
        return copiesIncomingFirst && parksCurrent && noBlindDelete
    }

    static func makeApplyScript(
        newApp: URL,
        destinationApp: URL,
        work: URL,
        logFile: URL,
        pid: Int32
    ) -> String {
        """
        #!/bin/bash
        set -e
        NEW=\(shellEscape(newApp.path))
        DEST=\(shellEscape(destinationApp.path))
        WORK=\(shellEscape(work.path))
        LOG=\(shellEscape(logFile.path))
        PID=\(pid)
        INCOMING="${DEST}.incoming"
        PRE="${DEST}.preupdate"
        {
          echo "$(date '+%Y-%m-%d %H:%M:%S') update start pid=$PID"
          for i in $(seq 1 100); do
            if ! kill -0 "$PID" 2>/dev/null; then
              break
            fi
            sleep 0.2
          done
          sleep 0.6
          if [ ! -d "$NEW" ]; then
            echo "missing new app: $NEW"
            exit 1
          fi
          rm -rf "$INCOMING"
          /usr/bin/ditto --norsrc --noextattr --noqtn "$NEW" "$INCOMING"
          if [ ! -d "$INCOMING" ]; then
            echo "incoming copy failed"
            exit 1
          fi
          rm -rf "$PRE"
          if [ -e "$DEST" ]; then
            if ! mv "$DEST" "$PRE"; then
              echo "could not park current app"
              rm -rf "$INCOMING"
              exit 1
            fi
          fi
          if ! mv "$INCOMING" "$DEST"; then
            echo "swap failed, restoring"
            if [ -e "$PRE" ]; then
              mv "$PRE" "$DEST" || true
            fi
            exit 1
          fi
          if [ ! -d "$DEST" ]; then
            echo "dest missing after swap, restoring"
            if [ -e "$PRE" ]; then
              mv "$PRE" "$DEST" || true
            fi
            exit 1
          fi
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
          rm -rf "$PRE"
          /usr/bin/open "$DEST"
          echo "update ok → $DEST"
          rm -rf "$WORK"
        } >>"$LOG" 2>&1
        """
    }

    // MARK: - Destination

    /// 运行中的 .app（跳过 DerivedData 构建产物，改写到 /Applications）。
    private static func preferredDestination() -> URL {
        let running = Bundle.main.bundleURL
        if running.pathExtension.lowercased() == "app" {
            let p = running.path
            if p.contains("/DerivedData/") || p.contains("/.build/") || p.contains("/Build/Products/") {
                return URL(fileURLWithPath: "/Applications/智额.app", isDirectory: true)
            }
            return running
        }
        return URL(fileURLWithPath: "/Applications/智额.app", isDirectory: true)
    }

    // MARK: - Expand（含智余同款 fallback）

    private static func runPkgUtilExpand(pkg: URL, to dir: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        p.arguments = ["--expand-full", pkg.path, dir.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            throw ManualUpdateError.install("解包失败：\(error.localizedDescription)")
        }
        if p.terminationStatus == 0 { return }

        // 回退：--expand + 手动解 Payload
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        p2.arguments = ["--expand", pkg.path, dir.path]
        let err2 = Pipe()
        p2.standardError = err2
        p2.standardOutput = Pipe()
        try p2.run()
        p2.waitUntilExit()
        if p2.terminationStatus != 0 {
            let msg = String(data: err2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "pkgutil failed"
            throw ManualUpdateError.install("解包失败：\(msg)")
        }
        try extractPayloadIfNeeded(in: dir)
    }

    private static func extractPayloadIfNeeded(in expanded: URL) throws {
        let fm = FileManager.default
        let payload = expanded.appendingPathComponent("Payload")
        guard fm.fileExists(atPath: payload.path) else {
            if let sub = try? fm.contentsOfDirectory(at: expanded, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "pkg" })
            {
                try extractPayloadIfNeeded(in: sub)
            }
            return
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: payload.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        let root = expanded.appendingPathComponent("PayloadRoot", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let cmd = """
        cd \(shellEscape(root.path)) && \
        /usr/bin/ditto -x \(shellEscape(payload.path)) . 2>/dev/null || \
        ( /usr/bin/gunzip -dc \(shellEscape(payload.path)) | /usr/bin/cpio -i 2>/dev/null )
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        try p.run()
        p.waitUntilExit()
    }

    private static func findAppBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [URL] = []
        for case let url as URL in en {
            guard url.pathExtension == "app" else { continue }
            candidates.append(url)
        }
        if let hit = candidates.first(where: { $0.lastPathComponent == "智额.app" }) {
            return hit
        }
        if let hit = candidates.first(where: { $0.lastPathComponent.lowercased().contains("smartquota") }) {
            return hit
        }
        return candidates.min(by: { $0.path.count < $1.path.count })
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appendLog(_ message: String) {
        let fm = FileManager.default
        let logURL = (fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory)
            .appendingPathComponent("Logs/SmartQuota", isDirectory: true)
        try? fm.createDirectory(at: logURL, withIntermediateDirectories: true)
        let file = logURL.appendingPathComponent("update.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if fm.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }
}

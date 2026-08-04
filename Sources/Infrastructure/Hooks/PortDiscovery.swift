import Foundation
import Domain

/// Manages the port discovery file at `~/.claude/smartquota-hook-port`.
/// Hook scripts read this file to find the HTTP server port.
public enum PortDiscovery {
    /// Path for the port discovery file.
    public static var portFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/\(AppIdentity.hookPortFileName)"
    }

    /// Writes the port number to the discovery file.
    /// Creates the `~/.claude` directory if it doesn't exist.
    public static func writePort(_ port: Int) throws {
        let path = portFilePath
        let directory = (path as NSString).deletingLastPathComponent

        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        try "\(port)".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Reads the port number from the discovery file.
    public static func readPort() -> Int? {
        guard let content = try? String(contentsOfFile: portFilePath, encoding: .utf8) else {
            return nil
        }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes the port discovery file.
    public static func removePortFile() {
        try? FileManager.default.removeItem(atPath: portFilePath)
    }
}

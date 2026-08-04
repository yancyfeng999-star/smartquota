import AppKit

/// Keeps 智额 alive as a menu-bar agent: closing windows must not quit the process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar + optional pinned window: red close only hides UI, app stays in status bar.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock-less agent: re-open (Finder / open -a) should not force quit paths.
        // Menu bar icon remains; user opens the extra from the status item.
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Defense in depth if Info.plist was overridden by a test build.
        NSApp.setActivationPolicy(.accessory)
    }
}

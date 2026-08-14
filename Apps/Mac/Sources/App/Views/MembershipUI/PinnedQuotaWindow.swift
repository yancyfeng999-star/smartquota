import SwiftUI
import AppKit
import Domain
import Infrastructure

/// Independent floating window for pin mode.
/// Opens flush to the top-right of the screen; min width fixed, height scrolls.
@MainActor
final class PinnedQuotaWindowController: NSObject, NSWindowDelegate {
    static let shared = PinnedQuotaWindowController()

    static let minWidth: CGFloat = 380
    static let defaultWidth: CGFloat = 400
    static let defaultHeight: CGFloat = 640

    private var window: NSWindow?
    private var isOpening = false
    private(set) var isOpen: Bool = false

    private override init() {
        super.init()
    }

    func openDeferred(
        monitor: QuotaMonitor,
        sessionMonitor: SessionMonitor,
        quotaAlerter: QuotaAlerter,
        refreshCoordinator: RefreshCoordinator,
        onHookSettingsChanged: ((Bool) -> Void)?
    ) {
        if isOpen {
            positionTopRightFlush()
            window?.orderFrontRegardless()
            return
        }
        if isOpening { return }

        isOpening = true
        AppSettings.shared.windowPinned = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.openNow(
                monitor: monitor,
                sessionMonitor: sessionMonitor,
                quotaAlerter: quotaAlerter,
                refreshCoordinator: refreshCoordinator,
                onHookSettingsChanged: onHookSettingsChanged
            )
        }
    }

    private func openNow(
        monitor: QuotaMonitor,
        sessionMonitor: SessionMonitor,
        quotaAlerter: QuotaAlerter,
        refreshCoordinator: RefreshCoordinator,
        onHookSettingsChanged: ((Bool) -> Void)?
    ) {
        defer { isOpening = false }

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: Self.defaultHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "\(Brand.nameCN) · \(Brand.nameEN)"
            win.isReleasedWhenClosed = false
            win.level = .floating
            win.hidesOnDeactivate = false
            // Safe collection behavior (no moveToActiveSpace — crashes with canJoinAllSpaces)
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.minSize = NSSize(width: Self.minWidth, height: 280)
            // Allow growing wide; no max width
            win.maxSize = NSSize(width: 10_000, height: 10_000)
            win.delegate = self
            self.window = win
        }

        let root = MenuContentView(
            monitor: monitor,
            sessionMonitor: sessionMonitor,
            quotaAlerter: quotaAlerter,
            refreshCoordinator: refreshCoordinator,
            onHookSettingsChanged: onHookSettingsChanged,
            runsInPinnedWindow: true
        )
        .appThemeProvider(themeModeId: AppSettings.shared.themeMode)
        .frame(
            minWidth: Self.minWidth,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )

        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        window?.contentView = host

        // Always snap to screen top-right, flush
        positionTopRightFlush(preferDefaultSize: true)

        isOpen = true
        AppSettings.shared.windowPinned = true
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Place window flush against the top-right of the main screen's visible frame.
    func positionTopRightFlush(preferDefaultSize: Bool = false) {
        guard let win = window, let screen = preferredScreen(for: win) else { return }
        let visible = screen.visibleFrame
        var size = win.frame.size
        if preferDefaultSize {
            size.width = max(Self.minWidth, Self.defaultWidth)
            // Cap default height to visible area so it fits under menu bar
            size.height = min(Self.defaultHeight, visible.height)
        }
        size.width = max(Self.minWidth, size.width)
        size.height = min(size.height, visible.height)

        // Flush: zero margin to top-right of visible frame (below menu bar, left of edge)
        let x = visible.maxX - size.width
        let y = visible.maxY - size.height
        win.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func preferredScreen(for win: NSWindow) -> NSScreen? {
        win.screen ?? NSScreen.main
    }

    func close() {
        isOpening = false
        isOpen = false
        AppSettings.shared.windowPinned = false
        window?.orderOut(nil)
        window?.contentView = NSView()
    }

    func toggleDeferred(
        monitor: QuotaMonitor,
        sessionMonitor: SessionMonitor,
        quotaAlerter: QuotaAlerter,
        refreshCoordinator: RefreshCoordinator,
        onHookSettingsChanged: ((Bool) -> Void)?
    ) {
        if isOpen || isOpening {
            close()
        } else {
            openDeferred(
                monitor: monitor,
                sessionMonitor: sessionMonitor,
                quotaAlerter: quotaAlerter,
                refreshCoordinator: refreshCoordinator,
                onHookSettingsChanged: onHookSettingsChanged
            )
        }
    }

    // Re-snap after user moves to another screen via maximize? keep their size but optional
    func windowDidChangeScreen(_ notification: Notification) {
        // Don't force re-snap on screen change if user dragged it; only initial open snaps.
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        isOpening = false
        AppSettings.shared.windowPinned = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        isOpen = false
        isOpening = false
        AppSettings.shared.windowPinned = false
        sender.orderOut(nil)
        sender.contentView = NSView()
        return false
    }
}

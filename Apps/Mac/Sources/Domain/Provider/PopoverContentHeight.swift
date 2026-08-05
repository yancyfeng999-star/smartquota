import Foundation

/// Height policy for the popover's scrollable content region.
///
/// Pure math, kept in Domain so it is unit-testable: the cap must never
/// let content push the action bar off-screen. The popover chrome (header,
/// provider pills, action bar, margins) surrounds the scrollable middle,
/// so the cap is the space that remains once the chrome is on screen.
public enum PopoverContentHeight {
    /// Vertical chrome around the scrollable region (header + pills +
    /// action bar + paddings).
    public static let chrome: CGFloat = 260

    /// Ceiling for overview mode (original design value — overview lists
    /// every provider and prefers a compact window).
    public static let overviewCeiling: CGFloat = 500

    /// Usable floor for degenerate displays: below this, a usable scroll
    /// region is preferred over strict on-screen fit.
    public static let usableFloor: CGFloat = 200

    /// Fixed popover panel width (home + settings share this).
    public static let panelWidth: CGFloat = 380

    /// Preferred popover panel height so switching home ↔ settings does not resize.
    public static let preferredPanelHeight: CGFloat = 580

    /// The max height for the scrollable content region.
    /// - Parameters:
    ///   - visibleScreenHeight: `NSScreen.visibleFrame.height` of the
    ///     screen hosting the popover.
    ///   - overviewMode: whether the popover lists all providers.
    public static func maxHeight(visibleScreenHeight: CGFloat, overviewMode: Bool) -> CGFloat {
        let available = max(visibleScreenHeight - chrome, usableFloor)
        return overviewMode ? min(overviewCeiling, available) : available
    }

    /// Full popover chrome height (home and settings must match to avoid flash).
    public static func panelHeight(visibleScreenHeight: CGFloat) -> CGFloat {
        let maxAllowed = max(visibleScreenHeight - 80, 420)
        return min(preferredPanelHeight, maxAllowed)
    }
}

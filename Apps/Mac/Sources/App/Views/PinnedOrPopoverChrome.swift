import SwiftUI
import AppKit
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

// MARK: - Popover vs pinned window chrome

/// Popover: **fixed** size so home ↔ settings does not shrink/flash.
/// Pinned window: fills host and allows vertical scroll.
struct PinnedOrPopoverChrome: ViewModifier {
    let runsInPinnedWindow: Bool

    private var panelHeight: CGFloat {
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        return PopoverContentHeight.panelHeight(visibleScreenHeight: screenH)
    }

    func body(content: Content) -> some View {
        if runsInPinnedWindow {
            content
                .frame(
                    minWidth: PopoverContentHeight.panelWidth,
                    maxWidth: .infinity,
                    minHeight: 0,
                    maxHeight: .infinity,
                    alignment: .top
                )
        } else {
            content
                .frame(
                    width: PopoverContentHeight.panelWidth,
                    height: panelHeight,
                    alignment: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipped()
        }
    }
}

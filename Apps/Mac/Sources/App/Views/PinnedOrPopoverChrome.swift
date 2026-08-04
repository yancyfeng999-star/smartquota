import SwiftUI
import AppKit
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

// MARK: - Popover vs pinned window chrome

/// Popover stays compact; pinned window fills host and allows vertical scroll.
struct PinnedOrPopoverChrome: ViewModifier {
    let runsInPinnedWindow: Bool

    func body(content: Content) -> some View {
        if runsInPinnedWindow {
            content
                .frame(minWidth: 380, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        } else {
            content
                .frame(width: 380)
                .fixedSize(horizontal: true, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipped()
        }
    }
}

import SwiftUI
import AppKit

// MARK: - Expand from under header (not from card top edge)

/// Animatable reveal: starts blurred / tucked under the header bottom, then settles downward.
/// Marked nonisolated so `Animatable` works under Swift 6 concurrency.
struct SoftExpandFromHeaderModifier: ViewModifier, Animatable, Sendable {
    /// 0 = hidden (under header, blurred), 1 = fully shown.
    var progress: Double

    nonisolated init(progress: Double) {
        self.progress = progress
    }

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = max(0, min(1, progress))
        // Ease-out for a silkier settle
        let eased = 1 - pow(1 - t, 2.2)
        // Tucked upward under the header, then drops into place below it
        let offsetY = (1 - eased) * -14
        // Grow downward from top of content block (= header bottom)
        let scaleY = 0.88 + 0.12 * eased
        // Strong blur at start, clears as it settles
        let blur = (1 - eased) * 12

        content
            .opacity(eased)
            .blur(radius: blur)
            .scaleEffect(x: 1, y: scaleY, anchor: .top)
            .offset(y: offsetY)
            .compositingGroup()
    }
}

/// App-wide motion tokens — keep every expand / hover / selection feeling the same.
enum AppMotion {
    /// Honors macOS Reduce Motion so expand / hover / selection do not animate.
    private static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func motion(_ animation: Animation) -> Animation {
        prefersReducedMotion ? .easeInOut(duration: 0.01) : animation
    }

    // MARK: - Timings

    /// Card expand / collapse (settings, language, membership, probe).
    static var expand: Animation { motion(.spring(response: 0.42, dampingFraction: 0.90)) }

    /// Chevron / small chrome that tracks expand.
    static var chevron: Animation { motion(.spring(response: 0.36, dampingFraction: 0.88)) }

    /// Chip / toggle selection.
    static var selection: Animation { motion(.spring(response: 0.32, dampingFraction: 0.86)) }

    /// Hover lift on membership cards.
    static var hover: Animation { motion(.easeOut(duration: 0.16)) }

    /// Soft fade for list appearance.
    static var appear: Animation { motion(.easeOut(duration: 0.35)) }

    // MARK: - Transitions

    /// Content unfolds **from below the header** (collapsed card bottom), with initial blur.
    static var expandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SoftExpandFromHeaderModifier(progress: 0),
                identity: SoftExpandFromHeaderModifier(progress: 1)
            ),
            removal: .modifier(
                active: SoftExpandFromHeaderModifier(progress: 0),
                identity: SoftExpandFromHeaderModifier(progress: 1)
            )
        )
    }

    /// Chip appear inside expanded panels (same soft expand-from-header feel).
    static var chipIn: AnyTransition {
        .modifier(
            active: SoftExpandFromHeaderModifier(progress: 0),
            identity: SoftExpandFromHeaderModifier(progress: 1)
        )
    }

    static func toggleExpand(_ isExpanded: Binding<Bool>) {
        withAnimation(expand) {
            isExpanded.wrappedValue.toggle()
        }
    }

    static func withExpand(_ body: () -> Void) {
        withAnimation(expand, body)
    }

    static func withSelection(_ body: () -> Void) {
        withAnimation(selection, body)
    }
}

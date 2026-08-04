import SwiftUI
import Domain

extension ClaudeSession.Phase {
    /// The display color for this session phase.
    /// Single source of truth — used by StatusBarIcon, SessionIndicatorView, etc.
    var color: Color {
        switch self {
        case .active: return .green
        case .subagentsWorking: return .blue
        case .stopped: return .orange
        case .ended: return .gray
        }
    }
}

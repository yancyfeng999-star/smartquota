import SwiftUI

/// Visual tokens for 智额 membership / quota chrome (liquid-glass surfaces).
enum MembershipPalette {
    // MARK: - Accent

    static let accentPrimary = Color(red: 0.157, green: 0.400, blue: 0.969) // #2866F7
    static let accentPrimaryLight = Color(red: 0.482, green: 0.627, blue: 1.000) // #7BA0FF
    static let accentSecondary = Color(red: 0.545, green: 0.427, blue: 1.000) // #8B6DFF
    static let accentHighlight = Color(red: 0.855, green: 0.639, blue: 0.980) // #DAA3FA

    // MARK: - Status (macOS system-aligned)

    static let statusSuccess = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let statusInfo = Color(red: 0.039, green: 0.518, blue: 1.000) // #0A84FF
    static let statusWarning = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let statusDanger = Color(red: 1.000, green: 0.271, blue: 0.227) // #FF453A

    static let surfaceTrack = Color.primary.opacity(0.10)

    // MARK: - Surfaces

    static func windowScrim(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }

    static func cardFill(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(elevated ? 0.11 : 0.08)
        }
        return Color.white.opacity(elevated ? 0.68 : 0.52)
    }

    static func cardStroke(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(elevated ? 0.14 : 0.10)
        }
        return Color.black.opacity(elevated ? 0.10 : 0.07)
    }

    static func controlFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.085) : Color.white.opacity(0.52)
    }

    static func controlSelectedFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.105)
    }

    static func controlStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    static func selectionFill(_ colorScheme: ColorScheme) -> Color {
        accentPrimary.opacity(colorScheme == .dark ? 0.18 : 0.12)
    }

    static func selectionStroke(_ colorScheme: ColorScheme) -> Color {
        accentPrimary.opacity(colorScheme == .dark ? 0.45 : 0.34)
    }

    /// Soft liquid-glass backdrop (no purple-pink orbs).
    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.14),
                    Color(red: 0.10, green: 0.11, blue: 0.18),
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.94, blue: 0.97),
                Color(red: 0.90, green: 0.92, blue: 0.98),
                Color(red: 0.94, green: 0.93, blue: 0.97),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Progress bar fill for remaining % (green when healthy, warms as low).
    static func progressColor(percentRemaining: Double) -> Color {
        switch percentRemaining {
        case ...0: return statusDanger
        case 0..<20: return statusDanger
        case 20..<50: return statusWarning
        default: return statusSuccess
        }
    }
}

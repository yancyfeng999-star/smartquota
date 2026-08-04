import SwiftUI
import AppKit
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

// MARK: - Bedrock Usage Card

/// Displays AWS Bedrock usage with cost and per-model breakdown.
struct BedrockUsageCard: View {
    let usage: BedrockUsageSummary
    let delay: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with cost
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProviderVisualIdentityLookup.color(for: "bedrock", scheme: colorScheme))

                        Text("TODAY'S USAGE")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                            .tracking(0.5)
                    }

                    // Large cost number
                    Text(usage.formattedTotalCost)
                        .font(.system(size: 36, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Stats column
                VStack(alignment: .trailing, spacing: 4) {
                    StatPill(icon: "number", value: "\(usage.totalInvocations)", label: "calls")
                    StatPill(icon: "text.word.spacing", value: usage.formattedTotalTokens, label: "tokens")
                }
            }

            // Model breakdown (if multiple models)
            if usage.modelUsages.count > 0 {
                Divider()
                    .background(theme.glassBorder)

                VStack(spacing: 6) {
                    ForEach(usage.modelsBySpend.prefix(3), id: \.model.id) { modelUsage in
                        HStack {
                            Text(modelUsage.model.displayName)
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text(modelUsage.formattedCost)
                                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    // Show "and X more" if more than 3 models
                    if usage.modelUsages.count > 3 {
                        Text("and \(usage.modelUsages.count - 3) more...")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            // Budget progress (if set)
            if let budgetPercent = usage.budgetPercentUsed,
               let budgetFormatted = usage.formattedDailyBudget {
                Divider()
                    .background(theme.glassBorder)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Daily Budget")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)

                        Spacer()

                        Text("\(Int(min(budgetPercent, 100)))% of \(budgetFormatted)")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(budgetPercent > 90 ? theme.statusCritical : theme.textPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.progressTrack)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(budgetPercent > 90 ? theme.statusCritical : theme.accentPrimary)
                                .frame(width: geo.size.width * min(CGFloat(budgetPercent) / 100, 1.0))
                        }
                    }
                    .frame(height: 4)
                }
            }

            // Time period
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))

                Text("Since \(formattedPeriodStart)")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
            }
            .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(delay), value: animateIn)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear { animateIn = true }
    }

    // Cached formatter to avoid recreation overhead
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var formattedPeriodStart: String {
        Self.timeFormatter.string(from: usage.periodStart)
    }
}

// MARK: - Stat Pill (for Bedrock card)

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.textTertiary)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Text(label)
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(theme.glassBackground)
        )
    }
}


import Foundation

/// The value and bar position used by compact quota summary cards.
public struct QuotaSummaryDisplay: Sendable, Equatable {
    public let valueText: String
    public let progressPercent: Double?
    public let isCountBased: Bool

    public init(
        valueText: String,
        progressPercent: Double?,
        isCountBased: Bool = false
    ) {
        self.valueText = valueText
        self.progressPercent = progressPercent
        self.isCountBased = isCountBased
    }
}

public extension UsageQuota {
    /// Returns the compact value and progress position for a quota summary card.
    ///
    /// Explicit count strings are only interpreted when their text says whether
    /// the numerator is used or remaining. Unlabeled ratios (for example Kimi's
    /// raw `14/100`) fall back to the authoritative percentage field.
    func summaryDisplay(mode: UsageDisplayMode) -> QuotaSummaryDisplay {
        if let count = Self.summaryCount(from: resetText) {
            let value = mode == .used ? count.used : count.remaining
            return QuotaSummaryDisplay(
                valueText: "\(value)/\(count.total)",
                progressPercent: displayProgressPercent(mode: mode),
                isCountBased: true
            )
        }

        if let dollars = dollarRemaining {
            let value = NSDecimalNumber(decimal: dollars).doubleValue
            let text: String
            if abs(value.rounded() - value) < 0.05 {
                text = String(format: "%.0f", value)
            } else {
                text = String(format: "%.1f", value)
            }
            return QuotaSummaryDisplay(
                valueText: text,
                progressPercent: nil
            )
        }

        return QuotaSummaryDisplay(
            valueText: "\(Int(displayPercent(mode: mode).rounded()))/100",
            progressPercent: displayProgressPercent(mode: mode)
        )
    }

    private struct SummaryCount {
        let used: Int
        let remaining: Int
        let total: Int
    }

    private enum SummaryCountSemantics {
        case used
        case remaining
    }

    private static func summaryCount(from resetText: String?) -> SummaryCount? {
        guard let resetText, !resetText.isEmpty else { return nil }

        let lowercased = resetText.lowercased()
        let semantics: SummaryCountSemantics
        if lowercased.contains("used") || resetText.contains("已用") {
            semantics = .used
        } else if lowercased.contains("remaining") || resetText.contains("剩余") {
            semantics = .remaining
        } else {
            return nil
        }

        let pattern = #"(\d+)\s*/\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: resetText,
                range: NSRange(resetText.startIndex..., in: resetText)
              ),
              match.numberOfRanges >= 3,
              let firstRange = Range(match.range(at: 1), in: resetText),
              let totalRange = Range(match.range(at: 2), in: resetText),
              let first = Int(resetText[firstRange]),
              let total = Int(resetText[totalRange]),
              total > 0 else {
            return nil
        }

        switch semantics {
        case .used:
            return SummaryCount(
                used: first,
                remaining: total - first,
                total: total
            )
        case .remaining:
            return SummaryCount(
                used: total - first,
                remaining: first,
                total: total
            )
        }
    }
}

import Foundation
import Domain

/// Resolves membership plan labels and renewal dates.
/// Prefer: manual override > local product defaults (no auto amount labels).
@MainActor
enum MembershipPlanStore {
    /// Canonical plan names (no prices). Kept in sync with ProviderCatalog.
    static var defaults: [String: String] {
        ProviderCatalog.defaultPlanLabels
    }

    static func displayPlan(for provider: any AIProvider) -> String {
        let manual = AppSettings.shared.planLabel(for: provider.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            return manual
        }
        // Prefer known product names over raw API tier tokens (PRO / LEVEL_*)
        if let known = defaults[provider.id] {
            return known
        }
        if let auto = autoPlan(from: provider.snapshot) {
            return auto
        }
        return L10n.shared.t("quota.plan_unset")
    }

    /// Display text for next renewal from activation (开通) date. Nil when unset.
    static func displayRenewal(for providerId: String) -> String? {
        let raw = AppSettings.shared.renewalDate(for: providerId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let l10n = L10n.shared
        guard let activation = MembershipRenewal.parse(raw) else {
            return "\(l10n.t("common.activation")) \(raw)"
        }
        let next = MembershipRenewal.nextRenewal(fromActivation: activation)
        return "\(l10n.t("quota.renewal")) \(MembershipRenewal.format(next))"
    }

    /// Activation (开通) date display for settings UI.
    static func displayActivation(for providerId: String) -> String? {
        let raw = AppSettings.shared.renewalDate(for: providerId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let d = MembershipRenewal.parse(raw) {
            return MembershipRenewal.format(d)
        }
        return raw
    }

    static func autoPlan(from snapshot: UsageSnapshot?) -> String? {
        guard let tier = snapshot?.accountTier else { return nil }
        switch tier {
        case .claudeMax: return "Claude Max"
        case .claudePro: return "Claude Pro"
        case .claudeApi: return "API"
        case .custom(let badge):
            let cleaned = badge.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            // Kimi LEVEL_* → known map if possible
            let upper = cleaned.uppercased()
            // Official Kimi product tier tokens → public tier names (not user-specific)
            if upper.hasPrefix("LEVEL_") {
                let level = String(cleaned.dropFirst(6)).uppercased()
                switch level {
                case "INTERMEDIATE", "ALLEGRO", "ALLEGRETTTO", "ALLEGRETTO": return "Allegretto"
                case "ANDANTE": return "Andante"
                case "MODERATO": return "Moderato"
                default: return level.capitalized
                }
            }
            // Generic API tier tokens — no personal plan names
            if upper == "PRO" { return "Pro" }
            if upper == "PLUS" { return "Plus" }
            if upper == "PRO+" || upper == "PRO_PLUS" || upper == "PROPLUS" { return "Pro+" }
            if upper == "ULTRA" { return "Ultra" }
            if upper == "START" { return "Start" }
            if upper == "HOBBY" || upper == "FREE" { return "Hobby" }
            if upper == "TEAMS" || upper == "BUSINESS" { return "Teams" }
            if upper == "ENTERPRISE" { return "Enterprise" }
            return cleaned
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "MM-dd", "yyyy年M月d日"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }
}

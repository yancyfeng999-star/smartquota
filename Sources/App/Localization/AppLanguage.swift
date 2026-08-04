import Foundation
import SwiftUI

/// Supported UI languages for 智额.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case ru = "ru"
    case ar = "ar"
    case fr = "fr"
    case de = "de"
    case es = "es"
    case pt = "pt"

    var id: String { rawValue }

    /// Name shown in the language picker (native + Chinese label).
    var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .ru: return "Русский"
        case .ar: return "العربية"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .pt: return "Português"
        }
    }

    /// Short chip label.
    var shortName: String {
        switch self {
        case .zhHans: return "中文"
        case .en: return "EN"
        case .ja: return "JP"
        case .ko: return "KR"
        case .ru: return "RU"
        case .ar: return "AR"
        case .fr: return "FR"
        case .de: return "DE"
        case .es: return "ES"
        case .pt: return "PT"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        self == .ar ? .rightToLeft : .leftToRight
    }

    var isRTL: Bool { self == .ar }

    static var `default`: AppLanguage { .zhHans }

    static func resolve(_ raw: String?) -> AppLanguage {
        guard let raw, let lang = AppLanguage(rawValue: raw) else { return .default }
        return lang
    }
}

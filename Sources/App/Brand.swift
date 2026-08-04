import Foundation

/// Product branding for 智额 · SmartQuota.
enum Brand {
    /// 中文产品名
    static let nameCN = "智额"
    /// 英文产品名
    static let nameEN = "SmartQuota"
    /// 标题栏 / 关于：中英并列
    static let displayTitle = "\(nameCN)"
    /// 副标题
    static let taglineCN = "会员额度监控"
    static let taglineEN = "Membership quota monitor"

    /// 关于页完整说明（随界面语言切换）
    @MainActor
    static var aboutLine: String {
        L10n.shared.t("app.about")
    }
}

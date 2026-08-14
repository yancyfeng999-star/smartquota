import Foundation

/// Languages used by the support / accessibility copy contract.
/// UI chrome still goes through `L10n`; this table is the testable source for
/// help, unified errors, and VoiceOver keys (zh-Hans + English).
public enum SupportLanguage: String, Sendable, CaseIterable {
    case zhHans
    case en
}

/// Bilingual support strings shared by help, error copy, and accessibility.
public enum SupportCopy: Sendable {
    public static func text(_ key: String, _ language: SupportLanguage) -> String {
        guard let pair = table[key] else { return key }
        switch language {
        case .zhHans: return pair.zh
        case .en: return pair.en
        }
    }

    public static func contains(_ key: String) -> Bool {
        table[key] != nil
    }

    public static var allKeys: [String] { table.keys.sorted() }

    private static let table: [String: (zh: String, en: String)] = [
        // MARK: Help chrome
        "help.title": ("帮助中心", "Help Center"),
        "help.subtitle": (
            "首次配置、更新、日志、多账号、密钥与隐私。可打开日志、诊断中心、Release 页面和本地用户手册。",
            "First setup, updates, logs, accounts, keys, and privacy. Open logs, Diagnostics, the Release page, or the local user guide."
        ),
        "help.section.actions": ("快捷入口", "Shortcuts"),
        "help.section.topics": ("主题与 FAQ", "Topics and FAQ"),
        "help.open_logs": ("打开日志", "Open logs"),
        "help.open_diagnostics": ("打开诊断中心", "Open Diagnostics"),
        "help.open_releases": ("打开 Release 页面", "Open Release page"),
        "help.open_guide": ("打开用户手册", "Open user guide"),
        "settings.help": ("帮助中心", "Help Center"),
        "settings.help_sub": ("首次配置、日志、隐私和常见问题", "First setup, logs, privacy, and FAQ"),

        // MARK: Help topics
        "help.topic.first_setup.title": ("首次配置", "First setup"),
        "help.topic.first_setup.body": (
            "首次打开会看到引导：说明本机优先、检查兼容性、选择第一个会员并做一次检测。可随时跳过；设置里仍有「继续引导」。关闭引导窗口不会退出智额。",
            "The first launch walks through local-first privacy, compatibility, choosing a membership, and one check. Skip anytime; Settings keeps Continue setup. Closing the guide does not quit SmartQuota."
        ),
        "help.topic.check_updates.title": ("检查更新", "Check for updates"),
        "help.topic.check_updates.body": (
            "在设置中点「检查更新」。应用只访问公开的 GitHub Releases，不会默认静默安装。有新版本时由你触发下载与安装；也可打开项目 Release 页面手动下载。",
            "Tap Check for Updates in Settings. The app only reads public GitHub Releases and does not silently install. You trigger download and install; you can also open the project Release page."
        ),
        "help.topic.log_location.title": ("日志位置", "Log location"),
        "help.topic.log_location.body": (
            "日志在 ~/Library/Logs/SmartQuota/SmartQuota.log，只留在本机。设置或帮助中心可打开该文件。请勿分享含有邮箱、密钥或 Cookie 的原始日志。",
            "Logs live at ~/Library/Logs/SmartQuota/SmartQuota.log on this Mac. Settings or Help can open the file. Do not share raw logs that contain emails, keys, or cookies."
        ),
        "help.topic.multi_account.title": ("多账号", "Multiple accounts"),
        "help.topic.multi_account.body": (
            "同一会员可跟踪多个账号，但同一时间只刷新本机当前登录。读不到登录态时保留上次快照并显示「未登录」；网络失败显示「连接失败」，两者不会混淆。",
            "A membership can track several accounts, but only the account signed in on this Mac is refreshed. If login is missing, the last snapshot stays and shows Not signed in. Network failures show Connection failed and are not mixed with that state."
        ),
        "help.topic.key_security.title": ("密钥安全", "Key security"),
        "help.topic.key_security.body": (
            "API Key、Token 和 Cookie 保存在本机钥匙串，不会进入导出、备份或诊断摘要。可在设置 › 安全中用 Touch ID 保护查看。删除账号只清理智额本地记录，不会登出外部 CLI。",
            "API keys, tokens, and cookies stay in the local Keychain and never enter export, backup, or diagnostic summaries. Touch ID can protect viewing them in Settings › Security. Deleting an account only clears SmartQuota’s local record."
        ),
        "help.topic.privacy.title": ("隐私", "Privacy"),
        "help.topic.privacy.body": (
            "智额是本机优先：设置、备注、缓存和诊断都留在这台 Mac。没有云账号，也不会上传密钥、Cookie、完整邮箱、原始日志或额度明细。",
            "SmartQuota is local-first: settings, notes, cache, and diagnostics stay on this Mac. There is no cloud account, and keys, cookies, full emails, raw logs, and quota details are not uploaded."
        ),
        "help.topic.faq.title": ("常见问题", "FAQ"),
        "help.topic.faq.body": (
            "Q：卡片显示未登录或连接失败？\nA：未登录会保留旧快照；连接失败也保留旧数据。下一步：打开配置或诊断中心，不要删除会员重来。\n\nQ：关掉面板后图标没了？\nA：点关闭只收起面板，不会退出。只有「退出应用」才结束进程。\n\nQ：如何自己排查？\nA：打开诊断中心运行检查，或查看本机日志和用户手册。",
            "Q: The card says Not signed in or Connection failed?\nA: Both keep the old snapshot. Next: open setup or Diagnostics; do not delete the membership to start over.\n\nQ: The menu-bar icon vanished after closing the panel?\nA: Close only hides the panel. Only Quit App ends the process.\n\nQ: How do I troubleshoot?\nA: Run Diagnostics, or open the local log and user guide."
        ),

        // MARK: Unified errors — what / kept / next
        "error.refreshNetwork.what": (
            "刷新失败：网络不可用或请求超时。",
            "Refresh failed: the network is unavailable or the request timed out."
        ),
        "error.refreshNetwork.kept": (
            "已保留该会员上次成功读取的额度快照，没有清空历史数据。",
            "The last successful quota snapshot is kept. Historical data was not cleared."
        ),
        "error.refreshNetwork.next": (
            "请恢复网络后点刷新，或打开诊断中心查看网络检查。",
            "Restore the network and tap Refresh, or open Diagnostics to inspect reachability."
        ),
        "error.refreshNotLoggedIn.what": (
            "当前本机没有可用登录态，因此读不到新额度。",
            "This Mac has no usable sign-in, so new quota data could not be read."
        ),
        "error.refreshNotLoggedIn.kept": (
            "已保留上次成功快照，并显示「未登录」，不会用空数据覆盖。",
            "The last successful snapshot is kept and shown as Not signed in. It is not replaced with empty data."
        ),
        "error.refreshNotLoggedIn.next": (
            "请在对应 CLI 或客户端重新登录，然后在设置中检测配置。",
            "Sign in again in the matching CLI or app, then test the setup in Settings."
        ),
        "error.refreshMissingCLI.what": (
            "未找到该会员需要的命令行工具，无法检测额度。",
            "The command-line tool this membership needs was not found, so quota could not be checked."
        ),
        "error.refreshMissingCLI.kept": (
            "已保留旧快照；智额不会卸载或改写你已有的配置。",
            "The previous snapshot is kept. SmartQuota does not uninstall tools or rewrite your existing config."
        ),
        "error.refreshMissingCLI.next": (
            "请自行安装并登录对应 CLI。智额不会自动安装第三方工具。可打开帮助或诊断查看说明。",
            "Install and sign in to that CLI yourself. SmartQuota will not auto-install third-party tools. Open Help or Diagnostics for the steps."
        ),
        "error.refreshMissingKey.what": (
            "缺少本机密钥或凭证，无法完成检测。",
            "A local key or credential is missing, so the check could not finish."
        ),
        "error.refreshMissingKey.kept": (
            "已保留旧数据；不会把空密钥写入钥匙串，也不会删除其他账号。",
            "Previous data is kept. An empty key is not written to the Keychain, and other accounts are not deleted."
        ),
        "error.refreshMissingKey.next": (
            "到设置 › 额度检测配置中补上 Key，或打开诊断中心查看「缺少 Key」。",
            "Add the key in Settings › Quota detection, or open Diagnostics and look for Missing key."
        ),
        "error.refreshServiceRejected.what": (
            "会员服务拒绝了这次请求（限流或接口错误）。",
            "The membership service rejected this request (rate limit or endpoint error)."
        ),
        "error.refreshServiceRejected.kept": (
            "已保留上次有效额度；这次失败不会改写本地缓存为空白。",
            "The last valid quota is kept. This failure does not blank the local cache."
        ),
        "error.refreshServiceRejected.next": (
            "稍后再刷新，或打开会员后台确认套餐与登录。也可运行诊断。",
            "Refresh later, or open the membership dashboard to confirm the plan and sign-in. You can also run Diagnostics."
        ),
        "error.refreshFailed.what": (
            "这次刷新没有得到新的额度结果。",
            "This refresh did not return a new quota result."
        ),
        "error.refreshFailed.kept": (
            "已保留旧快照和账号记录，不会因为一次失败清空会员。",
            "The previous snapshot and account record are kept. One failure does not remove the membership."
        ),
        "error.refreshFailed.next": (
            "请打开诊断中心或日志查看原因，再重试刷新。",
            "Open Diagnostics or the log to see why, then try Refresh again."
        ),
        "error.updateCheckFailed.what": (
            "检查更新失败，没有下载或安装任何新版本。",
            "The update check failed. No new version was downloaded or installed."
        ),
        "error.updateCheckFailed.kept": (
            "当前已安装版本保持不变。",
            "The installed version is unchanged."
        ),
        "error.updateCheckFailed.next": (
            "请检查网络后重试，或打开项目 Release 页面手动下载。",
            "Check the network and try again, or open the project Release page to download manually."
        ),
        "error.settingsSaveFailed.what": (
            "设置没有写成功。",
            "Settings could not be saved."
        ),
        "error.settingsSaveFailed.kept": (
            "磁盘上的原设置文件保持不变。",
            "The settings file on disk is left unchanged."
        ),
        "error.settingsSaveFailed.next": (
            "请确认 ~/.smartquota 可写，然后重试。必要时打开诊断或安全模式。",
            "Confirm ~/.smartquota is writable, then retry. Open Diagnostics or Safe Mode if it keeps failing."
        ),
        "error.backupRestoreFailed.what": (
            "恢复备份没有完成。",
            "Restoring the backup did not finish."
        ),
        "error.backupRestoreFailed.kept": (
            "当前设置和备份文件都还在，已保留原数据，没有用半成品覆盖。",
            "Current settings and the backup file are still in place. Previous data is kept and was not half-overwritten."
        ),
        "error.backupRestoreFailed.next": (
            "请再试一次，或打开日志查看备份位置。",
            "Try again, or open the log to find the backup location."
        ),
        "error.exportFailed.what": (
            "导出非敏感设置失败。",
            "Exporting non-sensitive settings failed."
        ),
        "error.exportFailed.kept": (
            "本机设置、密钥和备份均未改动。",
            "Local settings, keys, and backups were not changed."
        ),
        "error.exportFailed.next": (
            "请另选可写位置再导出。导出文件不会包含密钥。",
            "Choose a writable location and export again. The file never includes secrets."
        ),
        "error.importFailed.what": (
            "导入设置没有完成。",
            "Importing settings did not finish."
        ),
        "error.importFailed.kept": (
            "当前设置、钥匙串和外部登录态均未改动。",
            "Current settings, Keychain items, and external logins were left unchanged."
        ),
        "error.importFailed.next": (
            "请检查文件是否为智额导出的 JSON，再选择合并或覆盖。",
            "Check that the file is a SmartQuota export, then choose merge or overwrite."
        ),
        "error.migrationFailed.what": (
            "设置迁移失败，没有采用不完整的新配置。",
            "Settings migration failed. An incomplete new configuration was not applied."
        ),
        "error.migrationFailed.kept": (
            "原 settings.json 已恢复或从未改写，并保留迁移前备份。",
            "The original settings.json was restored or never rewritten. The pre-migration backup is kept."
        ),
        "error.migrationFailed.next": (
            "在安全模式中恢复备份或查看备份路径，然后重试正常模式。",
            "In Safe Mode, restore a backup or note the backup path, then retry normal mode."
        ),
        "error.settingsCorrupt.what": (
            "settings.json 无法读取。",
            "settings.json could not be read."
        ),
        "error.settingsCorrupt.kept": (
            "损坏文件仍留在原处，并复制了一份到 recovery/corrupt/。当前只用只读默认值。",
            "The damaged file is still in place, with a copy under recovery/corrupt/. Only read-only defaults are in use."
        ),
        "error.settingsCorrupt.next": (
            "打开安全模式恢复备份，或导出后重置智额自己的设置。",
            "Open Safe Mode to restore a backup, or export and then reset SmartQuota’s own settings."
        ),

        // MARK: VoiceOver — icon buttons
        "a11y.refresh.label": ("刷新全部会员", "Refresh all memberships"),
        "a11y.refresh.hint": ("重新检测已开启会员的额度。可按 ⌘R。", "Recheck quota for enabled memberships. Press ⌘R."),
        "a11y.refresh.value.idle": ("空闲", "Idle"),
        "a11y.refresh.value.running": ("正在刷新", "Refreshing"),
        "a11y.refresh.current.label": ("刷新当前会员", "Refresh current membership"),
        "a11y.refresh.current.hint": ("只重新检测当前选中会员的本机账号。", "Recheck only the current membership’s signed-in account."),
        "a11y.refresh.cancel.label": ("取消刷新", "Cancel refresh"),
        "a11y.refresh.cancel.hint": ("停止尚未开始的刷新。已完成的结果会保留。", "Stop remaining refresh work. Finished results are kept."),
        "a11y.refresh.cancel.value": ("可以取消", "Can cancel"),
        "a11y.pin.label": ("固定窗口", "Pin window"),
        "a11y.pin.hint": ("打开或关闭常驻窗口，点击其他应用时面板不会消失。", "Open or close the persistent window so the panel stays when you click another app."),
        "a11y.pin.value.on": ("已固定", "Pinned"),
        "a11y.pin.value.off": ("未固定", "Unpinned"),
        "a11y.close_panel.label": ("关闭面板", "Close panel"),
        "a11y.close_panel.hint": ("只隐藏窗口，智额继续在菜单栏运行。", "Hides the window only. SmartQuota stays in the menu bar."),
        "a11y.close_panel.value": ("面板打开", "Panel open"),
        "a11y.settings_icon.label": ("设置", "Settings"),
        "a11y.settings_icon.hint": ("打开设置。可按 ⌘,。", "Open Settings. Press ⌘,."),
        "a11y.settings_icon.value": ("设置", "Settings"),
        "a11y.share.label": ("分享 Claude 通行", "Share Claude pass"),
        "a11y.share.hint": ("显示可分享的 Claude 访客通行。", "Show a shareable Claude guest pass."),
        "a11y.share.value": ("可分享", "Available"),
        "a11y.help.label": ("帮助中心", "Help Center"),
        "a11y.help.hint": ("打开应用内帮助、日志和用户手册。可按 ⌘?。", "Open in-app help, logs, and the user guide. Press ⌘?."),
        "a11y.help.value": ("帮助", "Help"),
        "a11y.back.label": ("返回", "Back"),
        "a11y.back.hint": ("返回菜单栏主面板。", "Return to the menu-bar panel."),
        "a11y.back.value": ("设置已打开", "Settings open"),
        "status.info": ("提示", "Info"),
        "status.severity.warning": ("警告", "Warning"),
    ]
}

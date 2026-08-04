import Foundation

/// How each built-in membership probes quota — used by 额度检测配置.
struct ProviderProbeGuide: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    /// Ordered steps shown in the config form (left-aligned).
    let steps: [String]
    /// Optional credential / CLI path hints.
    let credentialHint: String?
    let dashboardURL: URL?

    @MainActor
    static func guide(for providerId: String) -> ProviderProbeGuide {
        let base = catalog[providerId] ?? ProviderProbeGuide(
            id: providerId,
            title: "\(providerId)",
            summary: L10n.shared.t("common.how_to_probe"),
            steps: [L10n.shared.t("common.how_to_probe")],
            credentialHint: nil,
            dashboardURL: nil
        )
        // Prefer localized title/summary/steps when present in L10n tables.
        let lang = L10n.shared.language
        let titleKey = "probe.\(providerId).title"
        let summaryKey = "probe.\(providerId).summary"
        let title = L10n.lookup(titleKey, language: lang)
        let summary = L10n.lookup(summaryKey, language: lang)
        let steps = base.steps.enumerated().map { index, fallback in
            let key = "probe.\(providerId).step.\(index)"
            let value = L10n.lookup(key, language: lang)
            return value == key ? fallback : value
        }
        let hintKey = "probe.\(providerId).hint"
        let hintLookup = L10n.lookup(hintKey, language: lang)
        let hint = hintLookup == hintKey ? base.credentialHint : hintLookup
        return ProviderProbeGuide(
            id: base.id,
            title: title == titleKey ? base.title : title,
            summary: summary == summaryKey ? base.summary : summary,
            steps: steps,
            credentialHint: hint,
            dashboardURL: base.dashboardURL
        )
    }

    /// Complete catalog for all built-in providers.
    static let catalog: [String: ProviderProbeGuide] = [
        "codex": ProviderProbeGuide(
            id: "codex",
            title: "ChatGPT 额度检测",
            summary: "通过 Codex CLI（RPC）或 ChatGPT OAuth（API）读取限速额度",
            steps: [
                "RPC 模式：本机 codex app-server 拉取 5 小时 / 周限额",
                "API 模式：读取 ~/.codex/auth.json，请求 ChatGPT 额度接口",
                "推荐 API：稳定且无需常驻交互 CLI",
            ],
            credentialHint: "凭证：~/.codex/auth.json（终端运行 codex 登录后生成）",
            dashboardURL: URL(string: "https://chatgpt.com")
        ),
        "kimi": ProviderProbeGuide(
            id: "kimi",
            title: "Kimi 额度检测",
            summary: "CLI /usage 或 Coding API / Cookie 拉取周 / 5 小时额度",
            steps: [
                "CLI 模式：启动 kimi 交互命令并发送 /usage",
                "API 模式：优先 sk-kimi Coding Key，其次浏览器 Cookie",
                "查找顺序：环境变量 → kimi-desktop 本地 Key → 浏览器 kimi-auth",
            ],
            credentialHint: "API：KIMI_CODE_API_KEY / sk-kimi；或浏览器登录 kimi.com",
            dashboardURL: URL(string: "https://www.kimi.com")
        ),
        "minimax": ProviderProbeGuide(
            id: "minimax",
            title: "MiniMax 额度检测",
            summary: "Coding Plan API（国内 / 国际区域）Bearer Token 查询",
            steps: [
                "按区域选择 minimaxi.com 或 minimax.io 接口",
                "密钥顺序：环境变量 → 设置中保存的 Key → ~/.minimax/config.yaml",
                "成功后显示 Coding Plan 剩余额度",
            ],
            credentialHint: "环境变量默认 MINIMAX_API_KEY，也可在配置里填写",
            dashboardURL: URL(string: "https://platform.minimaxi.com")
        ),
        "grok": ProviderProbeGuide(
            id: "grok",
            title: "Grok 额度检测",
            summary: "xAI OAuth + billing credits 接口",
            steps: [
                "读取 ~/.grok/auth.json 中的 OAuth access token",
                "过期则用 refresh_token 向 auth.x.ai 刷新",
                "请求 cli-chat-proxy 的 billing?format=credits 得到额度",
            ],
            credentialHint: "终端登录 grok / xAI CLI 后会写入 ~/.grok/auth.json",
            dashboardURL: URL(string: "https://grok.com/?_s=usage")
        ),
        "claude": ProviderProbeGuide(
            id: "claude",
            title: "Claude 额度检测",
            summary: "Claude Code CLI `/usage` 或 Anthropic OAuth API",
            steps: [
                "CLI 模式：运行 claude /usage 解析会话与周额度",
                "API 模式：OAuth 凭证直连接口（可缓存约 15 分钟）",
                "可选：Guest Pass 与 API 预算阈值",
            ],
            credentialHint: "需安装 Claude Code，并完成登录",
            dashboardURL: URL(string: "https://claude.ai")
        ),
        "gemini": ProviderProbeGuide(
            id: "gemini",
            title: "Gemini 额度检测",
            summary: "Gemini CLI OAuth 凭证 + Google 用量接口",
            steps: [
                "读取 ~/.gemini/oauth_creds.json",
                "用 access token 请求 Gemini 用量 / 配额接口",
                "Token 过期时可尝试 CLI 刷新后再探测",
            ],
            credentialHint: "终端运行 gemini 登录后生成 oauth_creds.json",
            dashboardURL: URL(string: "https://aistudio.google.com")
        ),
        "copilot": ProviderProbeGuide(
            id: "copilot",
            title: "Copilot 额度检测",
            summary: "GitHub Billing API 或 Copilot Internal API",
            steps: [
                "Billing 模式：GitHub Billing API（细粒度 PAT，Plan:read）",
                "Internal 模式：api.github.com/copilot_internal/user（Classic PAT copilot）",
                "可配置用户名、月额度上限与手动覆盖",
            ],
            credentialHint: "在配置里粘贴 GitHub Token，或设环境变量",
            dashboardURL: URL(string: "https://github.com/settings/copilot")
        ),
        "cursor": ProviderProbeGuide(
            id: "cursor",
            title: "Cursor 额度检测",
            summary: "本机 Cursor 登录库 + usage-summary API",
            steps: [
                "读取 ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                "从库中取出 access token，解码 JWT 得到 userId",
                "请求 https://cursor.com/api/usage-summary 解析 plan / on-demand",
            ],
            credentialHint: "需已在本机 Cursor 客户端登录",
            dashboardURL: URL(string: "https://cursor.com/settings")
        ),
        "antigravity": ProviderProbeGuide(
            id: "antigravity",
            title: "Antigravity 额度检测",
            summary: "本机 Antigravity 语言服务本地 API",
            steps: [
                "检测本机是否运行 Antigravity / 相关 CLI",
                "请求本地 HTTPS 接口（可含自签证书）",
                "解析返回的配额窗口与剩余比例",
            ],
            credentialHint: "保持 Antigravity 客户端或服务已登录并可用",
            dashboardURL: nil
        ),
        "zai": ProviderProbeGuide(
            id: "zai",
            title: "Z.ai / GLM 额度检测",
            summary: "settings.json 中的 token 或环境变量",
            steps: [
                "优先从配置的 settings.json 路径读取 token",
                "找不到则读环境变量（如 GLM_AUTH_TOKEN）",
                "调用 Z.ai / GLM 用量接口",
            ],
            credentialHint: "可指定 ~/.claude/settings.json 或自定义路径",
            dashboardURL: URL(string: "https://z.ai")
        ),
        "bedrock": ProviderProbeGuide(
            id: "bedrock",
            title: "AWS Bedrock 额度检测",
            summary: "AWS Profile + CloudWatch 用量与定价",
            steps: [
                "使用本机 AWS profile（aws configure）",
                "查询指定区域 CloudWatch 调用量",
                "结合定价估算费用，可设每日预算",
            ],
            credentialHint: "aws configure --profile <name>，并在配置中填 profile / regions",
            dashboardURL: URL(string: "https://console.aws.amazon.com/bedrock/home")
        ),
        "alibaba": ProviderProbeGuide(
            id: "alibaba",
            title: "阿里云 Coding Plan 检测",
            summary: "浏览器 Cookie 自动导入或 API Key",
            steps: [
                "区域：国内 / 国际控制台",
                "Cookie：自动从浏览器读取，或手动粘贴",
                "也可使用 API Key 探测 Coding Plan 额度",
            ],
            credentialHint: "浏览器登录阿里云控制台，或配置 API Key",
            dashboardURL: URL(string: "https://bailian.console.aliyun.com")
        ),
        "ampcode": ProviderProbeGuide(
            id: "ampcode",
            title: "Amp 额度检测",
            summary: "Sourcegraph Amp CLI：`amp usage`",
            steps: [
                "定位本机 amp 命令",
                "执行 amp usage 解析配额输出",
                "映射为剩余额度卡片",
            ],
            credentialHint: "安装 Amp CLI 并完成登录",
            dashboardURL: URL(string: "https://ampcode.com")
        ),
        "kiro": ProviderProbeGuide(
            id: "kiro",
            title: "Kiro 额度检测",
            summary: "交互式 kiro-cli `/usage`",
            steps: [
                "定位本机 kiro-cli",
                "启动交互会话并发送 /usage",
                "解析 credits / 周期重置信息",
            ],
            credentialHint: "安装 Kiro CLI 并登录账号",
            dashboardURL: nil
        ),
        "mistral": ProviderProbeGuide(
            id: "mistral",
            title: "Mistral / Vibe 额度检测",
            summary: "本地 Vibe 会话日志估算今日用量（无需联网）",
            steps: [
                "检查 ~/.vibe/logs/session 是否存在",
                "扫描今日 session 元数据与 token",
                "按 Devstral 定价汇总今日成本",
            ],
            credentialHint: "使用 Vibe 客户端产生本地会话日志即可",
            dashboardURL: nil
        ),
        "opencode-go": ProviderProbeGuide(
            id: "opencode-go",
            title: "OpenCode Go 额度检测",
            summary: "本机 opencode 数据库统计 5h / 周 / 月窗口",
            steps: [
                "定位本机 opencode 命令",
                "查询本地 DB 中消息与用量窗口",
                "映射 $12/5h、$30/周、$60/月 类限额",
            ],
            credentialHint: "安装 OpenCode 并使用 Go 套餐账号",
            dashboardURL: nil
        ),
        "omp": ProviderProbeGuide(
            id: "omp",
            title: "Oh My Pi 额度检测",
            summary: "`omp usage --json` 汇总多账号限速窗口",
            steps: [
                "定位本机 omp 命令",
                "执行 omp usage --json",
                "把每个源平台 provider 的 5h/周 等窗口显示为额度",
            ],
            credentialHint: "安装 Oh My Pi (omp) 并完成各账号 OAuth",
            dashboardURL: nil
        ),
    ]
}

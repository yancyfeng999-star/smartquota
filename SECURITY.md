# 智额 · SmartQuota — 安全与隐私说明

智额是本机优先的额度监控工具。本文档描述当前仓库和默认 Mac 构建的安全边界，不是对任意第三方服务、用户设备或未来构建的绝对安全保证。实现、测试和发布状态以源码、CI 和 Release 证据为准。

当前公开基线：Mac `0.3.29`（build 32）。发现安全边界、网络出口、依赖、更新方式或诊断数据变化时，必须同步更新本文档、[NOTICE](./NOTICE)、用户文档和 [CHANGELOG.md](./CHANGELOG.md)。

## 当前默认行为

| 项目 | 当前状态 | 证据边界 |
|---|---|---|
| 数据上传 | 默认不向智额自有服务器上传用量、密钥或设备信息 | 内置探针、日志和网络代码；用户配置的扩展 URL 除外 |
| 更新检查 | 用户主动点击后访问 GitHub 公共 Releases API | `GitHubReleaseChecker`、`ReleaseDownloader`、发布工作流 |
| 自动更新 | 默认 Mac Tuist 目标未启用 Sparkle，也未链接 Sparkle 依赖 | 源码仍保留 `#if ENABLE_SPARKLE` 条件路径；在未完成审查前不得启用 |
| 遥测/崩溃上报 | 当前未配置 Sentry、Firebase、Crashlytics 或作者自有上报服务 | 未来接入必须先增加明确同意、脱敏、删除和停止上传机制 |
| 远程服务 | 内置 Provider 官方端点、用户配置的健康检查 URL、用户主动触发的 GitHub API | 具体 URL 以 Provider 实现和设置为准 |

“没有默认上传”不等于“第三方服务不会收到请求”：用户开启某个会员探针后，数据会按该服务自己的 API 和服务条款发送到对应官方端点。

## 网络与本地数据边界

### 可能访问的网络

- 各内置 Provider 用于读取用户自己额度或刷新用户自己登录态的官方端点。
- 用户在扩展设置中主动配置的 `http`/`https` 健康检查地址。
- 用户点击「检查更新」时访问 GitHub 公共 Releases API；下载 Release 资产时访问 GitHub 资产 URL。
- 本地 Hook 服务只监听 `127.0.0.1`，不对局域网开放。

应用不会把用量、密钥、Cookie、OAuth 文件或完整日志发送到智额维护者的服务器。网络失败时，应用应保留最后成功快照并显示失败状态，不把错误当成新额度。

### 本地存储

| 数据 | 位置 | 处理边界 |
|---|---|---|
| 普通设置、账号备注、套餐标签、续费日期 | `~/.smartquota/settings.json` | 本机保存；不进入导出/备份中的敏感字段 |
| 额度快照 | `~/.smartquota/account-snapshots.json` | 本机缓存；读不到时保留旧快照并显示未登录/连接失败 |
| API Key、Cookie、PAT | macOS Keychain | 通过 `KeychainSecretStore` 保存；不得写入日志或仓库 |
| OAuth 登录文件 | 各工具自己的 `~/.codex/`、`~/.claude/`、`~/.grok/` 等 | 智额按需只读，不复制到自己的配置目录 |
| 日志 | `~/Library/Logs/SmartQuota/` | 本地轮换；分享前必须脱敏 |
| Release 下载文件 | `~/Downloads/` | 用户主动检查更新后产生；失败时应清理或明确提示 |

多账号只记录必要的邮箱或外部账号 ID 以匹配历史账号；邮箱、额度、账号备注、续费日期和快照不上传。删除账号时清理智额自己的配置、快照和账号级密钥，不删除外部 CLI 或浏览器的登录态。

## 凭证和生物识别

- 普通 Provider 密钥由 Keychain 包装器保存，服务名使用应用 Bundle ID，账号名按 Provider/用途区分。
- 生物识别路径使用 macOS LocalAuthentication；系统负责 Touch ID/Face ID 模板和设备认证。智额不读取或保存生物识别模板。
- `SecureKeychainStore` 可使用 `SecAccessControl` 配置 `biometryCurrentSet` / `userPresence`，但认证策略的部分观察状态目前由应用内存维护；不要把“设置界面显示需要生物识别”当成跨重启的独立安全证明。
- Keychain 内容、OAuth 文件、Cookie 和认证响应不得进入导出、备份、诊断包、日志、截图或 Issue。
- 任何新增凭证来源必须说明读取路径、权限、生命周期、删除路径和失败降级方式，并补充测试。

## 信任边界

1. 内置探针会启动本机已安装的 CLI、读取用户配置文件或访问 Provider API；这是额度监控功能的一部分。
2. 用户自己安装到 `~/.smartquota/extensions/` 的脚本可能被执行；只安装信任的扩展，并检查其 manifest、路径和网络行为。
3. 用户配置的健康检查 URL 可能收到请求；不要配置包含 Token、Cookie 或私密路径的 URL。
4. OAuth `client_id` 或 Provider endpoint 可能出现在源码中；这不等于仓库包含维护者的私钥或用户凭证。
5. 第三方 Swift 包受各自许可证和上游安全政策约束；依赖清单和锁定版本见 [NOTICE](./NOTICE)。
6. GitHub Release、第三方 API 和用户本机 CLI 都可能返回错误、过期登录态或不完整数据；应用不能把外部成功响应当成绝对可信身份。

## 公共仓库红线

禁止提交：

- API Key、Token、Cookie、OAuth refresh token、Keychain dump、认证 JSON 和 `.env`。
- 真实邮箱、手机号、账号 ID、套餐、账单、额度、日志和屏幕截图。
- `.p12`、`.pem`、私钥、公证日志私密字段和 CI secret。
- 没有许可证/来源的图标、字体、截图、代码或生成资源。
- 未经核对的网络出口、自动更新、遥测、签名、公证和“安全审计通过”结论。

仓库使用 `scripts/check-open-source-docs.sh` 做本地和 CI 预检。该检查只报告文件名和规则，不打印疑似密钥内容；它不能代替人工安全审查、依赖上游公告审查或真实设备验证。

## 自查命令

在仓库根目录执行：

```bash
./scripts/check-open-source-docs.sh

# 检查默认 Mac 目标是否仍然没有启用 Sparkle
rg -n 'ENABLE_SPARKLE|Sparkle' Apps/Mac/Project.swift Apps/Mac/Tuist/Package.swift Apps/Mac/Sources

# 检查公开代码中的高风险凭证模式；不要把匹配内容粘到 Issue
rg -n '-----BEGIN (RSA|EC|OPENSSH|DSA|PRIVATE) PRIVATE KEY-----|ghp_|gho_|github_pat_' \
  Apps/Mac Apps/Windows Branding scripts --glob '!**/.build/**' || true

# 检查运行时配置没有被纳入版本控制
git ls-files | rg '(^|/)(auth\.json|settings\.json|\.env|.*\.p12|.*\.pem)$' || true
```

## 报告安全问题

请不要在公开 Issue、Discussion、PR 或截图中披露漏洞细节、真实凭证或用户数据。

优先使用仓库的 [GitHub Security Advisories](https://github.com/yancyfeng999-star/smartquota/security/advisories/new) 私密报告入口；如果该入口对你不可用，请通过维护者可见的私密 GitHub 渠道联系，并只提供脱敏的复现步骤、受影响版本、系统架构和最小必要日志。

报告中请说明：

- 受影响版本、构建号、macOS 版本和 Apple Silicon/Intel 架构。
- 可重复的最小步骤、影响范围和是否需要本地权限/已登录状态。
- 已采取的临时缓解措施；不要附加 Token、Cookie、Keychain 内容或完整用户路径。

本项目当前没有承诺固定响应 SLA；维护者会先确认影响范围，再决定修复、公告、回滚或要求升级。安全报告中的个人信息只用于处理问题，不应进入公开变更记录。

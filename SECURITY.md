# 智额 · SmartQuota — 安全说明

开源、本机运行的额度监控工具。**不向任何第三方上报用量、密钥或设备信息。**  
仓库中**不包含**任何真实用户账户、会员档位或 API 密钥。

## 审计结论（2026-08-04）

| 类别 | 结论 |
|------|------|
| 后门 / 隐蔽上报 | **未发现** |
| 远程自动更新 | **已移除**（不再链接 Sparkle；设置里可**手动**查 GitHub 公开 Release 版本，不自动下载安装） |
| 硬编码密钥 / 私有 token | **未发现**（测试仅用假数据） |
| 硬编码个人会员档位 | **已清空**（`defaultPlanLabels` 为空；套餐由用户本机填写） |
| 混淆 / 动态下载执行 | **未发现** |
| 网络出口 | 仅各 AI 厂商公开额度/OAuth API + 用户配置的扩展健康检查 |

## 网络会连哪里

应用**只**访问用于查额度 / 刷新用户自己 token 的官方端点，例如：

- OpenAI / ChatGPT usage、token refresh  
- Anthropic OAuth usage  
- xAI / Grok billing  
- Kimi、MiniMax、阿里云百炼、GitHub Copilot、Cursor、Gemini 等对应官方 API  
- 用户在「扩展」里配置的 **http(s)** 健康检查 URL  

**不会**连接：统计 SDK、Sentry/Firebase、作者自有服务器、Sparkle 更新 feed。  

可选：用户在设置中点击「检查更新」时，会请求 GitHub 公开 API（`api.github.com/repos/…/releases`）比对版本。若发现新版，优先下载 `.pkg` 到「下载」文件夹并**由本机一键静默安装**（展开 pkg + 覆盖 App，或在无写权限时用系统 `installer` 鉴权），然后自动重启。**不会**在后台无人点击时自动下载/安装；**不会**打开 Installer.app 向导（dmg 回退路径除外）。

本地 Hook 服务只监听 **`127.0.0.1`（loopback）**，接收 Claude Code 的 hook 事件。

## 本地读写

| 路径 | 用途 |
|------|------|
| `~/.smartquota/` | 本应用配置、扩展、主题（**勿提交进 git**） |
| Keychain（本 App） | GitHub / MiniMax / 阿里云等密钥 |
| `~/.claude/`、`~/.codex/`、`~/.grok/` 等 | **只读**读取各 CLI 已有登录态（查额度） |
| 浏览器 Cookie（可选） | 阿里云 / 部分探测在用户开启时读取 |
| `~/Library/Logs/SmartQuota/` | 本地日志，不上云 |

## 已加固项

1. **移除 Sparkle 依赖** — 不再嵌入自动更新框架，杜绝远程投毒更新包  
2. **收紧 entitlements** — 去掉 `allow-unsigned-executable-memory`、`disable-library-validation`  
3. **扩展脚本** — 只允许执行 `~/.smartquota/extensions/<id>/` 目录内脚本，禁止绝对路径逃逸  
4. **健康检查 / 自定义 Web 卡片** — 仅 `http`/`https`，拒绝 `file://`、`javascript:` 等  
5. **Info.plist** — `SUEnableAutomaticChecks = false`（即使将来误加 feed 也不会自动检查）  
6. **开源默认套餐** — 不在源码中写入个人会员名称或开通日  

## 你需要知道的信任边界

1. **内置探测代码**会启动本机已安装的 CLI（`claude`、`codex`、`kimi` 等）并解析输出 — 这是功能本身，不是后门。  
2. **用户自己放入** `~/.smartquota/extensions/` 的脚本会被执行；只安装你信任的扩展。  
3. **OAuth client_id**（Claude Code / Codex CLI 公开 client id）写死在代码里，用于刷新**用户自己的** token，不是维护者的密钥。  
4. **AWS SDK** 字符串中可能出现 `169.254.169.254`（实例元数据）— 来自 AWS SDK，本机 Mac 桌面通常不会用到。  
5. 第三方依赖（AWS SDK、SwiftTerm、Mockable、MenuBarExtraAccess、SweetCookieKit）为开源库；升级时请核对其发布渠道。

## 如何自查

```bash
# 二进制内嵌 URL
strings 智额.app/Contents/MacOS/智额 | grep -E 'https?://' | sort -u

# 不应再有 Sparkle.framework
ls 智额.app/Contents/Frameworks/

# 源码敏感模式
rg -n 'Sparkle|SUFeed|telemetry|mixpanel|sentry|firebase' Sources Project.swift Tuist

# 手动检查更新仅允许 GitHub 公开 API（不应出现作者私有更新服）
rg -n 'github.com|api.github.com' Sources/Domain Sources/Infrastructure/Update

# 确认没有把本机配置带进仓库
rg -n 'sk-[a-zA-Z0-9]{20,}|ghp_|gho_' --glob '!Tests/**' Sources scripts || true
```

## 报告安全问题

请通过 GitHub Security Advisory（若已启用）或仓库 Issues 私信维护者描述问题，**不要**在公开 issue 中粘贴真实密钥或账户信息。

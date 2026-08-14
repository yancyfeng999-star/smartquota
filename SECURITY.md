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

可选：用户在设置中点击「检查更新」时，会请求 GitHub 公开 API 比对版本。若发现新版，优先下载 `.pkg` 到「下载」文件夹，**本地解包 + 退出后 ditto 覆盖**（用户级替换，**不弹管理员密码**、不打开 Installer.app）。目标目录当前用户不可写时，仅在设置页显示错误，**不会**走 `sudo`/`osascript` 鉴权。日志：`~/Library/Logs/SmartQuota/update.log`。无后台无人点击自动更新。

本地 Hook 服务只监听 **`127.0.0.1`（loopback）**，接收 Claude Code 的 hook 事件。

## 本地读写

| 路径 | 用途 |
|------|------|
| `~/.smartquota/` | 本应用配置、扩展、主题（**勿提交进 git**） |
| `~/.smartquota/account-snapshots.json` | 账号额度快照缓存（权限 `0600`，原子写入） |
| Keychain（本 App） | GitHub / MiniMax / 阿里云等密钥 |
| Keychain（账号级） | `provider:<id>:account:<accountId>:api-key` 格式 |
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

---

## 生物识别安全

### 支持的认证方式

| 认证方式 | 说明 | 适用场景 |
|----------|------|----------|
| Touch ID | 指纹识别 | MacBook、Magic Keyboard |
| Face ID | 面容识别 | 不支持（macOS 限制） |
| 密码 | 系统密码回退 | 生物识别不可用时 |

### 密钥保护机制

- **Secure Enclave**：生物识别模板存储在设备安全芯片中，永不离开设备
- **Keychain 访问控制**：敏感密钥使用 `kSecAttrAccessControl` 保护
- **用户存在验证**：每次访问敏感密钥都需要用户交互

### 存储隔离

| 数据类型 | 存储位置 | 访问控制 | 删除时清理 |
|----------|----------|----------|------------|
| 生物识别模板 | Secure Enclave | 系统级保护 | 设备重置时 |
| API 密钥（普通） | Keychain | 应用级 | 删除账号时 |
| API 密钥（安全） | Keychain + 访问控制 | 生物识别 + 用户存在 | 删除账号时 |
| 认证状态 | 内存 | 应用级 | 应用关闭时 |

### 权限说明

| 权限 | 用途 | 拒绝后降级 |
|------|------|------------|
| 生物识别 | 访问敏感密钥 | 使用密码回退 |
| Keychain | 安全存储 | 使用普通存储 |

### 威胁模型

| 威胁 | 控制 | 残余风险 |
|------|------|----------|
| 设备解锁后未授权访问 | 生物识别验证 | 低 |
| 物理设备被盗 | Keychain 加密 + 生物识别 | 极低 |
| 绕过验证 | LocalAuthentication 框架 | 极低 |
| 密钥泄露 | 访问控制 + 加密 | 极低 |

---

## 多账号隐私边界

### 存储隔离

| 数据类型 | 存储位置 | 是否上传 | 删除时清理 |
|----------|----------|----------|------------|
| 邮箱 | `settings.json` | 否 | 删除账号时清理 |
| 额度快照 | `account-snapshots.json` | 否 | 删除账号时清理 |
| 账号配置（套餐、续费日） | `settings.json` | 否 | 删除账号时清理 |
| API Key / Token | Keychain（账号级） | 否 | 删除账号时清理 |
| OAuth 凭证 | 各工具自己的文件 | 否 | 智额不复制，无需清理 |

### 不等于托管多份 OAuth

智额**不**复制或托管 OAuth 登录凭证：

- OAuth、CLI、浏览器登录型会员只读取本机当前登录态
- 不创建 OAuth 文件副本
- 切换账号需在外部工具中操作
- 智额只记录检测到的邮箱或账号 ID

### 只有当前本机账号会刷新

- 后台刷新只更新当前本机登录的账号
- 其他账号保留最后一次成功快照
- 快照包含更新时间，用户可判断是否过期

### 历史快照不参与告警

- 未登录账号的快照仅作历史参考
- 过期快照不触发额度告警
- 只有 `signedIn` + `fresh` 的快照参与告警计算

### 账号删除流程

删除账号时，智额会清理：

1. `settings.json` 中的账号配置
2. `account-snapshots.json` 中的快照缓存
3. Keychain 中的账号级密钥（如有）

**不会**清理：

- 外部工具的登录态
- 其他账号的数据
- 应用全局设置

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

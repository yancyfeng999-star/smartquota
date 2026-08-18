# 智额 · 开发者文档

面向在本仓库上改功能、加会员、打包的人。仓库自有代码、文档和脚本采用 [Apache License 2.0](../LICENSE)；第三方依赖和资源边界见 [NOTICE](../NOTICE)。

---

## 1. 环境

| 依赖 | 说明 |
|------|------|
| macOS 15+ | 部署目标 |
| Xcode（完整） | 含 Command Line Tools 不够时请装完整 IDE |
| Tuist | `brew install tuist` 或官方安装方式 |
| Swift 6 | 与工程一致 |

```bash
cd Apps/Mac   # 或你的克隆路径
tuist generate
open SmartQuota.xcworkspace
```

---

## 2. 构建与运行

```bash
# 调试包 → 桌面 智额.app
Apps/Mac/scripts/build-test-app.sh

# Release
CONFIG=Release Apps/Mac/scripts/build-test-app.sh
```

Scheme：`SmartQuota`（产物显示名「智额」）。

当前 Mac 发布版本：`0.3.30`（build `33`）。版本号唯一来源：`Sources/App/Info.plist`；对应 Release：[v0.3.30](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.30)

- `CFBundleShortVersionString`：用户可见版本（如 `0.2.0`）  
- `CFBundleVersion`：构建号（如 `2`）

---

## 3. 架构

三层（详见 [architecture/ARCHITECTURE.md](./architecture/ARCHITECTURE.md)）：

```text
App (SwiftUI)
  │  直接消费 Domain，无独立 ViewModel 层
  ▼
Domain
  │  QuotaMonitor（SSoT）、AIProvider、UsageSnapshot…
  ▼
Infrastructure
     Probe、JSONSettings、Keychain、网络、CLI
```

要点：

- **`QuotaMonitor`**：刷新、启用状态、选中会员；`@MainActor` + `@Observable`  
- **`ProviderCatalog`**（App）：注册全部内置 Provider  
- **`ProviderConfigRegistry`**（App）：设置页「额度检测」卡片映射  
- **`L10n` / `AppLanguage`**：运行时多语言  
- **`JSONSettingsRepository`**：`~/.smartquota/settings.json`  
- **`KeychainSecretStore`**：敏感密钥

### 开源与依赖治理

- `Apps/Mac/Tuist/Package.swift` 是直接依赖声明，`Apps/Mac/Tuist/Package.resolved` 是提交到仓库的解析锁文件。
- 依赖、传递依赖、许可证和上游链接必须登记在根目录 `NOTICE`；新增或升级依赖不能只改 `Package.swift`。
- 仓库自有代码/文档/脚本使用 Apache-2.0，不覆盖第三方包、字体、图标、截图、商标或用户连接的第三方服务。
- 新增资源必须在 PR 中提供来源和许可证证据；无法确认许可的资源不得进入源码或 Release。
- 提交前从仓库根目录运行 `./scripts/check-open-source-docs.sh`；它会检查公开入口、相对链接、锁文件、NOTICE、版本、邮箱样式文件名和高置信度凭证模式。

### 关键 App 文件

| 路径 | 职责 |
|------|------|
| `SmartQuotaApp.swift` | 入口、组装 catalog、monitor |
| `ProviderCatalog.swift` | 内置会员列表与默认套餐名 |
| `Views/MenuContentView.swift` | 主菜单 |
| `Views/MenuChromeComponents.swift` | 菜单子组件 |
| `Views/SettingsView.swift` | 设置组装 |
| `Views/Settings/*` | 各配置卡、会员开关、语言、检测区 |
| `Localization/*` | 语言枚举与词表 |

---

## 4. 添加一个内置会员

1. **Domain**
   - `Sources/Domain/Provider/<Name>/<Name>Provider.swift` 实现 `AIProvider`

2. **Infrastructure**
   - `Sources/Infrastructure/<Name>/<Name>UsageProbe.swift` 实现 `UsageProbe`
   - 凭证只读本机文件 / 环境变量 / Keychain（经 repository）

3. **注册**
   - `ProviderCatalog.makeAllProviders` 增加实例
   - `displayOrder`；`defaultPlanLabels` 在开源树中保持 **空字典**（勿写入个人套餐名）
   - 若需专用设置表单：写 `XxxConfigCard`，并在 `ProviderConfigRegistry` 增加 `case`
   - 否则走 `GenericProbeConfigCard` + `ProviderProbeGuide`

4. **文案**
   - `L10n` 增加 `probe.<id>.title/summary/step.*`
   - 配置表单字符串用 `L10n.shared.t("config....")`

5. **图标**（可选）
   - `Assets.xcassets` + `ProviderVisualIdentity`

6. **测试**
   - Probe 解析单测放 `Tests/InfrastructureTests`
   - Domain 行为放 `Tests/DomainTests`

默认启用策略：非核心会员若 settings 中 **从未写过** `isEnabled`，启动时置为 `false`（见 `ProviderCatalog.applyExpandedProviderDefaults`）。

---

## 4.1 多账号接入

每个 Provider 可选择接入多账号支持。接入方式取决于身份识别能力：

### 自动身份识别（推荐）

适用于能从 CLI/API 返回邮箱或账号 ID 的 Provider：

1. 在 Probe 中解析 `accountEmail` 或 `externalAccountId`
2. 在 `UsageSnapshot` 中填充身份字段
3. `ProviderAccountCoordinator` 自动处理账号发现和匹配

**示例：** Codex 从 JWT `id_token` 解析邮箱，Claude 从 `~/.claude.json` 读取。

### 手动密钥型

适用于需要用户手动输入 API Key 的 Provider：

1. 实现 `MultiAccountSettingsRepository` 的账号级密钥存储
2. Keychain 键格式：`provider:<id>:account:<accountId>:api-key`
3. 用户添加账号时填写邮箱和密钥
4. 验证成功后保存

**示例：** MiniMax API Key、Copilot PAT。

### Profile/路径型

适用于使用配置文件或 Profile 的 Provider：

1. 保存 Profile 名称或配置路径（非敏感）
2. 如果数据源无邮箱，要求用户填写
3. 使用 Profile 名作为身份标识

**示例：** AWS Bedrock Profile、Z.ai 配置路径。

### 接入清单

| 步骤 | 说明 |
|------|------|
| 1. 实现身份解析 | 在 Probe 或 CredentialLoader 中提取邮箱/ID |
| 2. 填充 UsageSnapshot | 设置 `accountEmail`、`accountExternalId` |
| 3. 选择接入方式 | 自动身份 / 手动密钥 / Profile |
| 4. 测试 | 添加账号发现、邮箱匹配、删除清理测试 |
| 5. 更新文档 | 在 Provider 接入矩阵中记录 |

详见 `docs/superpowers/plans/2026-08-10-multi-account-memberships.md`。

### Provider 接入矩阵

| Provider | 添加方式 | 自动身份 | 无法识别时 |
|----------|----------|----------|------------|
| Codex | 切换 CLI 登录后检测 | JWT `id_token` 邮箱 | 用户确认邮箱 |
| Kimi | CLI/浏览器切换或手动 Key | 尝试接口身份 | 手动邮箱 |
| MiniMax | 手动添加 API Key | 接口可返回则使用 | 必填邮箱 |
| Grok | 切换 Grok 登录后检测 | 认证文件已有邮箱 | 手动邮箱 |
| Claude | 切换 Claude Code 登录 | `~/.claude.json` 邮箱 | 手动邮箱 |
| Gemini | 切换 Gemini CLI 登录 | OAuth 身份若可得 | 手动邮箱 |
| Copilot | 手动 PAT + GitHub 用户名 | GitHub 用户名 | 用户填写邮箱 |
| Cursor | 切换 Cursor 客户端账号 | JWT `userId` | 首次关联邮箱 |
| Antigravity | 切换客户端账号 | `userStatus.email` | 手动邮箱 |
| Z.ai | 手动 Key/配置路径 | 接口可返回则使用 | 手动邮箱 |
| Bedrock | 选择 AWS Profile | Profile/AWS Account ID | Profile 作为身份 |
| Alibaba | 切换浏览器或手动 Key/Cookie | 账号接口若可得 | 手动邮箱 |
| MiMo | 切换浏览器或手动 Cookie | Cookie 中 `userId` | 首次关联邮箱 |
| AmpCode | 切换 CLI 登录 | `Signed in as` 邮箱 | 手动邮箱 |
| Kiro | 切换 CLI 登录 | 当前输出若可得 | 手动邮箱 |
| Mistral | 独立日志目录 | 无稳定邮箱 | 手动绑定目录 |
| OpenCode Go | 独立数据库/当前登录 | 数据库身份若可得 | 手动绑定 |
| OMP | 保留现有多账号分组 | 输出中的 email/accountId | 不重复建立子账号 |

---

## 5. 用户扩展（脚本）

路径：`~/.smartquota/extensions/`  

manifest + 探测脚本，由 `ExtensionRegistry` 加载进 `QuotaMonitor`。示例见 `docs/features/extensions/`。

---

## 6. 多语言

- 词表：`Sources/App/Localization/L10n.swift`（字典表，运行时切换）  
- 语言码：`AppLanguage`（`zh-Hans`、`en`、`ja`…）  
- 持久化：`app.language` → `settings.json`  
- 缺失译文：目标语言 → **en** → **zh-Hans** → raw key  
- DEBUG 启动会检查缺中文的 key  

新增 UI 字符串请走 `L10n.shared.t("…")`，避免硬编码中英文。

设置注入：

```swift
// 菜单根
.appSettings(settings)

// 子视图
@Environment(\.appSettings) private var settings
```

需要 `Toggle`/`Picker` 的 `$settings` 绑定时，可用 `@State private var settings = AppSettings.shared`（与 singleton 同一实例）。

---

## 7. 密钥与设置

| 数据 | 存储 |
|------|------|
| 主题、语言、开关、探测模式、套餐/续费 | `~/.smartquota/settings.json` |
| 账号配置（邮箱、备注、套餐、续费日） | `~/.smartquota/settings.json`（`providers.<id>.accounts`） |
| 账号额度快照 | `~/.smartquota/account-snapshots.json`（权限 `0600`） |
| GitHub Token、MiniMax Key、阿里云 Cookie/Key | Keychain（`KeychainSecretStore`） |
| 账号级密钥 | Keychain（`provider:<id>:account:<accountId>:api-key`） |
| Codex/Grok/Kimi 等 OAuth | 各工具自己的 `~/.xxx/auth.json` 等 |

**禁止**把真实密钥提交进仓库。

### 多账号存储边界

- **邮箱**：仅保存在 `settings.json`，不上传
- **额度快照**：保存在 `account-snapshots.json`，原子写入，损坏时安全降级
- **Keychain 密钥**：按 `providerId + accountId` 隔离，删除账号时同步清理
- **普通设置**：套餐、续费日等改为账号级配置，保存在 `settings.json`

---

## 8. 测试

```bash
# 示例：Domain 产品默认
xcodebuild -workspace SmartQuota.xcworkspace -scheme Domain \
  -destination 'platform=macOS' test \
  -only-testing:DomainTests/SmartQuotaProductDefaultsTests
```

也可在 Xcode 中跑 `Domain` / `Infrastructure` / `AcceptanceTests` scheme。

仓库治理检查：

```bash
cd ../..
./scripts/check-open-source-docs.sh
git diff --check
```

无 UI 的四家 live 探测：

```bash
python3 scripts/probe_four_providers.py
```

---

## 9. 品牌与打包

- 显示名：智额  
- Bundle ID：工程内 `com.smartquota.app`（以 Tuist/`Project.swift` 为准）  
- Logo：`Branding/` 与 `Assets.xcassets`  
- 正式分发：Release 构建 + 可选 Developer ID 签名/公证（见 [DISTRIBUTION.md](./DISTRIBUTION.md)）  

当前默认 Mac Tuist 目标不启用 Sparkle；正常公开构建使用用户主动触发的 GitHub Release 检查路径。源码仍保留 `#if ENABLE_SPARKLE` 条件代码，除非完成单独的更新、签名、回退和隐私审查，否则不得启用该编译条件。

---

## 10. 提交与协作建议

- 改 provider 行为时补单测（解析、默认 enabled）  
- 大 UI 文件继续按「一卡一文件 / 一场景一文件」拆分  
- 用户可见字符串进 L10n  
- 勿提交密钥、本机 `settings.json` 或个人会员信息（见 [CONTRIBUTING.md](../CONTRIBUTING.md)）  

---

## 11. 相关文档

- [USER_GUIDE.md](./USER_GUIDE.md)  
- [../PRODUCT.md](../PRODUCT.md)  
- [architecture/ARCHITECTURE.md](./architecture/ARCHITECTURE.md)  

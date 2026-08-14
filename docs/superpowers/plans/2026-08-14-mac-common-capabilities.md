# 智额 Mac 通用能力建设实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为智额补齐与具体 AI 会员无关的 Mac 产品底座，让用户可以安全地首次使用、刷新、诊断、迁移、更新、恢复和维护应用，同时保持本机优先与不上传敏感数据的产品原则，并建立可公开维护、可复核的文档、许可证和第三方归属基线。

**Architecture:** 复用现有 `SmartQuotaApp`、`AppSettings`、`QuotaMonitor`、`StatusItemLabelDriver`、`JSONSettingsStore`、`GitHubReleaseChecker` 和 `FileLogger`，新增小型的 Support/Recovery/Transfer 能力层。所有基础能力通过明确的 Domain 接口与 Infrastructure 实现隔离，SwiftUI 只负责状态展示和用户操作。刷新、诊断、迁移、备份和更新均使用可取消、可测试的服务，不把逻辑继续堆入 `SettingsView.swift`。

**Tech Stack:** Swift 6、SwiftUI、Observation、Tuist、macOS 15+、`xcodebuild`、Swift Testing、JSON 本地存储、Keychain、LocalAuthentication、UserNotifications、GitHub Releases API、`SMAppService`。

## Global Constraints

- 本计划只覆盖 `Apps/Mac`，不修改 Windows，不改变具体 Provider 的额度算法。
- 默认 `local-only`：设置、账号备注、缓存和诊断均留在本机；不得上传密钥、Cookie、OAuth 文件、完整邮箱、原始日志或额度明细。
- 智额是公开开源仓库：仓库自有代码、文档、脚本、示例数据、品牌素材和发布物必须明确许可证与归属；第三方代码、依赖、商标、截图和服务条款不得被误写成 MIT 内容。
- `LICENSE` 是仓库自有代码和文档授权的主入口；根据已确认的发布决策采用 Apache-2.0，不引入未定义的 CLA 或额外授权条件。
- `NOTICE` 必须以实际依赖清单、锁定版本、打包内容和品牌/商标使用情况为依据；不能只凭记忆手写依赖许可，也不能遗漏随 App 发布的第三方组件或资源。
- 导出和备份使用显式 allowlist；任何未列入 allowlist 的字段不得进入导出文件。
- 导出、备份、迁移和恢复都不得包含 API Key、Token、Cookie、密码、Keychain 内容或认证文件原文。
- 同一时间不强制并发刷新多个账号；账号读不到时保留最后快照，显示“未登录”；网络失败显示“连接失败”，不能混淆。
- 更新默认仍由用户主动触发；P2 自动更新必须单独开关、可暂停、可回退，不能默认开启。
- 任何失败操作都必须保留用户原数据；写入采用临时文件 + 原子替换，迁移前先生成备份。
- 兼容旧版本 `~/.smartquota/settings.json`、旧账号配置和旧 Keychain 命名；未知 JSON 字段必须保留。
- 所有新的用户可见文字进入 `L10n.swift`，至少覆盖简体中文和 English，不能在 SwiftUI 视图中散落硬编码文案。
- 本计划执行时保留现有工作区未提交改动；实现前先重新检查 `git status --short`，不得用恢复、重置或批量格式化覆盖用户文件。
- 本计划文件本次只作为规划交付，不授权提交源码、上传 GitHub、创建 Release 或安装到 `/Applications`。

---

## 1. 当前基线与边界

### 1.1 已确认的现有能力

当前源码和文档已经包含以下基础：

- `SmartQuotaApp` + `AppDelegate` 提供菜单栏常驻、Accessory 应用行为和关闭窗口不退出。
- `AppSettings` 已接入主题、语言、额度显示、会员排序、后台刷新、告警阈值和 `SMAppService` 登录时启动。
- `JSONSettingsStore` 使用 `~/.smartquota/settings.json`，支持点号路径、线程锁和原子写入。
- `FileLogger` 写入 `~/Library/Logs/SmartQuota/SmartQuota.log`，有大小轮换和打开日志入口。
- `SystemAlertSender`、`NotificationAlerter` 已支持系统通知、额度阈值和重复告警抑制。
- `GitHubReleaseChecker`、`ReleaseDownloader`、`SilentPkgInstaller` 已支持手动检查、版本比较、PKG 优先下载和退出后覆盖安装。
- `KeychainSecretStore`、`SecureKeychainStore`、`BiometricAuthManager` 已存在，但需要确认所有 Provider 的真实凭证路径是否统一接入。
- `StatusItemLabelDriver` 和 `SystemPowerStateProvider` 已有刷新生命周期、唤醒和菜单栏展示相关逻辑。
- 已有多账号、缓存、Provider 配置和验收测试基础，基础能力不能破坏“读不到保留旧快照”的规则。

### 1.2 当前需要特别处理的现状

- `SettingsView.swift` 已包含更新、日志和登录时启动入口，新增能力应拆成独立子视图或服务，避免继续膨胀。
- 更新源码已经具备 PKG 静默安装路径，但用户手册部分仍描述为下载 DMG 后手动拖入 Applications；实现和文案必须统一。
- `AppSettings` 和 `JSONSettingsRepository` 已有 `receiveBetaUpdates` 字段，但更新筛选、Release API 和设置 UI 需要形成完整闭环。
- `SecureKeychainStore` 已支持带访问控制的保存/读取，但 Keychain 项的生物识别要求目前存在内存态记录，不能把它直接当成跨重启的完整策略存储。
- 当前版本信息在 README、PROJECT_STATUS 和部分产品文档中存在不同步，计划执行前需要以 `Info.plist` 为版本唯一来源，再更新文档。
- 根目录已有 `README.md`、`LICENSE`、`NOTICE`、`SECURITY.md`、`CONTRIBUTING.md` 和 `docs/README.md`，执行时以“审计、补齐、互相校验”为目标，不重复创建同名文件，也不把文件存在误认为内容已经合格。
- 当前工作区有用户未提交改动。本计划不把这些改动当作本计划实现，也不在本轮清理它们。

### 1.3 不在本计划范围

- 新增或重写具体会员 Provider、额度解析和计费算法。
- 官方账号体系、云同步、多设备同步、云端备份。
- 导出或备份 API Key、Cookie、OAuth 凭证、Keychain 数据。
- 默认后台静默自动更新。
- 在没有明确服务、隐私政策和用户同意前接入崩溃上报或匿名遥测。
- Windows 功能对齐、App Store 上架、Apple Developer ID 公证的独立发布工作。

---

## 1.4 用户需求覆盖映射

| 用户提出的功能 | 计划任务 |
|---|---|
| 首次启动引导 | Task 2 |
| 手动刷新 | Task 3 |
| 诊断中心 | Task 4 |
| 安全的数据导出/导入 | Task 5 |
| 全局备份与恢复 | Task 1、Task 5 |
| 兼容性提示 | Task 2、Task 8 |
| 无障碍支持 | Task 9 |
| 更新说明展示 | Task 6 |
| 崩溃或异常恢复 | Task 7 |
| 数据迁移机制 | Task 1、Task 8 |
| 应用内帮助 | Task 9 |
| 性能保护 | Task 10 |
| Beta 更新通道 | Task 11 |
| 自动更新开关 | Task 12 |
| 崩溃报告和匿名诊断上报 | Task 13 |

## 1.5 开源仓库文档、许可证与公开治理要求

### 1.5.1 已有公开文件与本计划的处理方式

当前仓库已经存在以下公开入口：

- `README.md`：项目介绍、隐私原则、功能入口、文档导航和许可证链接。
- `LICENSE`：当前为 Apache License 2.0。
- `NOTICE`：第三方 Swift 包、商标和本地隐私边界声明。
- `SECURITY.md`：安全/隐私边界、网络出口、本地存储和漏洞报告说明。
- `CONTRIBUTING.md`：开发流程、隐私红线、Pull Request 和贡献授权说明。
- `docs/README.md`：用户、开发者、发布和架构文档索引。
- `.github/workflows/`：现有构建、测试和发布工作流。

本计划不把“文件已存在”视为完成条件。执行时要逐份核对链接、版本、功能描述、隐私承诺和许可证范围，并只补充有证据的内容。

### 1.5.2 必须达到的开源标准

1. **许可证边界清晰**
   - `LICENSE` 保持完整、可读的 Apache License 2.0 正文，并写明实际版权归属主体；代码、文档和脚本的授权范围不得与 README 或贡献指南矛盾。
   - `README.md`、`docs/README.md`、`CONTRIBUTING.md` 和发布说明都能直接链接到 `LICENSE` 和 `NOTICE`。
   - 贡献代码的授权方式与 `CONTRIBUTING.md` 一致；当前不设置未定义的 CLA、商业附加条款或“提交即转让全部权利”的隐含表述。
   - 第三方代码、生成文件、图标、字体、截图、示例数据和品牌名称逐项标注来源、许可证或使用限制；无法确认来源的内容不得进入发布包。

2. **第三方依赖和 NOTICE 可复核**
   - 依赖来源以 `Apps/Mac/Tuist/Package.swift`、`Apps/Mac/Tuist/Package.resolved`、实际构建产物和仓库资源为准。
   - `NOTICE` 至少记录组件名称、锁定版本或版本范围、来源 URL、许可证类型、随包分发时的归属要求和用途；不能只列项目名而不说明许可来源。
   - 对依赖升级、移除和新增建立核对步骤；如果上游许可证、版权声明或商标要求变化，先更新 `NOTICE` 和发布说明，再合并代码。
   - 不把 ChatGPT、Claude、Gemini、Copilot、Cursor、Grok、Kimi、MiniMax 等产品名称写成智额的资产；公开文案必须保留“非官方、无隶属关系”的说明。

3. **README 是可独立阅读的项目入口**
   - 说明智额解决的问题、支持的平台和最低系统要求、当前能力边界、快速开始/构建方法、隐私模型、更新方式、已知限制、许可证、第三方声明、贡献入口和安全报告入口。
   - 明确“开源的是仓库代码和文档”与“用户连接的 AI 服务仍受其自身账号、服务条款和隐私政策约束”之间的区别。
   - 不在公开文档中写入真实邮箱、账号、套餐、额度、Cookie、Token、API Key、私有更新地址或未验证的签名/公证结论。
   - 下载、安装、手动检查更新和发布资产的说明必须与 `docs/USER_GUIDE.md`、`docs/DISTRIBUTION.md`、GitHub Release 实际流程一致。

4. **贡献和安全流程可执行**
   - `CONTRIBUTING.md` 明确本地环境、生成工程、测试命令、改动范围、PR 内容、隐私红线、假数据规则、依赖许可检查和文档同步要求。
   - `SECURITY.md` 明确威胁边界、本机数据与网络出口、敏感信息处理、支持版本、漏洞报告渠道、不要公开提交凭证以及维护者响应边界；不能承诺仓库没有证据支持的安全结论。
   - `.github` 中的 Issue/PR 模板（如仓库尚未配置则补齐）要求提交复现环境、版本、脱敏日志和许可证/依赖变更信息，不允许收集真实凭证。
   - 不把公开 Issue 当作秘密披露渠道；安全问题、用户数据问题和普通功能问题分别进入不同流程。

5. **文档有唯一来源和发布校验**
   - 版本号以 `Apps/Mac/Sources/App/Info.plist` 的 `CFBundleShortVersionString`、`CFBundleVersion` 为唯一来源；README、`PRODUCT.md`、`PROJECT_STATUS.md`、`CHANGELOG.md`、用户手册和发布说明不得各自维护相互冲突的版本事实。
   - 每个新功能在代码、测试、用户文档、开发文档、隐私/安全文档和 CHANGELOG 中分别记录适用内容；未实现、未验证、仅本地测试或未发布的能力必须明确标注状态。
   - 通过脚本检查必需文件、相对链接、许可证入口、敏感信息模式、NOTICE 依赖清单和文档版本同步；检查失败不得进入 Release。
   - 发布前同时保留“源码/文档校验”“构建/打包校验”“签名/公证校验”“安装/运行时校验”四类证据，不能用代码已合并替代发布已完成。


---

## 2. 目标用户流程与统一状态模型

### 2.1 首次启动流程

```text
首次打开
  → 说明智额是什么
  → 说明本机优先和隐私边界
  → 检查系统兼容性
  → 引导选择第一个会员
  → 引导完成检测配置
  → 执行一次手动检测
  → 显示结果和下一步
```

允许用户跳过，但跳过后必须保留“继续设置”入口；关闭引导不应导致应用退出。首次启动状态只保存是否完成步骤，不保存任何密钥。

### 2.2 刷新状态

统一使用以下状态，避免每个视图自己定义一套 loading/error 文案：

```swift
public enum RefreshScope: Sendable, Equatable {
    case provider(String)
    case allEnabledProviders
}

public enum RefreshState: Sendable, Equatable {
    case idle
    case running(scope: RefreshScope, startedAt: Date)
    case cancelling
    case completed(successCount: Int, failureCount: Int)
    case cancelled(completedCount: Int)
    case failed(message: String)
}
```

刷新规则：

- 当前会员刷新只触发当前会员的当前本机账号探测。
- 全部刷新按已开启会员顺序执行，使用受控并发；默认不并发同一会员的多个账号。
- 用户可以取消；取消后已完成的结果保留，未执行的任务不启动。
- 成功更新账号状态、额度快照和更新时间。
- 读不到本机登录态时保留旧快照并显示“未登录”。
- 网络或服务错误保留旧快照并显示“连接失败”。
- 任何刷新都不能把旧账号替换成新账号，也不能因为一次失败清空历史数据。

### 2.3 诊断结果

```swift
public enum DiagnosticSeverity: String, Codable, Sendable {
    case ok
    case info
    case warning
    case error
}

public enum DiagnosticCheckKind: String, Codable, Sendable {
    case operatingSystem
    case architecture
    case providerEnabled
    case cliInstalled
    case credentialAvailable
    case keychainAccess
    case networkReachability
    case providerEndpoint
    case cacheFreshness
    case notificationPermission
    case appWritable
}

public struct DiagnosticResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerId: String?
    public let kind: DiagnosticCheckKind
    public let severity: DiagnosticSeverity
    public let title: String
    public let detail: String
    public let suggestedAction: String?
    public let checkedAt: Date
}
```

诊断只显示脱敏后的路径和错误，不显示完整邮箱、Token、Cookie、Keychain 内容或原始响应。

---

## 3. 文件与模块规划

### 3.1 Domain 层

创建或修改以下文件：

- Create: `Apps/Mac/Sources/Domain/Support/FirstLaunchState.swift` — 首次启动步骤和完成状态。
- Create: `Apps/Mac/Sources/Domain/Support/RefreshScope.swift` — 当前会员/全部会员刷新范围。
- Create: `Apps/Mac/Sources/Domain/Support/RefreshState.swift` — 刷新状态机。
- Create: `Apps/Mac/Sources/Domain/Support/DiagnosticModels.swift` — 诊断等级、检查项和结果。
- Create: `Apps/Mac/Sources/Domain/Support/PortableSettings.swift` — 导出/导入 allowlist 和 schema。
- Create: `Apps/Mac/Sources/Domain/Support/BackupManifest.swift` — 本地备份清单、时间、版本和校验信息。
- Create: `Apps/Mac/Sources/Domain/Support/CompatibilityReport.swift` — 系统、架构、CLI、权限和可写性检查结果。
- Create: `Apps/Mac/Sources/Domain/Support/AppRecoveryState.swift` — 正常退出、异常退出和安全模式状态。
- Create: `Apps/Mac/Sources/Domain/Support/SettingsMigration.swift` — schema 版本和迁移步骤协议。
- Modify: `Apps/Mac/Sources/Domain/Update/ManualUpdate.swift` — 更新渠道、Release 说明、最低系统版本和安装动作所需的模型。

### 3.2 Infrastructure 层

- Create: `Apps/Mac/Sources/Infrastructure/Support/FirstLaunchStore.swift` — 首次启动状态本地持久化。
- Create: `Apps/Mac/Sources/Infrastructure/Support/RefreshCoordinator.swift` — 串联刷新、取消、进度、错误和结果聚合。
- Create: `Apps/Mac/Sources/Infrastructure/Support/DiagnosticsService.swift` — 运行诊断检查并生成脱敏结果。
- Create: `Apps/Mac/Sources/Infrastructure/Support/SettingsTransferService.swift` — 导出、预览、校验和导入非敏感配置。
- Create: `Apps/Mac/Sources/Infrastructure/Support/BackupManager.swift` — 自动备份、备份列表、恢复、校验和失败回滚。
- Create: `Apps/Mac/Sources/Infrastructure/Support/CompatibilityChecker.swift` — 系统和运行环境兼容性检查。
- Create: `Apps/Mac/Sources/Infrastructure/Support/CrashRecoveryStore.swift` — 启动心跳、正常退出标记和安全模式判定。
- Create: `Apps/Mac/Sources/Infrastructure/Support/SettingsMigrationRunner.swift` — 迁移前备份、逐版本迁移、校验和回滚。
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsStore.swift` — 接入 schema 版本、迁移前快照和损坏文件保护。
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsRepository.swift` — 暴露基础设置、导出 allowlist 和恢复入口。
- Modify: `Apps/Mac/Sources/Infrastructure/Update/GitHubReleaseChecker.swift` — 读取 Release 说明、最低系统要求和更新渠道。
- Modify: `Apps/Mac/Sources/Infrastructure/Update/ReleaseDownloader.swift` — 下载大小限制、取消、临时文件清理和资产校验。
- Modify: `Apps/Mac/Sources/Infrastructure/Update/SilentPkgInstaller.swift` — 安装前版本检查、安装失败日志和恢复提示。
- Modify: `Apps/Mac/Sources/Infrastructure/Logging/FileLogger.swift` — 统一脱敏规则和诊断包导出接口。
- Modify: `Apps/Mac/Sources/Infrastructure/Notifications/SystemAlertSender.swift` — 通知权限状态和测试通知入口。
- Modify: `Apps/Mac/Sources/Infrastructure/Shared/SystemPowerStateProvider.swift` — 与刷新协调器对接睡眠/唤醒暂停策略。

### 3.3 App 层

- Create: `Apps/Mac/Sources/App/Views/Onboarding/OnboardingView.swift` — 首次启动引导。
- Create: `Apps/Mac/Sources/App/Views/Onboarding/PrivacyBoundaryView.swift` — 本机优先和隐私说明。
- Create: `Apps/Mac/Sources/App/Views/Support/DiagnosticsCenterView.swift` — 诊断结果、重试和配置引导。
- Create: `Apps/Mac/Sources/App/Views/Support/HelpCenterView.swift` — FAQ、日志、会员配置和隐私帮助。
- Create: `Apps/Mac/Sources/App/Views/Support/CompatibilityView.swift` — 系统兼容性报告。
- Create: `Apps/Mac/Sources/App/Views/Support/UpdateDetailsView.swift` — 新版本说明和安装动作。
- Create: `Apps/Mac/Sources/App/Views/Support/SettingsTransferView.swift` — 导入导出预览和确认。
- Create: `Apps/Mac/Sources/App/Views/Support/BackupRestoreView.swift` — 本地备份列表和恢复。
- Create: `Apps/Mac/Sources/App/Views/Recovery/SafeModeView.swift` — 安全模式恢复操作。
- Modify: `Apps/Mac/Sources/App/SmartQuotaApp.swift` — 首次启动、恢复状态、刷新协调器和安全模式路由。
- Modify: `Apps/Mac/Sources/App/Views/MenuContentView.swift` — 当前会员刷新、全部刷新、取消、刷新状态展示。
- Modify: `Apps/Mac/Sources/App/Views/SettingsView.swift` — 仅组装子视图，不继续增加大型业务逻辑。
- Modify: `Apps/Mac/Sources/App/Settings/AppSettings.swift` — 新增首次启动、更新渠道、备份和诊断设置的观察状态。
- Modify: `Apps/Mac/Sources/App/Localization/L10n.swift` — 所有新文案的中文/英文及 RTL 文案。
- Modify: `Apps/Mac/Sources/App/Theme/` — 动态字体、减少动画、高对比度和无障碍颜色适配。

### 3.4 测试与文档

- Create: `Apps/Mac/Tests/DomainTests/Support/FirstLaunchStateTests.swift`
- Create: `Apps/Mac/Tests/DomainTests/Support/RefreshStateTests.swift`
- Create: `Apps/Mac/Tests/DomainTests/Support/PortableSettingsTests.swift`
- Create: `Apps/Mac/Tests/DomainTests/Support/CompatibilityReportTests.swift`
- Create: `Apps/Mac/Tests/DomainTests/Support/AppRecoveryStateTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Support/RefreshCoordinatorTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Support/DiagnosticsServiceTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Support/SettingsTransferServiceTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Support/BackupManagerTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Support/SettingsMigrationRunnerTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Update/ReleaseNotesTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Recovery/CrashRecoveryStoreTests.swift`
- Modify: `Apps/Mac/Tests/AcceptanceTests/UpdatesSpec.swift` — 更新说明、下载前用户确认、失败状态。
- Modify: `Apps/Mac/Tests/AcceptanceTests/RefreshSpec.swift` — 当前会员、全部会员、取消和部分失败。
- Modify: `Apps/Mac/Tests/AcceptanceTests/NotificationsSpec.swift` — 权限、阈值、去重和测试通知。
- Create: `Apps/Mac/Tests/AcceptanceTests/OnboardingSpec.swift`
- Create: `Apps/Mac/Tests/AcceptanceTests/DiagnosticsSpec.swift`
- Create: `Apps/Mac/Tests/AcceptanceTests/SettingsTransferSpec.swift`
- Create: `Apps/Mac/Tests/AcceptanceTests/RecoverySpec.swift`
- Create: `Apps/Mac/Tests/AcceptanceTests/AccessibilitySpec.swift`
- Modify: `docs/README.md`、`docs/USER_GUIDE.md`、`docs/DEVELOPER.md`、`docs/DISTRIBUTION.md`、`docs/REPO_LAYOUT.md` — 文档索引、首次启动、诊断、导入导出、恢复、更新、开发、发布和仓库结构说明。
- Modify: `README.md`、`LICENSE`、`NOTICE`、`SECURITY.md`、`CONTRIBUTING.md` — 开源入口、许可证边界、依赖归属、隐私红线和贡献/安全流程校准。
- Modify: `PRODUCT.md`、`PROJECT_STATUS.md`、`CHANGELOG.md` — 功能状态、版本来源和公开变更记录；仅在实际实现和验证后更新。
- Create or modify: `.github/ISSUE_TEMPLATE/bug-report.yml`、`.github/ISSUE_TEMPLATE/feature-request.yml`、`.github/PULL_REQUEST_TEMPLATE.md` — 若不存在则创建，若已有则按隐私和开源流程补齐。
- Modify: `.github/workflows/tests.yml` — Pull Request 和主分支测试前执行公开文档、许可证和敏感信息检查。
- Modify: `.github/workflows/release.yml` — 正式构建/发布前执行同一检查，并阻断未完成文档或 NOTICE 核对的 Release。
- Create: `scripts/check-open-source-docs.sh` — 检查必需公开文件、相对链接、许可证入口、版本一致性和敏感信息红线。

---

## 4. P1 实施阶段

### Task 0: 冻结基线、需求合同和测试夹具

**Files:**
- Read: `README.md`
- Read: `PRODUCT.md`
- Read: `PROJECT_STATUS.md`
- Read: `Apps/Mac/Project.swift`
- Read: `Apps/Mac/Sources/App/Info.plist`
- Read: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsStore.swift`
- Read: `Apps/Mac/Sources/Infrastructure/Update/ManualUpdate.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Settings/JSONSettingsStoreTests.swift`

**Interfaces:**
- Produces: 当前版本、设置路径、既有字段、测试命令和工作区差异清单，供后续每个任务使用。

- [ ] 记录实现开始前的 `git status --short`，将现有用户改动列为保留项。
- [ ] 以 `Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 作为版本唯一来源，记录 README/PRODUCT/PROJECT_STATUS 的不同步项。
- [ ] 固定测试数据目录使用临时目录，不读写用户真实 `~/.smartquota`。
- [ ] 为后续测试准备包含旧字段、未知字段、损坏 JSON 和空文件的 fixture。
- [ ] 写出 P1 验收清单：首次启动、刷新、诊断、导出导入、备份恢复、兼容性、无障碍、更新说明、异常恢复、迁移、帮助、性能。
- [ ] 运行现有 Mac 全量测试，记录测试数量和失败项；不能把旧运行结果当作本次基线。

**验证：**

```bash
cd Apps/Mac
tuist generate --no-open
xcodebuild -workspace SmartQuota.xcworkspace -scheme SmartQuota \
  -destination 'platform=macOS,arch=arm64' test \
  -resultBundlePath .build/p1-baseline.xcresult
```

### Task 0A: 开源仓库文档、许可证和治理基线

**Purpose:** 在实现通用能力前先固定公开仓库的法律、隐私、贡献和发布文档边界，保证后续新增功能有可追溯的文档和许可证证据。

**Files:**
- Read: `README.md`
- Read: `LICENSE`
- Read: `NOTICE`
- Read: `SECURITY.md`
- Read: `CONTRIBUTING.md`
- Read: `docs/README.md`
- Read: `docs/USER_GUIDE.md`
- Read: `docs/DEVELOPER.md`
- Read: `docs/DISTRIBUTION.md`
- Read: `docs/REPO_LAYOUT.md`
- Read: `PRODUCT.md`
- Read: `PROJECT_STATUS.md`
- Read: `CHANGELOG.md`
- Read: `Apps/Mac/Tuist/Package.swift`
- Read: `Apps/Mac/Tuist/Package.resolved`
- Read: `Apps/Mac/Sources/App/Info.plist`
- Modify: `README.md`
- Modify: `LICENSE` — 保持完整 Apache License 2.0 正文，并核对版权主体和公开归属。
- Modify: `NOTICE`
- Modify: `SECURITY.md`
- Modify: `CONTRIBUTING.md`
- Modify: `docs/README.md`
- Modify: `docs/USER_GUIDE.md`
- Modify: `docs/DEVELOPER.md`
- Modify: `docs/DISTRIBUTION.md`
- Modify: `docs/REPO_LAYOUT.md`
- Modify: `PRODUCT.md`
- Modify: `PROJECT_STATUS.md`
- Modify: `CHANGELOG.md`
- Create or modify: `.github/ISSUE_TEMPLATE/bug-report.yml`
- Create or modify: `.github/ISSUE_TEMPLATE/feature-request.yml`
- Create or modify: `.github/PULL_REQUEST_TEMPLATE.md`
- Modify: `.github/workflows/tests.yml`
- Modify: `.github/workflows/release.yml`
- Create: `scripts/check-open-source-docs.sh`

**Interfaces:**
- Produces: 一份公开文档矩阵，列明每个文档的读者、唯一来源、允许承诺、禁止承诺和更新触发条件。
- Produces: 一份由实际依赖清单和发布内容生成的 `NOTICE` 核对表，包含组件、版本、来源 URL、许可证和分发要求。
- Produces: `scripts/check-open-source-docs.sh`，无网络依赖即可返回 0/非 0；失败时只输出文件和规则，不输出疑似密钥或用户数据。
- Preserves: 当前 Apache-2.0 License 和本机优先隐私原则；不引入云同步、遥测、CLA、商业附加条款或未授权的维护者联系方式。

- [ ] 对照 `LICENSE` 核对完整 Apache License 2.0 正文、版权主体、年份和仓库实际权利归属；若版权主体尚未确认，先列为发布阻塞项，不擅自填入个人姓名或公司名称。
- [ ] 在 `README.md` 和 `docs/README.md` 建立稳定的“许可证 / 第三方声明 / 安全报告 / 贡献指南 / 用户文档 / 开发文档 / 发布说明”入口，所有相对链接指向仓库内真实文件。
- [ ] 从 `Apps/Mac/Tuist/Package.swift`、`Apps/Mac/Tuist/Package.resolved` 和实际 App 包内容核对 `NOTICE`；为每个随 App 分发的第三方组件补齐锁定版本或版本范围、来源 URL、许可证类型、版权/归属要求和用途。
- [ ] 检查资源目录、图标、字体、截图、示例 JSON、脚本和生成文件的来源；没有许可证或来源证据的内容不得纳入公开仓库或 Release 资产。
- [ ] 在 `README.md` 写清项目用途、支持平台/最低系统、快速开始、构建与测试入口、本机优先边界、网络出口、更新方式、已知限制、第三方服务责任边界和当前发布状态。
- [ ] 在 `CONTRIBUTING.md` 写清环境准备、`tuist generate`、测试命令、改动范围、PR 证据、文档同步、依赖许可证核对、假数据规则和密钥/个人数据禁止提交规则。
- [ ] 在 `SECURITY.md` 写清威胁模型、敏感数据不上传原则、漏洞报告渠道、支持版本、公开 Issue 禁止披露凭证、维护者响应范围，以及 P2 崩溃上报/匿名诊断在未获用户同意前默认关闭。
- [ ] 校准 `docs/USER_GUIDE.md`、`docs/DEVELOPER.md`、`docs/DISTRIBUTION.md`、`docs/REPO_LAYOUT.md`，让安装、手动更新、构建、签名/公证和 Mac/Windows 目录边界与实际状态一致。
- [ ] 以 `Apps/Mac/Sources/App/Info.plist` 为版本唯一来源，统一 README、产品文档、项目状态、CHANGELOG、Release 说明中的版本、最低系统和已实现能力；未验证的签名、公证、安装和上报能力不得写成已完成。
- [ ] 补齐 Bug/Feature/PR 模板：要求版本、系统架构、复现步骤、脱敏日志、测试结果、文档影响和依赖/许可证影响；明确禁止粘贴 Token、Cookie、Keychain、真实邮箱和额度截图。
- [ ] 实现公开文档检查脚本：验证必需文件存在且非空、仓库内相对链接可解析、Apache-2.0/NOTICE/SECURITY/CONTRIBUTING 入口存在、版本字段不冲突，并扫描密钥/凭证/真实本机路径模式；测试样例中的假数据必须有明确 allowlist。
- [ ] 将开源文档检查加入本地发布前门禁和 GitHub CI；依赖发生增删、许可证变化、网络出口变化、数据字段变化或 P2 上报能力变化时，必须同步更新 `NOTICE`、`SECURITY.md`、用户文档和 CHANGELOG。

**验证：**

```bash
test -s LICENSE
test -s NOTICE
test -s SECURITY.md
test -s CONTRIBUTING.md
test -s README.md
test -s docs/README.md
./scripts/check-open-source-docs.sh
git diff --check
```

**验收：** 公开仓库新用户只读 `README.md` 即可知道项目用途、安装/构建方式、隐私边界、许可证、第三方声明、贡献方式和安全报告路径；依赖和资源均有可追溯许可；文档不包含真实凭证或未验证承诺；脚本在缺文件、坏链接、版本冲突或疑似敏感内容时失败并阻止 Release。

### Task 1: 设置 schema、迁移和安全备份基础

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/BackupManifest.swift`
- Create: `Apps/Mac/Sources/Domain/Support/SettingsMigration.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/BackupManager.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/SettingsMigrationRunner.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsStore.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsRepository.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/BackupManagerTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/SettingsMigrationRunnerTests.swift`

**Interfaces:**

```swift
public struct BackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let appVersion: String
    public let createdAt: Date
    public let includedFiles: [String]
    public let sha256: [String: String]
}

public protocol SettingsMigrationStep: Sendable {
    var fromVersion: Int { get }
    var toVersion: Int { get }
    func migrate(_ input: [String: Any]) throws -> [String: Any]
}

public protocol BackupManaging: Sendable {
    func createPreMutationBackup() throws -> BackupManifest
    func listBackups() throws -> [BackupManifest]
    func restore(_ backup: BackupManifest) throws
}
```

- [ ] 为 `settings.json` 增加 `schemaVersion`，未知字段继续保留。
- [ ] 迁移前把设置文件复制到 `~/.smartquota/backups/<timestamp>/`，写入 manifest 和 SHA256。
- [ ] 迁移只操作临时副本；校验通过后使用原子替换，失败时保留原文件。
- [ ] 损坏 JSON 不覆盖原文件，生成可读错误并进入恢复提示。
- [ ] 备份只包含非敏感设置和账号元数据，不包含 Keychain、Token、Cookie、日志和原始额度快照。
- [ ] 为旧版本字段补默认值，验证主题、语言、排序、会员开关、套餐标签、续费日期和刷新间隔。
- [ ] 测试重复迁移幂等、未知字段保留、迁移失败回滚、备份校验失败拒绝恢复。

**验收：** 任意旧设置 fixture 升级后数据不丢失；模拟写入失败后原文件字节内容不变；恢复后应用可启动。

### Task 2: 首次启动引导与兼容性检查

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/FirstLaunchState.swift`
- Create: `Apps/Mac/Sources/Domain/Support/CompatibilityReport.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/FirstLaunchStore.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/CompatibilityChecker.swift`
- Create: `Apps/Mac/Sources/App/Views/Onboarding/OnboardingView.swift`
- Create: `Apps/Mac/Sources/App/Views/Onboarding/PrivacyBoundaryView.swift`
- Create: `Apps/Mac/Sources/App/Views/Support/CompatibilityView.swift`
- Modify: `Apps/Mac/Sources/App/SmartQuotaApp.swift`
- Modify: `Apps/Mac/Sources/App/Localization/L10n.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/FirstLaunchStateTests.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/CompatibilityReportTests.swift`
- Test: `Apps/Mac/Tests/AcceptanceTests/OnboardingSpec.swift`

**Interfaces:**

```swift
public enum OnboardingStep: String, Codable, Sendable {
    case privacy
    case compatibility
    case chooseProvider
    case configureProvider
    case firstRefresh
    case completed
}

public struct CompatibilityReport: Codable, Equatable, Sendable {
    public let minimumOSSatisfied: Bool
    public let architecture: String
    public let supportedArchitecture: Bool
    public let appDirectoryWritable: Bool
    public let keychainAvailable: Bool
    public let providerChecks: [String: ProviderCompatibility]
}
```

- [ ] 首次打开只展示一次；用户跳过后在设置中提供“继续引导”。
- [ ] 首屏明确说明：数据留在本机、不建云账号、不上传密钥和用量。
- [ ] 显示 macOS 版本、CPU 架构、应用目录可写性、Keychain 可用性。
- [ ] 用户选择第一个会员后跳转已有检测配置，不复制 Provider 配置逻辑。
- [ ] 完成第一次检测后显示成功、未登录或需要配置的具体下一步。
- [ ] 缺少 CLI、Key 或系统权限时，直接提供“打开配置”“查看帮助”“重新检测”动作。
- [ ] 引导所有状态支持跳过、返回、重新进入和应用重启后继续。

**验收：** 新临时设置目录首次打开能完成引导；已完成用户不会重复弹出；不兼容环境不会误报为已准备完成。

### Task 3: 手动刷新、取消和刷新结果聚合

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/RefreshScope.swift`
- Create: `Apps/Mac/Sources/Domain/Support/RefreshState.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/RefreshCoordinator.swift`
- Modify: `Apps/Mac/Sources/App/Views/MenuContentView.swift`
- Modify: `Apps/Mac/Sources/App/StatusItemLabelDriver.swift`
- Modify: `Apps/Mac/Sources/Domain/Monitor/QuotaMonitor.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Shared/SystemPowerStateProvider.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/RefreshStateTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/RefreshCoordinatorTests.swift`
- Modify: `Apps/Mac/Tests/AcceptanceTests/RefreshSpec.swift`

**Interfaces:**

```swift
public protocol RefreshCoordinating: Sendable {
    var state: RefreshState { get async }
    func refresh(_ scope: RefreshScope) async
    func cancel() async
}
```

- [ ] 为当前选中会员增加“刷新”按钮，并显示当前刷新状态。
- [ ] 增加“刷新全部”按钮，按已开启会员执行，显示成功/失败计数。
- [ ] 增加“取消刷新”按钮；取消只停止未完成任务，已成功快照不回滚。
- [ ] 防止相同 Provider 重复刷新；已有后台刷新时，前台点击应复用或拒绝第二个任务。
- [ ] 睡眠时暂停后台刷新，唤醒后按最新设置恢复；手动刷新仍由用户主动触发。
- [ ] 每个失败结果包含可读状态和最后成功时间，不把失败快照清空。
- [ ] 菜单栏只反映有效实时数据；未登录和连接失败不参与最差额度计算和告警。

**验收：** 模拟一个成功、一个超时、一个取消的三会员刷新，界面显示正确计数，旧快照完整保留，取消后没有继续启动新任务。

### Task 4: 诊断中心

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/DiagnosticModels.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/DiagnosticsService.swift`
- Create: `Apps/Mac/Sources/App/Views/Support/DiagnosticsCenterView.swift`
- Modify: `Apps/Mac/Sources/App/Views/Settings/ProviderProbeGuide.swift`
- Modify: `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/DiagnosticsServiceTests.swift`
- Test: `Apps/Mac/Tests/AcceptanceTests/DiagnosticsSpec.swift`

**Interfaces:**

```swift
public protocol DiagnosticsServicing: Sendable {
    func runAll() async -> [DiagnosticResult]
    func run(providerId: String) async -> [DiagnosticResult]
    func retry(_ result: DiagnosticResult) async -> DiagnosticResult
}
```

- [ ] 检查系统版本、架构、应用目录可写性、Keychain、通知权限和配置文件完整性。
- [ ] 对已开启会员检查 CLI 是否存在、凭证是否可读、网络是否可达、Provider 接口是否返回有效结果。
- [ ] 清晰区分“未登录”“缺少 CLI”“缺少 Key”“网络失败”“服务拒绝”“缓存过期”。
- [ ] 每个失败项提供对应动作：打开配置、打开帮助、打开后台、重试、打开日志。
- [ ] 路径只显示 `~` 下的相对路径或文件名；邮箱脱敏；不显示密钥和原始响应。
- [ ] 增加“复制诊断摘要”，内容只包含版本、系统、架构、检查结果和错误编号。

**验收：** 断开网络、移除 CLI、删除测试凭证、拒绝通知权限时，诊断中心分别给出不同结果和可执行建议。

### Task 5: 安全设置导出/导入与全局备份恢复

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/PortableSettings.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/SettingsTransferService.swift`
- Create: `Apps/Mac/Sources/App/Views/Support/SettingsTransferView.swift`
- Create: `Apps/Mac/Sources/App/Views/Support/BackupRestoreView.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Support/BackupManager.swift`
- Modify: `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/PortableSettingsTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/SettingsTransferServiceTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/BackupManagerTests.swift`
- Modify: `Apps/Mac/Tests/AcceptanceTests/SettingsTransferSpec.swift`

**导出 allowlist：**

```text
schemaVersion
appLanguage
themeMode
usageDisplayMode
menuBar display preferences
provider enabled states
membership order
accountId / providerId
user account label / remark
optional email, only after explicit privacy confirmation
plan label
renewal date
refresh and alert preferences
```

**禁止导出：**

```text
API Key / Token / Cookie / Password
OAuth files and refresh tokens
Keychain data
raw provider responses
full logs
diagnostic payloads containing secrets
```

- [ ] 导出前显示字段预览和敏感数据声明，默认不导出邮箱。
- [ ] 导入先解析、校验 schema、生成差异预览，再由用户选择合并或覆盖非敏感配置。
- [ ] 导入不得覆盖 Keychain，不得删除外部登录态，不得自动启用未知 Provider。
- [ ] 每次导入、恢复和迁移前自动生成备份。
- [ ] 备份列表显示时间、来源版本、文件列表和校验状态。
- [ ] 恢复使用临时目录校验，成功后原子替换；失败保留当前数据并给出恢复失败原因。
- [ ] 提供“恢复默认设置”和“清除全部本地数据”两个独立危险操作，分别二次确认。

**验收：** 导出的 JSON 中搜索 `token`、`cookie`、`secret`、`password`、`key` 等敏感字段不得出现；导入后会员排序和备注恢复，密钥仍必须重新配置。

### Task 6: 更新说明展示与安全更新体验

**Files:**
- Create: `Apps/Mac/Sources/App/Views/Support/UpdateDetailsView.swift`
- Modify: `Apps/Mac/Sources/Domain/Update/ManualUpdate.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/GitHubReleaseChecker.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/ReleaseDownloader.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/SilentPkgInstaller.swift`
- Modify: `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift`
- Modify: `Apps/Mac/Sources/App/Localization/L10n.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Update/GitHubReleaseCheckerTests.swift`
- Create: `Apps/Mac/Tests/InfrastructureTests/Update/ReleaseNotesTests.swift`
- Modify: `Apps/Mac/Tests/AcceptanceTests/UpdatesSpec.swift`

**接口扩展：**

```swift
public struct RemoteRelease: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let htmlURL: URL
    public let downloadURL: URL?
    public let releaseNotes: String
    public let publishedAt: Date?
    public let minimumOS: OperatingSystemVersion?
    public let assetSize: Int64?
    public let sha256: String?
}
```

- [ ] 检查完成后显示当前版本、新版本、发布日期、变更说明、安装包大小和最低 macOS 版本。
- [ ] 只有稳定版默认进入结果；Beta 版本由 P2 更新渠道控制。
- [ ] 如果最低系统版本不满足，显示不可安装原因，不启动下载。
- [ ] 如果 Release 缺少合法 DMG/PKG/校验信息，显示发布资产异常并打开 Release 页面作为回退。
- [ ] 下载使用临时文件、大小上限、超时、取消和失败清理。
- [ ] 更新前检查目标版本高于当前版本；安装完成后重新读取 Bundle 版本。
- [ ] 更新失败时保留当前 App 可启动，不删除当前版本，不伪造“已更新”。
- [ ] 统一用户手册与实现：明确 PKG 主路径、DMG 回退、签名状态和首次打开提示。
- [ ] 保持用户控制：检查结果先展示说明；下载/安装动作必须在用户可见的更新区域中完成。

**验收：** 使用 mock Release 覆盖“已是最新版、发现新版本、低系统版本、无资产、网络超时、取消下载、安装失败”七条路径。

### Task 7: 异常恢复与安全模式

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/AppRecoveryState.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/CrashRecoveryStore.swift`
- Create: `Apps/Mac/Sources/App/Views/Recovery/SafeModeView.swift`
- Modify: `Apps/Mac/Sources/App/SmartQuotaApp.swift`
- Modify: `Apps/Mac/Sources/App/AppDelegate.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsStore.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/AppRecoveryStateTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Recovery/CrashRecoveryStoreTests.swift`
- Test: `Apps/Mac/Tests/AcceptanceTests/RecoverySpec.swift`

**状态协议：**

```swift
public enum AppLaunchMode: Sendable, Equatable {
    case normal
    case safeMode(reason: SafeModeReason)
}

public enum SafeModeReason: String, Sendable, Codable {
    case previousLaunchDidNotFinish
    case settingsDecodeFailed
    case migrationFailed
    case repeatedStartupFailure
}
```

- [ ] 启动时写入 session marker，完成初始化后写入 ready marker，正常退出时清除 marker。
- [ ] 检测到上次未完成启动时，先以安全模式启动，不加载用户扩展、不启动后台刷新、不启动 Hook 服务。
- [ ] 设置解析失败时使用只读默认配置进入安全模式，保留损坏文件副本。
- [ ] 安全模式提供：打开日志、恢复最近备份、导出非敏感设置、重置设置、正常模式重试。
- [ ] 重置只处理智额自己的 `~/.smartquota` 内容，不删除外部 CLI 登录态。
- [ ] 安全模式恢复成功后清除 marker；恢复失败继续保持安全模式。
- [ ] 不把“用户主动退出”误判成崩溃；退出路径必须先写入 clean marker。

**验收：** 模拟设置损坏、迁移异常、启动中断和正常退出，分别验证安全模式、备份保留和正常启动路径。

### Task 8: 数据迁移与兼容性持续校验

**Files:**
- Modify: `Apps/Mac/Sources/Infrastructure/Support/SettingsMigrationRunner.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Support/CompatibilityChecker.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsStore.swift`
- Modify: `Apps/Mac/Sources/App/Views/Support/CompatibilityView.swift`
- Modify: `Apps/Mac/Sources/App/Settings/AppSettings.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/SettingsMigrationRunnerTests.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/CompatibilityReportTests.swift`

- [ ] 为每个设置 schema 版本定义单向迁移步骤，禁止跨版本直接猜字段。
- [ ] 迁移前生成 manifest，迁移后验证必需字段、类型、枚举值和文件权限。
- [ ] 迁移失败恢复原文件并显示备份位置；不能只记录日志后继续使用不完整配置。
- [ ] 兼容性检查覆盖 macOS 15+、arm64/x86_64、应用目录可写、Keychain、通知权限和已开启会员的外部依赖。
- [ ] 缺少 CLI 时显示安装/登录建议，但不自动安装第三方 CLI。
- [ ] 系统权限不足时显示系统设置入口或具体权限名称，不显示无意义的“未知错误”。
- [ ] 对跨版本未知字段做保留测试，确保新版本不会破坏未来字段。

**验收：** 使用至少三个历史设置 fixture 升级和回滚；在 arm64 与 x86_64 构建产物中检查兼容性信息；缺少依赖时诊断可操作。

### Task 9: 无障碍、帮助中心和统一错误体验

**Files:**
- Create: `Apps/Mac/Sources/App/Views/Support/HelpCenterView.swift`
- Modify: `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift`
- Modify: `Apps/Mac/Sources/App/Views/MenuContentView.swift`
- Modify: `Apps/Mac/Sources/App/Localization/L10n.swift`
- Modify: `Apps/Mac/Sources/App/Theme/`
- Test: `Apps/Mac/Tests/AcceptanceTests/AccessibilitySpec.swift`
- Modify: `docs/USER_GUIDE.md`

- [ ] 所有图标按钮提供 VoiceOver label、hint 和 value；装饰性图标标记为不读。
- [ ] 菜单栏面板、设置页、弹窗和危险操作支持完整键盘焦点顺序。
- [ ] 动态字体增大时不截断按钮、额度、错误信息和更新说明。
- [ ] 使用语义颜色和文本标签表达成功、警告、失败，不依赖颜色单独传达状态。
- [ ] 验证浅色、深色、高对比度、减少动画和 RTL 布局。
- [ ] 帮助中心包含首次配置、检查更新、日志位置、多账号、密钥安全、隐私和 FAQ。
- [ ] 错误文案统一包含“发生了什么、是否保留旧数据、下一步怎么做”。
- [ ] 帮助中心可以打开日志、诊断中心、项目 Release 页面和本地用户手册。

**验收：** 使用 VoiceOver 走完菜单栏→设置→诊断→帮助→返回路径；键盘不使用鼠标完成刷新和导出；放大字体后无关键内容丢失。

### Task 10: 性能保护与刷新生命周期

**Files:**
- Create: `Apps/Mac/Sources/Infrastructure/Support/RefreshPerformanceMonitor.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Support/RefreshCoordinator.swift`
- Modify: `Apps/Mac/Sources/App/StatusItemLabelDriver.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Shared/SystemPowerStateProvider.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Logging/AppLogger.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/RefreshCoordinatorTests.swift`
- Create: `Apps/Mac/Tests/AcceptanceTests/PerformanceSpec.swift`

- [ ] 后台刷新统一由 `RefreshCoordinator` 管理，禁止 Provider 自己创建无法取消的常驻 Timer。
- [ ] 睡眠、锁屏和低电量状态暂停非必要刷新；唤醒后只执行一次合并刷新。
- [ ] 同一 Provider 在短时间重复请求时合并任务或返回已有任务结果。
- [ ] 对网络请求设置超时、取消和有限重试；重试使用递增退避，不进行无限重试。
- [ ] 仅刷新已开启会员和当前需要的额度窗口；历史快照展示不触发网络请求。
- [ ] 记录刷新耗时、失败类别、任务数量和取消次数，不记录敏感请求内容。
- [ ] 对 30 分钟常驻、睡眠唤醒、网络断开恢复和 20 个扩展 Provider 做 CPU/内存/网络检查。

**验收：** 常驻 30 分钟无任务泄漏；睡眠期间没有持续网络刷新；唤醒后不会重复触发多个全量刷新；取消后任务可释放。

---

## 5. P2 后续增强阶段

P2 不阻塞 P1 日常使用闭环，必须在 P1 的数据、更新和隐私边界稳定后单独实施。

### Task 11: Beta 更新通道

**Files:**
- Create: `Apps/Mac/Sources/Domain/Update/UpdateChannel.swift`
- Modify: `Apps/Mac/Sources/App/Settings/AppSettings.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/GitHubReleaseChecker.swift`
- Modify: `Apps/Mac/Sources/App/Views/Support/UpdateDetailsView.swift`
- Modify: `Apps/Mac/Sources/App/Localization/L10n.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Update/GitHubReleaseCheckerTests.swift`
- Modify: `Apps/Mac/Tests/AcceptanceTests/UpdatesSpec.swift`

- [ ] 定义 `stable`、`beta` 两个更新通道；默认稳定版。
- [ ] Beta 通道只在用户主动开启后筛选 prerelease，设置页明确显示风险。
- [ ] 检查更新结果显示通道、版本、发布日期和是否为预发布。
- [ ] 关闭 Beta 后不再推荐预发布版本，已下载文件不自动安装。
- [ ] 测试稳定版、Beta 版、版本倒退和没有对应资产的情况。

### Task 12: 可控自动更新

**Files:**
- Create: `Apps/Mac/Sources/Domain/Update/AutoUpdatePolicy.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Update/AutoUpdateScheduler.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/ReleaseDownloader.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Update/SilentPkgInstaller.swift`
- Modify: `Apps/Mac/Sources/App/Settings/AppSettings.swift`
- Modify: `Apps/Mac/Sources/App/Views/Support/UpdateDetailsView.swift`
- Test: `Apps/Mac/Tests/DomainTests/Update/AutoUpdatePolicyTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Update/AutoUpdateSchedulerTests.swift`

- [ ] 自动更新默认关闭，用户必须单独开启。
- [ ] 只在空闲、非计量网络、电源条件允许、没有刷新任务时下载。
- [ ] 先下载到临时目录并验证版本、大小、SHA256 和代码签名状态。
- [ ] 支持稍后提醒、暂停、取消、失败重试和回到手动检查。
- [ ] 安装前保存当前版本信息，安装失败不删除旧版本；下一次启动可进入安全模式。
- [ ] 没有 Developer ID/公证资产时不得把自动更新作为默认发布能力。

### Task 13: 崩溃报告和匿名诊断上报

**Files:**
- Create: `Apps/Mac/Sources/Domain/Support/CrashReportConsent.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/CrashReportStore.swift`
- Create: `Apps/Mac/Sources/Infrastructure/Support/AnonymousDiagnosticsUploader.swift`
- Create: `Apps/Mac/Sources/App/Views/Support/PrivacyConsentView.swift`
- Modify: `Apps/Mac/Sources/App/SmartQuotaApp.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Logging/FileLogger.swift`
- Test: `Apps/Mac/Tests/DomainTests/Support/CrashReportConsentTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/CrashReportStoreTests.swift`
- Test: `Apps/Mac/Tests/InfrastructureTests/Support/AnonymousDiagnosticsUploaderTests.swift`

- [ ] 首次启用前显示数据清单、用途、保存期限、删除方式和关闭入口。
- [ ] 默认关闭；没有同意不得创建上传任务或网络请求。
- [ ] 只允许上传版本、构建号、系统版本、架构、错误类别、匿名事件编号和耗时统计。
- [ ] 删除路径、邮箱、Provider 账号、Keychain、请求 URL 参数、日志正文和额度数值。
- [ ] 本地队列加大小上限、失败重试上限、过期删除和立即清除功能。
- [ ] 上传使用 HTTPS、可验证服务端证书和独立超时；服务不可用时不影响主应用。
- [ ] 提供“仅导出到本机，不上传”的替代路径。

**停止条件：** 如果无法提供明确后端、隐私政策、删除机制和用户同意界面，只完成本地崩溃记录，不上线网络上报。

---

## 6. 测试与质量门禁

### 6.1 单元和基础设施测试

- 设置 schema：旧字段、未知字段、损坏文件、原子写入、迁移失败回滚。
- 导出导入：allowlist、敏感字段扫描、合并、覆盖、未知 Provider、重复导入。
- 备份恢复：manifest、SHA256、时间排序、损坏备份、恢复失败保留当前数据。
- 刷新协调：单会员、全量、取消、部分失败、重复任务、睡眠唤醒。
- 诊断：缺 CLI、缺 Key、未登录、连接失败、权限拒绝、缓存过期。
- 更新：最新版、新版、Beta、低系统、无资产、下载取消、安装失败。
- 恢复：正常退出、异常退出、设置损坏、迁移失败、连续启动失败。
- 安全：Keychain 访问、Touch ID 不可用、密码回退、密钥不出现在日志和导出文件。

### 6.2 Acceptance 测试

必须覆盖以下可观察路径：

1. 新用户首次打开并完成第一个会员配置。
2. 当前会员刷新成功，全部刷新部分失败，用户取消剩余刷新。
3. 诊断中心给出缺少 CLI、未登录和网络错误的不同结果。
4. 导出配置后扫描文件，确认没有密钥；导入后排序和备注恢复。
5. 设置损坏后进入安全模式，恢复最近备份后正常启动。
6. 检查更新显示版本和变更说明，用户主动安装或取消。
7. VoiceOver、键盘、放大字体、深色、RTL 和减少动画路径可用。
8. 睡眠和唤醒不会触发重复刷新或无限重试。

### 6.3 本地验证命令

```bash
cd Apps/Mac
tuist generate --no-open
xcodebuild -workspace SmartQuota.xcworkspace -scheme SmartQuota \
  -destination 'platform=macOS,arch=arm64' test \
  -resultBundlePath .build/p1-tests.xcresult
xcrun xcresulttool get test-results summary \
  --path .build/p1-tests.xcresult --compact
./scripts/build-test-app.sh
```

最终发布前才执行：

```bash
cd Apps/Mac
COPY_TO_DESKTOP=0 ./scripts/package-release.sh
```

### 6.4 发布门禁

P1 只有同时满足以下条件才可进入 Release：

- 单元、基础设施和 Acceptance 测试通过。
- 设置迁移至少覆盖现行版本和两个历史 fixture。
- 导出文件通过敏感字段扫描。
- 安全模式能从损坏设置恢复。
- 更新说明、资产命名、最低系统要求和 Release Notes 一致。
- `LICENSE`、`NOTICE`、`SECURITY.md`、`CONTRIBUTING.md`、README 文档入口和仓库文档检查脚本通过校验。
- 所有第三方依赖、随包资源和商标声明均有来源与许可证证据；没有把第三方内容误纳入 Apache-2.0 授权范围。
- 发布包、截图、示例和日志中没有真实密钥、Cookie、OAuth 文件、邮箱、账号 ID、额度明细或私有路径。
- 本地 Build、Package、运行时安装验证分别有证据。
- 未把 ad-hoc 包描述为 Developer ID 签名或已公证包。
- GitHub CI 通过后再创建正式 Release。

P2 自动更新和崩溃上报必须单独版本、单独 Release Notes、单独隐私验收，不能随 P1 一起隐式上线。

---

## 7. 实施顺序与交付批次

### Batch A：数据安全和恢复底座

包含 Task 0、Task 0A、Task 1、Task 7、Task 8。完成后公开仓库有可复核的文档/许可证基线，用户数据可迁移、备份、恢复，设置损坏不会直接阻塞启动。

### Batch B：用户入口和可诊断性

包含 Task 2、Task 4、Task 9。完成后新用户能完成配置，已有用户能理解失败原因并自行处理。

### Batch C：刷新和运行时质量

包含 Task 3、Task 10。完成后刷新可控、可取消，睡眠和唤醒不会造成重复任务或过度耗电。

### Batch D：更新体验

包含 Task 6。完成后检查更新会展示完整说明，失败不会破坏当前版本。

### Batch E：P2 试验能力

按需单独执行 Task 11、Task 12、Task 13。任何一项都需要重新确认隐私、签名、后端和回滚条件。

每个 Batch 完成后单独运行测试并形成小提交；本计划执行时不使用 `git add -A`，不纳入已有用户改动。

---

## 8. 最终验收清单

### P1

- [ ] 首次启动引导说明本机优先、隐私边界和第一个会员配置。
- [ ] 可刷新当前会员、刷新全部会员、取消刷新，并保留旧快照。
- [ ] 诊断中心区分未登录、缺 CLI、缺 Key、网络失败、权限失败和缓存过期。
- [ ] 设置和账号备注可安全导出/导入，密钥永不进入文件。
- [ ] 设置、会员开关、排序、套餐标签和续费日期可备份/恢复。
- [ ] 显示 macOS、架构、CLI、Keychain、通知权限和应用目录兼容性。
- [ ] VoiceOver、键盘、动态字体、颜色对比度、深色、RTL 和减少动画通过验收。
- [ ] 更新说明包含当前版本、新版本、变更内容、最低系统和安装包信息。
- [ ] 启动失败、设置损坏和迁移失败可进入安全模式并恢复。
- [ ] 旧版本设置迁移前自动备份，失败自动回滚。
- [ ] 应用内帮助包含 FAQ、日志、会员配置和隐私说明。
- [ ] 睡眠暂停刷新，唤醒恢复一次，常驻运行无任务泄漏和无限重试。

### 开源仓库文档与许可证

- [ ] `LICENSE` 保持完整 Apache License 2.0 正文，版权主体已确认，README、文档目录、贡献指南和发布说明均能访问许可证入口。
- [ ] `NOTICE` 根据 `Apps/Mac/Tuist/Package.swift`、`Package.resolved`、实际 App 包和仓库资源完成依赖、版权、许可证、商标和分发要求核对。
- [ ] README 可独立说明项目用途、支持范围、安装/构建、隐私边界、网络出口、更新方式、已知限制、第三方服务责任、贡献入口和安全报告入口。
- [ ] `CONTRIBUTING.md` 明确开发/测试/PR 流程、文档同步、依赖许可证核对和禁止提交真实凭证的隐私红线。
- [ ] `SECURITY.md` 明确威胁边界、数据流、漏洞报告、支持版本和公开 Issue 禁止披露敏感信息的处理方式。
- [ ] 用户、开发者、发布、产品、项目状态和 CHANGELOG 文档的版本与能力状态一致；未完成能力没有被写成已上线。
- [ ] Issue/PR 模板要求脱敏复现信息和许可证影响说明，不收集 Token、Cookie、Keychain、真实账号和额度数据。
- [ ] `scripts/check-open-source-docs.sh` 和 GitHub CI 通过；缺文档、坏链接、版本冲突、依赖声明缺失或敏感信息扫描失败时 Release 被阻断。
- [ ] P2 自动更新、崩溃上报和匿名诊断若进入实现，先同步公开隐私说明、用户同意、数据删除/停止上传机制和 CHANGELOG，再单独发布。

### P2

- [ ] Beta 更新通道默认关闭并明确风险。
- [ ] 自动更新默认关闭，满足签名、校验、回退、暂停和用户授权条件。
- [ ] 崩溃报告/匿名诊断默认关闭，具备隐私同意、脱敏、删除和停止上传能力。

### 当前明确未验证

- [ ] 真实用户设备上的 VoiceOver、Touch ID、低电量、睡眠唤醒和 Gatekeeper 行为。
- [ ] Developer ID 签名、公证、自动更新安装和失败回退。
- [ ] 真实用户主动同意后的崩溃上报链路。

---

## 9. 执行选择

本文件是实施计划，不代表源码已经实现。执行时可以选择：

1. **Subagent-Driven**：按 Batch/Task 分配独立实现、逐项 Review 和 QA。
2. **Inline Execution**：在当前会话按 Batch 执行，每个 Batch 完成后暂停验收。

开始实现前，先重新读取本计划、检查工作区脏改动，并明确本次只执行哪一个 Batch。

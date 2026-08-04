# 智额 · 开发者文档

面向在本仓库上改功能、加会员、打包的人。

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

版本号：`Sources/App/Info.plist`

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
| GitHub Token、MiniMax Key、阿里云 Cookie/Key | Keychain（`KeychainSecretStore`） |
| Codex/Grok/Kimi 等 OAuth | 各工具自己的 `~/.xxx/auth.json` 等 |

**禁止**把真实密钥提交进仓库。

---

## 8. 测试

```bash
# 示例：Domain 产品默认
xcodebuild -workspace SmartQuota.xcworkspace -scheme Domain \
  -destination 'platform=macOS' test \
  -only-testing:DomainTests/SmartQuotaProductDefaultsTests
```

也可在 Xcode 中跑 `Domain` / `Infrastructure` / `AcceptanceTests` scheme。

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

本产品**不**使用远程自动更新。

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

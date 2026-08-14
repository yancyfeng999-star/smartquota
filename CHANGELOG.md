# Changelog

All notable changes to **智额 · SmartQuota** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Mac 0.3.28] — 2026-08-14

### Changed
- **Cursor 额度对齐官方双桶**：卡片只左右两根条（Cursor 模型 / 其他模型），不展示具体模型名；套餐识别补上 Pro+、Start、Hobby、Teams。

### Release
- GitHub：`v0.3.28` · `SmartQuota-0.3.28.dmg` / `.pkg`

---

## [Mac 0.3.27] — 2026-08-11

### Added
- **指纹解锁保护**：支持使用 Touch ID 保护敏感 API 密钥
- **密钥管理界面**：设置中新增"安全"卡片，可管理密钥和生物识别设置
- **安全存储增强**：敏感密钥使用 Keychain 访问控制保护，需要用户交互才能访问
- **密码回退**：生物识别不可用时可使用系统密码验证

### Security
- 生物识别模板存储在 Secure Enclave 中，永不离开设备
- 敏感密钥使用 `kSecAttrAccessControl` 保护
- 新增 `com.apple.security.personal-information.biometric` 权限

### Release
- GitHub：`v0.3.27` · `SmartQuota-0.3.27.dmg` / `.pkg`

---

## [Mac 0.3.26] — 2026-08-11

### Added
- **全会员多账号支持**：每个 AI 会员支持任意数量账号，同一时间只读取本机当前可用账号，其他账号保留最后一次成功额度并显示"未登录"。
- **账号发现状态机**：自动识别当前登录账号，支持邮箱标准化、历史账号恢复、新账号确认流程。
- **账号级持久化**：账号配置和额度快照本地缓存，支持账号级套餐名称和续费日期。
- **多账号 UI**：账号选择器、待确认横幅、账号管理卡片，支持 VoiceOver 和键盘导航。
- **全部 Mac Provider 接入**：18 个内置 AI 会员均支持多账号（Codex、Kimi、MiniMax、Grok、Claude、Gemini、Copilot 等）。
- **Windows 行为对齐**：Rust 账号状态机、React 账号 UI、Windows Credential Manager 按账号隔离密钥。
- **隐私与安全**：邮箱、额度、Keychain 和普通设置的存储边界明确，历史快照不参与告警。

### Release
- GitHub：`v0.3.26` · `SmartQuota-0.3.26.dmg` / `.pkg`

---

## [Mac 0.3.25] — 2026-08-11

### Fixed
- **会员额度显示模式**：Kimi 的 `已用/总额` 不再被误当成「剩余/总额」，会员汇总卡现在会跟随全局「剩余 / 已用 / 节奏」设置同步更新数值和进度条。
- **多账号额度卡**：兼容旧缓存中没有语义标记的比例数据，并保留明确「剩余」数量型额度的换算。

### Release
- GitHub：`v0.3.25` · `SmartQuota-0.3.25.dmg` / `.pkg`

---

## [Mac 0.3.24] — 2026-08-09

### Fixed
- **静默更新与智余 `PackageSilentInstaller` 对齐**  
  - `pkgutil --expand-full` 失败时回退 `--expand` + Payload 解压  
  - `apply.sh`：`ditto --noqtn`、`.preupdate` 挪包、等 PID 退出后替换  
  - `nohup` 后台调度方式与智余一致  
  - **仍不**请求管理员密码

### Release
- GitHub：`v0.3.24` · `SmartQuota-0.3.24.dmg` / `.pkg`

---

## [Mac 0.3.23] — 2026-08-09

### Changed
- **静默更新对齐智余方案**：`pkgutil` 解包 → `nohup apply.sh` 在进程退出后 ditto 覆盖 → 自动打开  
  - **不再**调用 `installer` / 管理员鉴权（不弹密码框）  
  - 目标目录不可写时只在设置页报错  
  - 日志：`~/Library/Logs/SmartQuota/update.log`  
- 下载失败不再自动打开浏览器发布页

### Release
- GitHub：`v0.3.23` · `SmartQuota-0.3.23.dmg` / `.pkg`
- 已装旧版：设置 → **检查更新**

---

## [Mac 0.3.22] — 2026-08-09

### Changed
- **工程整理**：打包脚本固定产出 GitHub ASCII 资产 `SmartQuota-x.y.z.{dmg,pkg}` + `SHA256SUMS-github.txt`
- **测试构建默认装到 `/Applications`**，避免桌面再留一份导致「多个智额」
- 文档 / 项目状态同步到一键 pkg 更新流程

### Release
- GitHub：`v0.3.22` · `SmartQuota-0.3.22.dmg` / `.pkg`
- 已装旧版：设置 → **检查更新**（优先 pkg 静默安装）

---

## [Mac 0.3.21] — 2026-08-09

### Changed
- **一键更新（PKG 静默安装）**：设置 → **检查更新** 发现新版后，优先下载 `.pkg`，**无二次确认弹窗**，静默覆盖安装并自动重启。
  - 不打开系统 Installer.app 向导；设置页内显示下载/安装进度。
  - 若目标目录无写权限，会回退到管理员 `installer`（可能出现**系统**密码框，非应用内弹窗）。
  - 若 Release 仅有 dmg，仍打开 dmg（需用户拖到应用程序）。

### Release
- GitHub：`v0.3.21` · `SmartQuota-0.3.21.dmg` / `.pkg`（打版后上传）
- 已装旧版：设置 → **检查更新**

---

## [Mac 0.3.20] — 2026-08-09

### Added
- **Xiaomi MiMo Token Plan**：扩展会员（默认关）。用控制台 Cookie 读 `tokenPlan/detail` + `tokenPlan/usage`，展示月度 Credits 剩余；**不读**账户现金余额。设置里可自动浏览器 Cookie 或手动粘贴。

### Release
- GitHub：`v0.3.20` · `SmartQuota-0.3.20.dmg` / `.pkg`
- 已装旧版：设置 → **检查更新**

---

## [Mac 0.3.19] — 2026-08-09

### Fixed
- **ChatGPT 积分 0 误标「用尽」**：加油包 / 积分余额为 0 时不再把整张会员卡标成用尽。  
  周额度（7D / GPT-5.3 周）重置为 100 后，右上角徽章应显示**充足/正常**，而不是「用尽」。  
  无 cap 的美元余额（积分）仅作展示，不参与 overall 最差状态；真正的限速表计（5H / 7D / 周桶）仍按最差规则判定。

### Notes（状态含义）
| 徽章 | 含义 |
|------|------|
| 充足 / 正常 | 限速额度整体健康 |
| 偏低 / 紧张 | 限速额度偏低 |
| **用尽** | **限速额度**用尽（不是积分余额为 0） |
| 积分 | ChatGPT 可选加油包余额，**单独显示**，0 为常态 |

### Release
- GitHub：`v0.3.19` · `SmartQuota-0.3.19.dmg` / `.pkg`  
- 已装旧版：设置 → **检查更新**

---

## [Mac 0.3.18] — 2026-08-07

### Changed
- **品牌标识**：确认并重新打包**彩色** Q 标（AppIcon / AppLogo / Dock）；非纯色、非 SF Symbol
- 浅色 / 深色菜单栏继续匹配彩色浅色稿与深色稿

### Release
- GitHub：`v0.3.18` · `SmartQuota-0.3.18.dmg` / `.pkg`

---

## [Mac 0.3.17] — 2026-08-07

### Changed
- **状态栏图标**：默认显示品牌 Logo；设置新增「状态栏额度图标」开关（默认关），开启后才显示绿柱 / 感叹三角等额度状态符号

### Release
- GitHub：`v0.3.17` · `SmartQuota-0.3.17.dmg` / `.pkg`

---

## [Mac 0.3.16] — 2026-08-06

### Fixed
- **文档**：`PRODUCT.md` / `Apps/README.md` 版本对齐
- **命名**：`MonthlyFromWeekly` → `MembershipCycleRemaining`
- **真月额度识别**：去掉过宽的 `billing` 关键字匹配
- **无 snapshot 状态**：不再一律 `depleted`，有错误为 critical、否则 warning

### Release
- GitHub：`v0.3.16` · `SmartQuota-0.3.16.dmg` / `.pkg`

---

## [Mac 0.3.15] — 2026-08-06

### Changed
- **总额（全渠道）**：Codex / Kimi / MiniMax / Grok 及扩展统一规则——能读到真实月额度用真值；否则一律按**续费日日历线性递减**（无探测数据时也显示总额列；Windows 同步）

### Release
- GitHub：`v0.3.15` · `SmartQuota-0.3.15.dmg` / `.pkg`

---

## [Mac 0.3.14] — 2026-08-06

### Changed
- **总额**：有接口月额度则读真值；否则按**续费日日历线性递减** `剩余天数/周期天数×100`（每天下降，与 7D 用量脱钩，避免重置后假 100%）

### Release
- GitHub：`v0.3.14` · `SmartQuota-0.3.14.dmg` / `.pkg`

---

## [Mac 0.3.13] — 2026-08-06

### Fixed
- **Grok 7D 重置后额度全 `-`**：xAI billing 在新周期尚无消耗时会省略 `creditUsagePercent` / `productUsage`；现按 `currentPeriod` 视为 0% 已用（7D=100%，总额可估算）。Mac + Windows 同步修复

### Release
- GitHub：`v0.3.13` · `SmartQuota-0.3.13.dmg` / `.pkg`

---

## [Mac 0.3.12] — 2026-08-05

### Fixed
- **续费色**：Grok 等会员续费黄/绿仅按会员续费日，不再跟周额度紧迫度混在一起
- **设置面板**：固定高度，避免打开设置时窗口先闪一下变矮

### Changed
- 额度卡片主列统一 **5H · 7D · 总额**；进度条下仅时间
- Spark 相关文案：**GPT-5.3 周额度**

### Release
- GitHub：`v0.3.12` · `SmartQuota-0.3.12.dmg` / `.pkg`

---

## [Mac 0.3.11] — 2026-08-05

### Added / Changed
- 卡片文案统一：**5H · 7D · 总额**
- **总额**读不出时用 7D + 会员续费日估算
- **MiniMax 视频**按条数显示（如 3/3），不再只显示 100/100
- 设置项紧凑、阈值配置可折叠

### Release
- GitHub：`v0.3.11`

---

## [Mac 0.3.10] — 2026-08-05

### Changed
- 额度展示与设置区进一步紧凑化
- 文案与布局微调

### Release
- GitHub：`v0.3.10`

---

## [Mac 0.3.9] — 2026-08-05

### Changed
- 更新安装包打开后 **自动退出** 当前 App，便于覆盖安装

### Release
- GitHub：`v0.3.9`

---

## [Mac 0.3.8] — 2026-08-05

### Fixed / Changed
- Codex 卡片与附加额度展示
- 额度 meters 与 credits 路径增强

### Release
- GitHub：`v0.3.8`

---

## [Mac 0.3.7] — 2026-08-05

### Added
- **检查更新**：发现新版本后 **自动下载** 安装包并打开（进度条）
- 无需再点第二按钮跳转浏览器

### Release
- GitHub：`v0.3.7`

---

## [Mac 0.3.6] — 2026-08-05

### Added
- **手动检查更新**（GitHub Releases API）
- 免费路径：仅用户触发，无 Sparkle 静默安装

### Notes
- 资产名使用 ASCII（`SmartQuota-*.dmg`），避免中文文件名在 GitHub 乱码

### Release
- GitHub：`v0.3.6`

---

## [Mac 0.3.5] — 2026-08-05

### Changed
- 发布管线与安装体验整理

### Release
- GitHub：`v0.3.5`

---

## [Mac 0.3.4] — 2026-08-05

### Changed
- 打包与分发流程稳定化

### Release
- GitHub：`v0.3.4`

---

## [Mac 0.3.3] — 2026-08-04

### Changed
- 菜单栏后台行为；Release 资产 ASCII 名

### Release
- GitHub：`mac-v0.3.3` / 后续统一 `v0.3.x`

---

## [Windows 0.5.0] — 2026-08-05

### Added / Completed (Windows full parity push)
- 全部 catalog 探针深化：Claude Mac 级解析、Z.ai、通义、AmpCode、Kiro、OpenCode、OMP、Mistral/Vibe、Antigravity、Bedrock
- 用户扩展：`~/.smartquota/extensions`（manifest + 脚本 / healthCheck）
- 窗口置顶（固定）、卡片排序
- 单测增至 8 项（Claude/Zai/Amp/Kiro/OMP 解析 + 告警/状态）

---

## [Windows 0.4.0] — 2026-08-05

### Added (Windows)
- 核心四会员：Codex / **Kimi** / MiniMax / Grok（默认开）
- 扩展 catalog：Claude、Gemini、Copilot、Cursor 及 Mac 同序其余会员（默认关）
- meters 合约增强：`key` / `kind` / `resetsAtUnix`；状态阈值对齐 Mac（50/20/0）
- 阈值告警与临近重置提醒（系统 Toast，可配置/关闭）
- 刷新档位：关闭 / 5 / 10 / 15 / 30 分钟（默认 15）
- UI 简体中文 / English
- 设置：Kimi Key、GitHub Token、扩展 API Key

### Notes
- Windows 版本线独立于 Mac；行为对齐规格见 `docs/WINDOWS_PARITY.md`
- Setup.exe 需在 Windows 上 `npm run tauri:build` 产出

---

## [0.3.2] — 2026-08-04

### Added
- 产品全量品牌：**智额 · SmartQuota**（Bundle ID `com.smartquota.app`）
- 开源文档：`LICENSE`（MIT）、`NOTICE`、`CONTRIBUTING.md`、`SECURITY.md`
- 配置目录：`~/.smartquota`；密钥写入本机 Keychain

### Security
- 移除 Sparkle 远程静默自动更新
- 收紧 entitlements；扩展脚本不得逃逸目录；Web/健康检查仅 http(s)
- 开源树不硬编码个人会员档位（`defaultPlanLabels` 为空）

### Changed
- 核心四会员默认开启探测入口：ChatGPT (Codex)、Kimi、MiniMax、Grok
- 其余内置会员默认关闭（设置中开启）
- 多语言运行时切换（默认简体中文）

---

## [0.3.1] — 2026-08

### Added
- 发布包 dmg / pkg 流程（`scripts/package-release.sh`）

---

## [0.2.1] — 2026-08

### Added
- 本机构建测试 App（`scripts/build-test-app.sh`）
- 菜单栏额度卡片、固定窗口、卡片排序、额度检测配置

---

## 发布包

- **二进制**：GitHub [Releases](https://github.com/yancyfeng999-star/smartquota/releases)（不入库）
- **说明与校验和**：`releases/Mac/`、`releases/Windows/`

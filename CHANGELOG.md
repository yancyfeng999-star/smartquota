# Changelog

All notable changes to **智额 · SmartQuota** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

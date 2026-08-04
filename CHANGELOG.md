# Changelog

All notable changes to **智额 · SmartQuota** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.2] — 2026-08-04

### Added
- 产品全量品牌：**智额 · SmartQuota**（Bundle ID `com.smartquota.app`）
- 开源文档：`LICENSE`（MIT）、`NOTICE`、`CONTRIBUTING.md`、`SECURITY.md`
- 配置目录：`~/.smartquota`；密钥写入本机 Keychain

### Security
- 移除 Sparkle 远程自动更新
- 收紧 entitlements；扩展脚本不得逃逸目录；Web/健康检查仅 http(s)
- 开源树不硬编码个人会员档位（`defaultPlanLabels` 为空）

### Changed
- 核心四会员默认开启探测入口：ChatGPT (Codex)、Kimi、MiniMax、Grok
- 其余内置会员默认关闭（设置中开启）
- 多语言运行时切换（默认简体中文）

## [0.3.1] — 2026-08

### Added
- 发布包 dmg / pkg 流程（`scripts/package-release.sh`）

## [0.2.1] — 2026-08

### Added
- 本机构建测试 App（`scripts/build-test-app.sh`）
- 菜单栏额度卡片、固定窗口、卡片排序、额度检测配置

---

发布包与说明见 `releases/`。

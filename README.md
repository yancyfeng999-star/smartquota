# 智额 · SmartQuota

**本机 AI 会员额度监控** — macOS 菜单栏应用。

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **版本** | 0.3.2（构建号见 `Sources/App/Info.plist`） |
| **系统** | macOS 15+ |
| **形态** | 菜单栏主界面（测试构建可显示 Dock 图标） |
| **许可证** | [MIT](./LICENSE) |

本地读取各 AI 客户端 / CLI 的登录态与公开额度 API，在菜单栏汇总展示。  
**不建云账号、不上报密钥与用量、不内置任何用户的账户或会员信息。**

---

## 功能概览

- **菜单栏一览**：会员额度卡片（5 小时 / 7 天 / 总额、状态、套餐与续费）
- **会员开关**：启用后才在主界面与「额度检测配置」中出现
- **额度检测配置**：说明各会员如何探测，支持检测连接（成功 / 失败）
- **固定窗口**：可钉在桌面右侧，避免菜单栏弹窗点外即关
- **卡片排序**：长按进入排序模式，用箭头调整顺序
- **多语言**：简中 / 英 / 日 / 韩 / 俄 / 阿（RTL）/ 法 / 德 / 西 / 葡，设置内即时切换
- **密钥安全**：GitHub / MiniMax / 阿里云等敏感信息写入 **本机 Keychain**（可从旧 UserDefaults 迁移）

### 核心会员（默认开启探测入口）

| 会员 | 探测方式（摘要） |
|------|------------------|
| **ChatGPT (Codex)** | RPC（`codex app-server`）或 API（`~/.codex/auth.json`） |
| **Kimi** | CLI `/usage` 或 Coding API / Cookie |
| **MiniMax** | Coding Plan API + 区域；Key 来自环境变量 / 设置 / `~/.minimax` |
| **Grok** | `~/.grok/auth.json` + xAI billing |

### 扩展会员（默认关闭，设置里开启）

Claude · Gemini · Copilot · Cursor · Antigravity · Z.ai · AWS Bedrock · 阿里云 · Amp · Kiro · Mistral · OpenCode Go · Oh My Pi  

另支持用户扩展：`~/.smartquota/extensions/`（脚本探测）。

---

## 隐私与开源约定

| 会进入仓库的 | **不会**进入仓库的 |
|--------------|-------------------|
| 源码、文档、品牌资源（公开 Logo） | 你的 API Key / Token / Cookie |
| 测试用假数据（`sk-test-…` 等） | `~/.smartquota/settings.json` 中的套餐、开通日、开关 |
| 发布说明与校验和 | 本机 `auth.json`、Keychain 内容 |
| | 个人账号、真实会员档位、截图里的隐私信息 |

**请勿**将 `auth.json`、真实 `sk-*`、含 Token 的配置、或从本机拷出的 `settings.json` 提交到 git 或发给他人。  
套餐名与续费日仅保存在本机，开源默认**不硬编码**任何个人会员档位。

详见 [SECURITY.md](./SECURITY.md)、[NOTICE](./NOTICE)。

---

## 快速开始

### 依赖

- macOS 15+
- 完整 Xcode
- [Tuist](https://tuist.io)

### 一键构建测试 App

```bash
git clone <本仓库 URL>
cd 智额   # 或 clone 后的目录名
./scripts/build-test-app.sh
```

完成后桌面生成 **`智额.app`**，双击启动；菜单栏出现图标。

```bash
# 正式配置本机调试
CONFIG=Release ./scripts/build-test-app.sh

# 打安装包给其他电脑（zip / dmg + 说明）
./scripts/package-release.sh
```

发布包在 **`releases/v版本号/`**（二进制默认被 `.gitignore` 忽略，避免把安装包误传上公网）。  
详见 [`releases/README.md`](./releases/README.md) 与 [`docs/DISTRIBUTION.md`](./docs/DISTRIBUTION.md)。

### 不编译、只探测本机四家额度

```bash
python3 scripts/probe_four_providers.py
```

（仅读取**你本机**已有登录态，不向仓库写入任何凭证。）

### Xcode 调试

```bash
tuist generate
open SmartQuota.xcworkspace
# 选 scheme SmartQuota → Cmd+R
```

---

## 使用说明（简）

1. **打开菜单**：点击菜单栏图标  
2. **刷新**：打开菜单时会刷新已启用会员；也可依赖后台同步（设置内配置间隔）  
3. **设置**：底栏「设置」  
   - **语言**：切换界面语言  
   - **会员开关**：打开要监控的会员，可**自行**填写套餐名与开通日（仅本机）  
   - **额度检测配置**：仅已开启的会员；查看探测方式并「检测配置」  
   - **日志**：「打开」查看应用日志  
4. **固定窗口**：需要常驻时用固定窗口  
5. **排序**：长按卡片进入排序，完成后点「完成」  

更完整说明见 [`docs/USER_GUIDE.md`](./docs/USER_GUIDE.md)。

---

## 配置与数据位置（仅本机）

| 路径 | 内容 |
|------|------|
| `~/.smartquota/settings.json` | 主题、语言、会员开关、探测模式、套餐/续费等 |
| Keychain（本应用） | GitHub Token、MiniMax Key、阿里云 Cookie/Key 等 |
| `~/.codex/auth.json` 等 | 各 CLI / 客户端自有登录态（应用只读，不上传） |
| 应用日志目录 | 设置 → 日志 → 打开 |

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [LICENSE](./LICENSE) | MIT 许可证 |
| [NOTICE](./NOTICE) | 第三方依赖与商标声明 |
| [SECURITY.md](./SECURITY.md) | 安全审计：无后门、网络出口、加固项 |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | 贡献指南（含「勿提交隐私」） |
| [CHANGELOG.md](./CHANGELOG.md) | 版本变更 |
| [docs/USER_GUIDE.md](./docs/USER_GUIDE.md) | 用户使用手册 |
| [docs/DEVELOPER.md](./docs/DEVELOPER.md) | 开发与扩展 |
| [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md) | 打包与分发 |
| [PRODUCT.md](./PRODUCT.md) | 产品范围与阶段 |
| [docs/architecture/ARCHITECTURE.md](./docs/architecture/ARCHITECTURE.md) | 分层架构 |
| [Branding/README.md](./Branding/README.md) | 品牌与 Logo |

---

## 工程结构（摘要）

```text
智额/
├── LICENSE / NOTICE / README.md
├── PRODUCT.md / SECURITY.md / CONTRIBUTING.md
├── Project.swift                 ← Tuist
├── scripts/build-test-app.sh
├── scripts/package-release.sh
├── releases/                     ← 发布说明（大安装包默认不入库）
├── Branding/
├── docs/
└── Sources/
    ├── App/                      ← SwiftUI、设置、L10n、ProviderCatalog
    ├── Domain/                   ← QuotaMonitor、各 Provider 模型
    └── Infrastructure/           ← Probe、Keychain、JSON 设置、网络
```

新增内置会员：实现 Domain Provider + Infrastructure Probe，再在 `ProviderCatalog` 与 `ProviderConfigRegistry` 注册。详见开发文档。

---

## 默认行为

- 核心四会员探测入口：**默认开启**（需本机已有对应登录态才会显示有效额度）  
- 其它内置会员：从未配置过时 **默认关闭**  
- 套餐名 / 开通日：**空**，由用户在设置中自行填写  
- 默认选中会员：`codex`（ChatGPT）  
- 界面默认语言：**简体中文**  

---

## 许可与声明

- 本项目源码以 **[MIT License](./LICENSE)** 发布。  
- 第三方 Swift 包见 [NOTICE](./NOTICE)。  
- **非** Anthropic / OpenAI / 月之暗面 / MiniMax / xAI 等官方应用；使用各服务须遵守其服务条款。  
- 无远程自动更新通道；安装包由你自行构建或从本仓库 Release 获取。  
- 版权字符串：`Sources/App/Info.plist` → `NSHumanReadableCopyright`。

# 智额 · SmartQuota

**本机 AI 会员额度监控** — 跨平台客户端（Mac 菜单栏 / Windows 托盘）。

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **macOS** | **0.3.30** (build 33) · 菜单栏 · Swift / Tuist · macOS 15+ |
| **Windows** | **0.5.0** · 系统托盘 · Tauri 2 · Setup.exe · Win 10/11 |
| **许可证** | [Apache-2.0](./LICENSE) |
| **仓库** | [github.com/yancyfeng999-star/smartquota](https://github.com/yancyfeng999-star/smartquota) |

本地读取各 AI 客户端 / CLI 的登录态与公开额度 API，在菜单栏（Mac）或托盘（Windows）汇总展示。  
**不建云账号、不上报密钥与用量、不后台静默更新**（用户点「检查更新」后可一键装 pkg）。

> **当前状态（2026-08-18）**：Mac 源码版本为 v0.3.30（build 33）。本次候选修复将菜单栏刷新入口统一为“刷新全部已启用会员”；最后已发布安装包仍为 v0.3.29。源码、文档和 Release 状态以实际证据为准。

---

## 下载安装（推荐）

### macOS 最新已发布版本

**Release：** [v0.3.29](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.29)

当前发布包为 v0.3.29（build 32）。

| 文件 | 用法 |
|------|------|
| [SmartQuota-0.3.29.dmg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.29/SmartQuota-0.3.29.dmg) | 打开后把 **智额.app** 拖到 Applications（推荐） |
| [SmartQuota-0.3.29.pkg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.29/SmartQuota-0.3.29.pkg) | 双击安装向导 / 应用内一键静默更新 |

- 系统：**macOS 15.0+**
- 首次打开若提示「无法验证开发者」：**Control + 点击 → 打开**，或 **系统设置 → 隐私与安全性 → 仍要打开**
- 已安装用户：设置里点 **检查更新** → 优先下载 **pkg** 并静默安装后自动重启（无二次确认）

### Windows

**Release：** [windows-v0.1.0](https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0)（安装包）  
源码与能力已推进至 **0.5.0**，新 Setup.exe 需在 Windows 上 `npm run tauri:build` 产出后上传。

| 文件 | 用法 |
|------|------|
| [SmartQuota-Setup-0.1.0-x64.exe](https://github.com/yancyfeng999-star/smartquota/releases/download/windows-v0.1.0/SmartQuota-Setup-0.1.0-x64.exe) | 双击安装（约 2.2MB） |

---

## 功能概览

### 核心

- **额度卡片**：统一展示 **5H · 7D · 总额**、状态色、套餐与续费日  
- **核心四会员（默认开）**：ChatGPT (Codex) · Kimi · MiniMax · Grok  
- **扩展会员（默认关）**：Claude、Gemini、Copilot、Cursor 等，设置中开启  
- **本机密钥**：Mac Keychain / Windows 凭据管理器  
- **固定窗口 / 排序 / 告警阈值 / 临近重置提醒**  
- **用户扩展**：`~/.smartquota/extensions`（manifest + 脚本）

### Mac 0.3.30 源码变化

- 菜单栏只保留一个刷新入口，统一刷新全部已启用会员。

### Mac 0.3.29 已发布亮点

- **静默更新（对齐智余）**：解包 `.pkg` → 退出后覆盖 → 自动打开；**无确认框、无管理员密码**  
- 日志：`~/Library/Logs/SmartQuota/update.log`

### 隐私

- 探测在本机完成；不上传用量、密钥、套餐与账单  
- 详见 [SECURITY.md](./SECURITY.md)

---

## 仓库结构

```text
智额/
├── Apps/
│   ├── Mac/              ← macOS 应用（Swift / Tuist）
│   └── Windows/          ← Windows 应用（Tauri / React / Rust）
├── Branding/             ← Logo 与品牌资源
├── docs/                 ← 用户手册、架构、分发、Windows
├── releases/
│   ├── Mac/              ← 版本说明 / SHA256（二进制见 GitHub Release）
│   └── Windows/
├── README.md             ← 本文件
├── PRODUCT.md            ← 产品范围与阶段
├── CHANGELOG.md          ← 版本变更
├── LICENSE / NOTICE / SECURITY / CONTRIBUTING
└── .github/workflows/    ← CI（build / test / release / windows）
```

详见 [`docs/REPO_LAYOUT.md`](./docs/REPO_LAYOUT.md)。

---

## 快速开始（开发）

### macOS

```bash
cd Apps/Mac
tuist generate
./scripts/build-test-app.sh      # 桌面调试 App
./scripts/package-release.sh     # dmg/pkg → ../../releases/Mac/v*
```

依赖：macOS 15+、Xcode、[Tuist](https://tuist.io)。

### Windows

```bash
cd Apps/Windows
npm install
npm run tauri:dev      # 开发
npm run tauri:build    # Setup.exe（需 Windows）
```

依赖：Node 20+、Rust、WebView2、MSVC Build Tools。

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [docs/USER_GUIDE.md](./docs/USER_GUIDE.md) | 用户手册（安装、界面、设置、FAQ） |
| [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md) | 打包、GitHub Release、Gatekeeper |
| [docs/DEVELOPER.md](./docs/DEVELOPER.md) | 开发、分层、加会员、测试 |
| [docs/WINDOWS.md](./docs/WINDOWS.md) | Windows 技术栈与路径 |
| [docs/WINDOWS_PARITY.md](./docs/WINDOWS_PARITY.md) | Windows ↔ Mac 对齐 |
| [PRODUCT.md](./PRODUCT.md) | 产品原则与范围 |
| [CHANGELOG.md](./CHANGELOG.md) | 版本历史 |
| [Apps/Mac/README.md](./Apps/Mac/README.md) | Mac 构建 |
| [Apps/Windows/README.md](./Apps/Windows/README.md) | Windows 构建 |
| [SECURITY.md](./SECURITY.md) | 安全与隐私 |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | 贡献与隐私红线 |
| [LICENSE](./LICENSE) | 仓库自有代码与文档的 Apache-2.0 授权 |
| [NOTICE](./NOTICE) | 第三方依赖、商标、资源和隐私边界 |
| [docs/REPOSITORY_GOVERNANCE.md](./docs/REPOSITORY_GOVERNANCE.md) | 分支、PR、CI、依赖与发布治理 |
| [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) | 社区参与行为准则 |
| [PROJECT_STATUS.md](./PROJECT_STATUS.md) | 当前版本、已完成项与未验证项 |

完整目录：[docs/README.md](./docs/README.md)

---

## 开源范围与治理

- 本仓库自有代码、文档和脚本采用 [Apache License 2.0](./LICENSE)。
- Swift Package Manager 依赖和随包资源保留各自的许可证与版权要求，详见 [NOTICE](./NOTICE)；它们不因为被本项目引用就自动变成 Apache-2.0。
- ChatGPT、Claude、Gemini、Copilot、Cursor、Grok、Kimi、MiniMax、AWS、GitHub 等名称和标识归各自权利人所有；智额是非官方本机工具，不代表任何厂商。
- 应用连接的第三方服务仍受其自身服务条款和隐私政策约束；Apache-2.0 只授权本仓库适用范围内的内容。
- 安全问题请先阅读 [SECURITY.md](./SECURITY.md)，功能问题和改进建议请遵守 [CONTRIBUTING.md](./CONTRIBUTING.md)；Issue、PR、截图和日志不得包含真实账号、邮箱、Token、Cookie、Keychain 内容或额度数据。
- 公开文档和依赖声明在发布前由 `scripts/check-open-source-docs.sh` 校验；检查失败时不创建 Release。

---

## 发版说明（维护者）

1. 改 `Apps/Mac/Sources/App/Info.plist` 版本号 / build  
2. `Apps/Mac/scripts/package-release.sh`  
3. 上传 GitHub Release（**资产名用 ASCII**：`SmartQuota-x.y.z.dmg` / `.pkg`）
4. 更新 `CHANGELOG.md`、`releases/Mac/LATEST*`、用户/开发者/发布文档
5. 运行 `./scripts/check-open-source-docs.sh`，确认许可证、NOTICE、依赖锁文件、链接、版本和敏感信息检查通过

安装包 **不入库**（见 `.gitignore`），仅 Release 分发。

---

## 许可

本仓库自有代码和文档采用 Apache-2.0；完整授权见 [LICENSE](./LICENSE)，第三方声明见 [NOTICE](./NOTICE)。
本项目不授予任何第三方服务、账号、接口或商标的使用权；智额不是各 AI 厂商官方应用，各商标归权利人所有。

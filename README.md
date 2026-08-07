# 智额 · SmartQuota

**本机 AI 会员额度监控** — 跨平台客户端（Mac 菜单栏 / Windows 托盘）。

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **macOS** | **0.3.17** (build 20) · 菜单栏 · Swift / Tuist · macOS 15+ |
| **Windows** | **0.5.0** · 系统托盘 · Tauri 2 · Setup.exe · Win 10/11 |
| **许可证** | [MIT](./LICENSE) |
| **仓库** | [github.com/yancyfeng999-star/smartquota](https://github.com/yancyfeng999-star/smartquota) |

本地读取各 AI 客户端 / CLI 的登录态与公开额度 API，在菜单栏（Mac）或托盘（Windows）汇总展示。  
**不建云账号、不上报密钥与用量、不静默自动安装更新。**

> **当前状态（2026-08）**：本阶段功能已交付，仓库与 GitHub Release 已同步，**项目暂时完结**。后续可按需继续加会员、公证签名或 Windows 发版。

---

## 下载安装（推荐）

### macOS 最新版

**Release：** [v0.3.17](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.17)

| 文件 | 用法 |
|------|------|
| [SmartQuota-0.3.17.dmg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.17/SmartQuota-0.3.17.dmg) | 打开后把 **智额.app** 拖到 Applications（推荐） |
| [SmartQuota-0.3.17.pkg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.17/SmartQuota-0.3.17.pkg) | 双击安装向导 |

- 系统：**macOS 15.0+**
- 首次打开若提示「无法验证开发者」：**Control + 点击 → 打开**，或 **系统设置 → 隐私与安全性 → 仍要打开**
- 已安装 ≤ 0.3.11 的用户：设置里点 **检查更新** → 自动下载 dmg → 打开后拖到 Applications

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

### Mac 0.3.17 亮点

- **状态栏默认 Logo**：菜单栏默认显示品牌图标；设置可开启「状态栏额度图标」（绿柱 / 感叹三角）  
- **总额（全渠道）**：真月额度优先；否则续费日线性递减  
- **检查更新**：读 GitHub Releases → 下载 dmg/pkg → 打开安装器  

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
| [PROJECT_STATUS.md](./PROJECT_STATUS.md) | 本阶段完结状态 |

完整目录：[docs/README.md](./docs/README.md)

---

## 发版说明（维护者）

1. 改 `Apps/Mac/Sources/App/Info.plist` 版本号 / build  
2. `Apps/Mac/scripts/package-release.sh`  
3. 上传 GitHub Release（**资产名用 ASCII**：`SmartQuota-x.y.z.dmg` / `.pkg`）  
4. 更新 `CHANGELOG.md`、`releases/Mac/LATEST*`  

安装包 **不入库**（见 `.gitignore`），仅 Release 分发。

---

## 许可

MIT · 见 [LICENSE](./LICENSE) 与 [NOTICE](./NOTICE)。  
非各 AI 厂商官方应用；各商标归权利人所有。

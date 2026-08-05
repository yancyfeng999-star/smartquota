# 智额 · Windows 版方案（已选型）

> 状态：**技术栈与安装形态已拍板**  
> 日期：2026-08-04  
> 对照：macOS 智额 0.3.2

---

## 0. 已定决策

| 项 | 决定 |
|----|------|
| **安装形态** | 经典 **安装包 `.exe`**（双击 Setup → 向导 → 装到「程序文件」/ 用户目录） |
| **技术栈** | **Tauri 2 + TypeScript + React** |
| **打包工具** | Tauri 内置 **NSIS** → 产出 `SmartQuota-Setup-x.y.z-x64.exe` |
| **运行形态** | 系统托盘常驻；可选开机启动 |
| **与 macOS** | 同品牌、同 `UsageSnapshot` 规格；**独立实现**，不移植 SwiftUI |

不选 Electron：安装包与内存都更大，对本机读文件/起 CLI 没有本质优势。  
不选纯 C# WinUI：与 macOS 侧规格共享成本更高，且当前团队已有 TS/Web 与本地工具链经验可复用。

---

## 1. 用户拿到的是什么

```text
SmartQuota-Setup-0.1.0-x64.exe     ← 用户下载并双击
  └─ NSIS 安装向导（中文）
       ├─ 安装目录（默认 %LOCALAPPDATA%\Programs\SmartQuota）
       ├─ 创建开始菜单 / 桌面快捷方式（可选）
       ├─ 开机启动（可选）
       └─ 完成 → 启动 智额（托盘图标）
```

卸载：Windows「设置 → 应用」或开始菜单卸载项（NSIS 标准）。

> 说明：安装包是 **`.exe` 安装器**；装完后主程序也是 `SmartQuota.exe`（托盘应用）。  
> 第一期不做微软商店 MSIX；SmartScreen 可能提示「未知发布者」（无 EV 签名时正常，文档写清）。

---

## 2. 为什么选 Tauri 2

| 维度 | 说明 |
|------|------|
| **安装包体积** | 通常约十几 MB 级（Electron 常 100MB+） |
| **托盘** | 官方 / 社区 tray 插件成熟 |
| **本机能力** | Rust 侧读 `auth.json`、起进程、写配置、调 Credential Manager 干净 |
| **UI** | React 做卡片列表 / 设置，迭代快，视觉可对齐 macOS 信息架构 |
| **安装器** | `tauri build` → **NSIS Setup.exe**，符合「双击 exe 安装」习惯 |
| **安全叙事** | 与产品「本机优先、不上传」一致；无强制远程更新也可控 |

技术分层：

```
┌─────────────────────────────────────────┐
│  React UI（托盘弹出层 / 设置窗）          │
│  卡片、开关、检测配置、语言               │
└──────────────────┬──────────────────────┘
                   │ IPC (命令 / 事件)
┌──────────────────▼──────────────────────┐
│  Rust Core（Tauri commands）             │
│  · 读 settings.json                     │
│  · Probes：HTTP + 读 auth 文件           │
│  · 密钥：Windows DPAPI / Credential      │
│  · 托盘 / 开机启动 / 日志                │
└─────────────────────────────────────────┘
```

---

## 3. 目录与配置（Windows）

| 用途 | 路径 |
|------|------|
| 配置 | `%USERPROFILE%\.smartquota\settings.json`（与 macOS 键名尽量对齐） |
| 扩展脚本 | `%USERPROFILE%\.smartquota\extensions\` |
| 日志 | `%LOCALAPPDATA%\SmartQuota\Logs\SmartQuota.log` |
| 安装目录 | `%LOCALAPPDATA%\Programs\SmartQuota\`（单用户，免管理员） |
| 密钥 | Windows Credential Manager，服务名 `SmartQuota` |

> 安装默认 **不写 `Program Files`**，避免每次升级要 UAC；需要「为所有用户安装」可作为安装器第二选项后期再加。

---

## 4. MVP 功能（第一期可装可卖演示）

### 做

- 安装包：`SmartQuota-Setup-*.exe`（NSIS，中文向导）
- 托盘图标 + 左键弹出额度列表 + 刷新
- 设置窗：会员开关、语言（中/英）、检测连接、日志打开
- 探针（优先纯文件/API，不啃浏览器 Cookie）：
  1. **ChatGPT (Codex)** — `%USERPROFILE%\.codex\auth.json`
  2. **MiniMax** — API Key（设置里填，DPAPI 存）
  3. **Grok** — `%USERPROFILE%\.grok\auth.json`
  4. **Copilot**（可选）— GitHub Token
- 开机启动（可选勾选）
- 固定小窗（可选，MVP 可只做托盘弹层）

### 不做（第一期）

- 浏览器 Cookie / kimi-desktop 专用路径
- Claude Hook 会话条
- 与 macOS 配置云同步
- 微软商店上架
- 自动静默更新（可后接自建 appcast 或仅提示下载新 Setup.exe）

---

## 5. 仓库结构（Mac / Windows 平级）

**原则：两端同等地位，不把 Windows 塞在 Mac 工程下面。**

```text
智额/                              ← 仓库根（产品名，平台无关）
│
├── Apps/                          ← 各端应用（平级）
│   ├── Mac/                       ← macOS 智额
│   │   ├── Sources/               # Swift：App / Domain / Infrastructure
│   │   ├── Tests/
│   │   ├── Tuist/  Project.swift
│   │   ├── scripts/               # build-test-app / package-release
│   │   └── README.md              # 仅 Mac 构建说明
│   │
│   └── Windows/                   ← Windows 智额（与 Mac 同级）
│       ├── src/                   # React UI
│       ├── src-tauri/             # Rust + 探针 + 托盘
│       ├── package.json
│       ├── tauri.conf.json
│       └── README.md              # 仅 Windows 构建 / Setup.exe 说明
│
├── Branding/                      ← 双端共用 Logo / 图标源
├── docs/                          ← 双端共用文档
│   ├── WINDOWS.md
│   ├── USER_GUIDE.md
│   └── probe-contracts/           # 后续：UsageSnapshot 契约
├── releases/                      ← 发布索引（也可按平台分子目录）
│   ├── Mac/                       # dmg/pkg 说明与校验和
│   └── Windows/                   # Setup.exe 说明与校验和
├── LICENSE / NOTICE / README.md   ← 仓库总入口
└── .github/                       ← CI（可分 mac / windows job）
```

| 端 | 源码位置 | 安装包产物（构建后） |
|----|----------|----------------------|
| **Mac** | `Apps/Mac/` | `Apps/Mac` 构建 → `releases/Mac/` 或 GitHub Release 的 dmg/pkg |
| **Windows** | `Apps/Windows/` | `…/bundle/nsis/SmartQuota_x.y.z_x64-setup.exe` → `releases/Windows/` 或 GitHub Release |

> **现状**：Mac 已迁入 `Apps/Mac/`；Windows 脚手架在 `Apps/Windows/`。  
> **目标**：根目录为共用物 + `Apps/{Mac,Windows}`，两端路径对称。

发布：GitHub Release 同一产品，资产名 ASCII（`SmartQuota-0.3.2.dmg` / `SmartQuota-Setup-0.1.0-x64.exe`）。

---

## 6. 安装器细节（NSIS）

| 项 | 建议 |
|----|------|
| 语言 | 简体中文（+ 英文可选） |
| 产品名 | 智额（显示）/ SmartQuota（内部/可执行文件） |
| 图标 | 复用 `Branding/` |
| 权限 | 默认 per-user，无需管理员 |
| 升级 | 覆盖安装同目录；保留 `.smartquota` 配置 |
| 签名 | 有证书则 `signtool` 签 Setup.exe + 主程序；暂无则文档写 SmartScreen 处理 |

用户首次运行若被 SmartScreen 拦：

1. 「仍要运行」  
2. 或：属性 → 解除锁定（若从 zip 下）  
安装器本身也会被拦时同样处理。

---

## 7. 探针优先级与路径

| 会员 | Windows 路径 / 方式 | MVP |
|------|---------------------|-----|
| Codex | `%USERPROFILE%\.codex\auth.json` + 官方 usage API | ✅ |
| Grok | `%USERPROFILE%\.grok\auth.json` + billing API | ✅ |
| MiniMax | 设置 API Key + 区域 | ✅ |
| Copilot | Token + GitHub API | 可选 |
| Kimi | API Key 优先（Cookie 二期） | 二期 |
| Claude / Cursor | 路径适配二期 | 二期 |

`UsageSnapshot` 字段与 macOS Domain 对齐（剩余%、窗口类型、状态、重置时间），便于双端同一套卡片文案。

---

## 8. 里程碑粗估（1 人）

| 阶段 | 交付 | 人周 |
|------|------|------|
| M0 | Tauri 脚手架 + 托盘 Hello + 空卡片 + NSIS 能装上 | 1 |
| M1 | Codex + MiniMax + Grok 真探针 + 设置 + Key 存储 | 2–3 |
| M2 | 中文安装向导打磨、日志、开机启动、Release 上传 | 1 |
| M3 | 更多会员 / 固定窗 / 更新提示 | 2+ |

**约 4–6 周**可出「能双击 Setup.exe 安装并用核心探针」的内测版。

---

## 9. 开发环境（Windows 机器）

- Windows 10/11 x64  
- Node.js 20+  
- Rust stable  
- WebView2（Win11 自带；Win10 安装器可引导）  
- Visual Studio Build Tools（MSVC）  
- （可选）代码签名证书  

macOS 上可写 UI/部分逻辑，**NSIS 安装包最终在 Windows CI 或 Windows 实体机 `tauri build` 产出**。

---

## 10. 与 macOS 发布并列

| 平台 | 用户下载 |
|------|----------|
| macOS | `SmartQuota-x.y.z.dmg` / `.pkg` |
| Windows | **`SmartQuota-Setup-x.y.z-x64.exe`** |

GitHub Release 同一 tag 或分 `v0.1.0-windows`，资产名全程 ASCII。

---

## 11. 实现状态（已落地）

| 项 | 状态 |
|----|------|
| 目录 `Apps/Windows` 与 Mac 平级 | ✅ |
| Tauri 托盘 + 关窗驻留 | ✅ |
| Codex / MiniMax / Grok 真探针 | ✅ |
| 设置 / Key 凭据管理器 / settings.json | ✅ |
| NSIS Setup.exe 配置 | ✅ |
| GitHub Actions `windows.yml` | ✅ |
| 打出安装包 | 在 Windows CI 或本机 `npm run tauri:build` |

### 与 macOS 功能对齐（进行中）

- 状态索引：[`WINDOWS_PARITY.md`](./WINDOWS_PARITY.md)
- 设计规格：[`superpowers/specs/2026-08-05-windows-mac-parity-design.md`](./superpowers/specs/2026-08-05-windows-mac-parity-design.md)
- 对照：Mac 源码约 0.3.10 / 发布 0.3.9；Windows MVP **0.1.0**（缺 Kimi 等）

```bash
cd Apps/Windows
npm install
npm run tauri:build
# → src-tauri/target/release/bundle/nsis/SmartQuota_*_x64-setup.exe
```

# 智额 · SmartQuota

**本机 AI 会员额度监控** — 跨平台客户端（Mac 菜单栏 / Windows 托盘）。

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **macOS** | 15+ · 菜单栏 · Swift |
| **Windows** | 10/11 · 系统托盘 · Tauri · **Setup.exe** |
| **许可证** | [MIT](./LICENSE) |

本地读取各 AI 客户端 / CLI 的登录态与公开额度 API，汇总展示。  
**不建云账号、不上报密钥与用量。**

---

## 仓库结构（Mac / Windows 平级）

```text
智额/
├── Apps/
│   ├── Mac/          ← macOS 应用
│   └── Windows/      ← Windows 应用（Setup.exe）
├── Branding/
├── docs/
├── releases/
│   ├── Mac/
│   └── Windows/
└── LICENSE / README …
```

详见 [`docs/REPO_LAYOUT.md`](./docs/REPO_LAYOUT.md)。

---

## 快速开始

### macOS

```bash
cd Apps/Mac
tuist generate
./scripts/build-test-app.sh
```

打包 dmg/pkg：

```bash
cd Apps/Mac
./scripts/package-release.sh
# 产物 → ../../releases/Mac/v*
```

### Windows

**用户下载安装（推荐）：**  
https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0  

文件：[`SmartQuota-Setup-0.1.0-x64.exe`](https://github.com/yancyfeng999-star/smartquota/releases/download/windows-v0.1.0/SmartQuota-Setup-0.1.0-x64.exe)（约 2.2MB，双击安装）

开发构建：

```bash
cd Apps/Windows
npm install
npm run tauri:dev      # 开发
npm run tauri:build    # 产出 Setup.exe（需 Windows）
```

方案：[`docs/WINDOWS.md`](./docs/WINDOWS.md)。

---

## 功能概览（产品）

- 额度卡片：5 小时 / 7 天 / 总额、状态、套餐与续费  
- 会员开关与额度检测配置  
- 本机密钥安全存储  
- 多语言（Mac 已支持；Windows MVP 先中/英）

### 核心会员

ChatGPT (Codex) · Kimi · MiniMax · Grok（Windows MVP 优先 Codex / MiniMax / Grok）

---

## 文档

| 文档 | 说明 |
|------|------|
| [docs/REPO_LAYOUT.md](./docs/REPO_LAYOUT.md) | 目录规划 |
| [docs/WINDOWS.md](./docs/WINDOWS.md) | Windows 方案 |
| [docs/USER_GUIDE.md](./docs/USER_GUIDE.md) | 用户手册（Mac） |
| [docs/DEVELOPER.md](./docs/DEVELOPER.md) | 开发说明 |
| [Apps/Mac/README.md](./Apps/Mac/README.md) | Mac 构建 |
| [Apps/Windows/README.md](./Apps/Windows/README.md) | Windows 构建 |
| [SECURITY.md](./SECURITY.md) | 安全 |
| [LICENSE](./LICENSE) | MIT |

---

## 许可

MIT · 见 [LICENSE](./LICENSE) 与 [NOTICE](./NOTICE)。  
非各 AI 厂商官方应用。

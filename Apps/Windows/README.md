# 智额 · Windows

Windows 10/11 **系统托盘**应用。  
技术：**Tauri 2 + React + TypeScript + Rust**  
安装包：**NSIS Setup.exe**（双击安装）

与 [`../Mac`](../Mac/) **平级**。

---

## 功能（已实现）

| 能力 | 说明 |
|------|------|
| 托盘常驻 | 左键打开；关闭窗口隐藏到托盘 |
| 额度卡片 | Codex / MiniMax / Grok |
| Codex 探针 | `%USERPROFILE%\.codex\auth.json` + ChatGPT usage API（含 token 刷新） |
| Grok 探针 | `%USERPROFILE%\.grok\auth.json` + billing API（含 token 刷新） |
| MiniMax 探针 | 设置 API Key / 环境变量 / `.minimax\config.yaml` + 区域 |
| 设置 | 会员开关、区域、Key、检测连接、自动刷新 |
| 密钥 | Windows 凭据管理器（`com.smartquota.app`） |
| 配置 | `%USERPROFILE%\.smartquota\settings.json` |

---

## 开发

**依赖：** Node.js 20+、Rust stable、WebView2、MSVC Build Tools（Windows）

```bash
cd Apps/Windows
npm install
npm run tauri:dev      # 开发热重载
npm run tauri:build    # 打 Setup.exe
```

产物：

```text
src-tauri/target/release/bundle/nsis/SmartQuota_0.1.0_x64-setup.exe
```

> **NSIS 安装包必须在 Windows 上 `tauri build`。**  
> 在 macOS 上可改源码；完整打包请用 Windows 机或 GitHub Actions `windows-latest`。

---

## 用户安装后路径

| 用途 | 路径 |
|------|------|
| 程序 | `%LOCALAPPDATA%\Programs\SmartQuota\` |
| 配置 | `%USERPROFILE%\.smartquota\` |
| 日志目录 | `%LOCALAPPDATA%\SmartQuota\Logs\` |

---

## 首次使用

1. 安装并登录 **codex** / **grok** CLI（如需对应卡片）  
2. MiniMax：在设置中粘贴 Coding Plan API Key，选中国/国际  
3. 点「检测」验证连接  

SmartScreen 可能提示未知发布者（未 EV 签名时正常）→「仍要运行」。

---

## 源码结构

```text
Apps/Windows/
├── src/                 # React UI
├── src-tauri/
│   ├── src/
│   │   ├── lib.rs       # 命令 / 托盘
│   │   ├── settings.rs
│   │   ├── secrets.rs
│   │   ├── paths.rs
│   │   ├── models.rs
│   │   └── probes/      # codex / minimax / grok
│   ├── tauri.conf.json  # NSIS
│   └── icons/
└── package.json
```

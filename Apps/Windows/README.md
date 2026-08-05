# 智额 · Windows

Windows 10/11 **系统托盘**应用。  
技术：**Tauri 2 + React + TypeScript + Rust**  
安装包：**NSIS Setup.exe**（双击安装）

与 [`../Mac`](../Mac/) **平级**。当前版本 **0.5.0**（Mac catalog + 壳层能力补齐）。

---

## 功能（0.5.0）

| 能力 | 说明 |
|------|------|
| 托盘常驻 | 左键打开；关闭窗口隐藏到托盘 |
| 核心四会员 | Codex / **Kimi** / MiniMax / Grok（默认开） |
| 扩展会员 | Claude / Gemini / Copilot / Cursor + 其余 catalog（默认关） |
| 额度 meters | 5h / 7d / 额外条；状态阈值与 Mac 一致（50/20/0） |
| 告警 | 阈值偏低 + 临近重置未用完；系统 Toast（可关） |
| 刷新 | 关闭 / 5 / 10 / 15 / 30 分钟（默认 15） |
| 语言 | 简体中文 / English |
| 密钥 | Windows 凭据管理器 |
| 配置 | `%USERPROFILE%\.smartquota\settings.json` |

### 探针路径摘要

| 会员 | Windows 方式 |
|------|----------------|
| Codex | `%USERPROFILE%\.codex\auth.json` |
| Kimi | 设置 sk-kimi Key / `KIMI_API_KEY` |
| MiniMax | Key / 环境变量 / `.minimax\config.yaml` |
| Grok | `%USERPROFILE%\.grok\auth.json` |
| Claude | `claude` CLI `/usage` + 本机 `.claude` |
| Gemini | `%USERPROFILE%\.gemini\oauth_creds.json` |
| Copilot | GitHub Token |
| Cursor | Cursor `state.vscdb` + usage-summary API |

对齐规格：仓库 [`docs/WINDOWS_PARITY.md`](../../docs/WINDOWS_PARITY.md)。

---

## 开发

**依赖：** Node.js 20+、Rust stable、WebView2、MSVC Build Tools（Windows）

```bash
cd Apps/Windows
npm install
npm run tauri:dev      # 开发热重载
npm run tauri:build    # 打 Setup.exe
```

单元测试（Rust）：

```bash
cd Apps/Windows/src-tauri
cargo test --lib
```

产物：

```text
src-tauri/target/release/bundle/nsis/SmartQuota_0.5.0_x64-setup.exe
```

> **NSIS 安装包必须在 Windows 上 `tauri build`。**  
> 在 macOS 上可改源码并 `cargo test`；完整打包请用 Windows 机或 GitHub Actions。

---

## 源码结构

```text
Apps/Windows/
├── src/                 # React UI + i18n
├── src-tauri/
│   ├── src/
│   │   ├── lib.rs
│   │   ├── catalog.rs   # Mac 同序 catalog
│   │   ├── alerts.rs    # QuotaAlertPolicy
│   │   ├── models.rs
│   │   ├── settings.rs
│   │   ├── detect.rs
│   │   └── probes/      # codex/kimi/minimax/grok/claude/…
│   └── tauri.conf.json
└── package.json
```

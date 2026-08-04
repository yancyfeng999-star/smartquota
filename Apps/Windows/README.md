# 智额 · Windows

Windows 10/11 系统托盘应用（**Tauri 2 + React + TypeScript**）。  
与 [`../Mac`](../Mac/) **平级**，同属产品「智额 · SmartQuota」。

## 用户安装包

构建后产出 **NSIS Setup.exe**（双击安装）：

```text
src-tauri/target/release/bundle/nsis/SmartQuota_x.y.z_x64-setup.exe
```

发布到仓库 `releases/Windows/` 或 GitHub Release（文件名用 ASCII）。

## 本机路径（安装后）

| 用途 | 路径 |
|------|------|
| 程序 | `%LOCALAPPDATA%\Programs\SmartQuota\` |
| 配置 | `%USERPROFILE%\.smartquota\` |
| 日志 | `%LOCALAPPDATA%\SmartQuota\Logs\` |

## 开发（需 Windows 或交叉构建环境）

依赖：Node.js 20+、Rust stable、WebView2、MSVC Build Tools。

```bash
cd Apps/Windows
npm install
npm run tauri dev      # 开发
npm run tauri build    # 打 Setup.exe
```

macOS 上可编辑前端与 Rust 源码；**NSIS 安装包请在 Windows CI/实体机 `tauri build` 产出**。

## 方案文档

- 仓库根：[`docs/WINDOWS.md`](../../docs/WINDOWS.md)
- 目录规划：[`docs/REPO_LAYOUT.md`](../../docs/REPO_LAYOUT.md)

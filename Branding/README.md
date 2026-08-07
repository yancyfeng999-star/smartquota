# 智额 · SmartQuota 品牌素材

源文件目录（桌面）：`智额logo/`  
本目录为应用内归档与导出规格。

## 四套主标识（当前使用 · 纯色 monochrome）

自 2026-08 起主标识改为**通用纯色**（单色填充、扁平、无多色分段），对齐工具栏图标语言。

| 文件 | 模式 | 背景 | 用途 |
|------|------|------|------|
| `logo-light-transparent.png` | 浅色 UI | **无**（透明，纯黑标） | 界面 AppLogo（浅色外观） |
| `logo-dark-transparent.png` | 深色 UI | **无**（透明，纯白标） | 界面 AppLogo（深色外观） |
| `logo-light-on-white.png` | 浅色 | **白底**（纯黑标） | **AppIcon / Dock**、宣传方图 |
| `logo-dark-on-black.png` | 深色 | **黑底**（纯白标） | 深色宣传图、文档封面 |

中文别名（符号链接）：

- `智额-浅色-无背景.png`
- `智额-深色-无背景.png`
- `智额-浅色-白底.png`
- `智额-深色-黑底.png`

## 纯色导出与预览

| 文件 | 前景 | 背景 | 用途 |
|------|------|------|------|
| `logo-solid-white-transparent.png` | 纯白 | 透明 | 深色 UI / 工具栏 |
| `logo-solid-black-transparent.png` | 纯黑 | 透明 | 浅色 UI |
| `logo-solid-black-on-white.png` | 纯黑 | 白底 | 文档 / 浅色方图 / AppIcon 源 |
| `logo-solid-white-on-black.png` | 纯白 | 黑底 | 深色方图 |
| `logo-solid-white-on-olive.png` | 纯白 | 橄榄绿 | 风格预览 |
| `logo-solid-preview-toolbar.png` | — | — | 工具栏尺寸预览条 |

完整副本：`solid/`。历史**彩色**主标备份：`colorful-archive/`。

## 源文件备份

`source/` 内含：

- `智额logo源文件.ai`（Illustrator）
- 桌面导出的原始 jpg/png 副本

## 应用引用

| Asset | 内容 |
|-------|------|
| **AppIcon** | 纯色黑标白底，16…1024 全尺寸（`AppIcon.appiconset`） |
| **AppLogo** | 浅色：纯黑透明；深色：纯白透明（`appearances: dark`） |
| **Windows icons** | `Apps/Windows/src-tauri/icons/` 同步纯色方图 / ico / icns |

## 重新导入

若更新了桌面 `智额logo` 下的四张图，可在仓库根目录执行打包脚本里的导入逻辑，或重新运行导入步骤后：

```bash
./scripts/build-test-app.sh
```

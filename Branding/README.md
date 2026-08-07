# 智额 · SmartQuota 品牌素材

源文件目录（桌面）：`智额logo/`  
本目录为应用内归档与导出规格。

## 四套主标识（当前使用 · 彩色）

| 文件 | 模式 | 背景 | 用途 |
|------|------|------|------|
| `logo-light-transparent.png` | 浅色 | **无**（透明） | 界面 AppLogo（浅色外观） |
| `logo-dark-transparent.png` | 深色 | **无**（透明） | 界面 AppLogo（深色外观） |
| `logo-light-on-white.png` | 浅色 | **白底** | **AppIcon / Dock**、宣传方图 |
| `logo-dark-on-black.png` | 深色 | **黑底** | 深色宣传图、文档封面 |

中文别名（符号链接）：

- `智额-浅色-无背景.png`
- `智额-深色-无背景.png`
- `智额-浅色-白底.png`
- `智额-深色-黑底.png`

## 纯色备选（可选，非默认）

`logo-solid-*` 与 `solid/` 为实验性单色导出，**应用默认不使用**。  
彩色原件亦备份于 `colorful-archive/`。

## 源文件备份

`source/` 内含：

- `智额logo源文件.ai`（Illustrator）
- 桌面导出的原始 jpg/png 副本

## 应用引用

| Asset | 内容 |
|-------|------|
| **AppIcon** | 由 `logo-light-on-white.png` 生成 16…1024 全尺寸 |
| **AppLogo** | 浅色：无背景浅色稿；深色：无背景深色稿（`appearances: dark`） |
| **Windows icons** | 与彩色 AppIcon 同源 |

## 重新导入

若更新了桌面 `智额logo` 下的四张图，可在仓库根目录执行打包脚本里的导入逻辑，或重新运行导入步骤后：

```bash
./scripts/build-test-app.sh
```

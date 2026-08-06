# 智额 0.3.13 (build 16)

- **日期**：2026-08-06  
- **标签**：`v0.3.13`  
- **GitHub**：https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.13  

## 本版

- **修复 Grok**：7D 重置后、本周尚无消耗时，xAI 会省略 `creditUsagePercent` / `productUsage`，导致 5H·7D·总额全显示 `-`。现按 `currentPeriod` 视为 0% 已用（7D ≈ 100%，总额可估算）
- Windows 探针同步修复（源码；公开 Windows 安装包仍为既有版本）

## 安装包

| 本机文件 | GitHub 资产名 | 用法 |
|----------|---------------|------|
| 智额-0.3.13.dmg | **SmartQuota-0.3.13.dmg** | 拖到 Applications（推荐） |
| 智额-0.3.13.pkg | **SmartQuota-0.3.13.pkg** | 双击安装向导 |

## 首次打开

若提示无法验证开发者：Control + 点击 → 打开。  
临时签名（ad-hoc）。

## 系统

macOS 15.0 或更高。

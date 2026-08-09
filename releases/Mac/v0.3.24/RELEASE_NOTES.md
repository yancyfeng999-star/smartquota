# 智额 0.3.24 (build 27)

- **日期**：2026-08-09  
- **标签**：`v0.3.24`  

## 本版

- 静默更新与智余 `PackageSilentInstaller` **源码级对齐**  
  - `pkgutil --expand-full`，失败则 `--expand` + Payload  
  - 退出后 `ditto --noqtn` 覆盖，`.preupdate` 挪包  
  - **不请求管理员密码**；不可写仅设置页报错  
  - 日志：`~/Library/Logs/SmartQuota/update.log`

## 安装

| GitHub 资产 | 用法 |
|-------------|------|
| **SmartQuota-0.3.24.dmg** | 拖到 Applications |
| **SmartQuota-0.3.24.pkg** | 应用内静默更新优先 |

已装：设置 → **检查更新**。

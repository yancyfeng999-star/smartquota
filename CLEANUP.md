# 工程标识

智额 · **SmartQuota** 为本仓库正式产品名。

| 项 | 值 |
|----|-----|
| 显示名 | 智额 |
| 英文名 | SmartQuota |
| Bundle ID | `com.smartquota.app` |
| 工程 / scheme | `SmartQuota` |
| 配置目录 | `~/.smartquota` |
| 日志 | `~/Library/Logs/SmartQuota/` |
| Probe 目录 | `~/Library/Application Support/SmartQuota/Probe` |

## 生成工程

```bash
tuist generate --no-open
./scripts/build-test-app.sh
```

`*.xcodeproj` / `*.xcworkspace` 由 Tuist 生成，勿手改；见 `.gitignore`。

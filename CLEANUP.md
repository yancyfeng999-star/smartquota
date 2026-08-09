# 工程标识与清理约定

智额 · **SmartQuota** 为本仓库正式产品名。

| 项 | 值 |
|----|-----|
| 显示名 | 智额 |
| 英文名 | SmartQuota |
| Bundle ID | `com.smartquota.app` |
| 工程 / scheme | `SmartQuota` |
| 配置目录 | `~/.smartquota` |
| 日志 | `~/Library/Logs/SmartQuota/` |

## 生成本机 App（只装一份）

```bash
cd Apps/Mac
tuist generate --no-open
./scripts/build-test-app.sh          # → /Applications/智额.app
# 若必须放到桌面：
# DEST_DIR="$HOME/Desktop" ./scripts/build-test-app.sh
```

`*.xcodeproj` / `*.xcworkspace` 由 Tuist 生成，勿手改；见 `.gitignore`。

## 发版

```bash
cd Apps/Mac
./scripts/package-release.sh
# 产出 releases/Mac/vX.Y.Z/
#   智额-X.Y.Z.dmg / .pkg
#   SmartQuota-X.Y.Z.dmg / .pkg   ← 上传 GitHub 用
#   SHA256SUMS.txt / SHA256SUMS-github.txt
```

上传 GitHub 时优先 **SmartQuota-*** 文件名（应用内更新按此优先匹配）。

## 本机可删（不入库）

| 路径 | 说明 |
|------|------|
| `Apps/Mac/.build/` | 本地 DerivedData，可随时删 |
| `Apps/Mac/Derived/` | Tuist 派生，可删 |
| `Apps/Windows/node_modules/` / `src-tauri/target/` | 依赖缓存 |
| `releases/Mac/v*/` 下旧 `.dmg`/`.pkg` | 二进制不入库；磁盘可只留最近 1–2 版 |
| 桌面 `智额.app` / `智额-发布/` | 测完可删，正式用 Applications |
| 根目录 `task_plan.md` / `findings.md` / `progress.md` | 本地草稿（已 gitignore） |

## 避免「多个智额」

1. 日常只从 **应用程序** 打开  
2. 不要长期保留桌面 `.app` + Applications 双份  
3. 打开过的 **dmg 卷** 用完请推出  
4. 编译产物 `.app` 不必拷贝到桌面  

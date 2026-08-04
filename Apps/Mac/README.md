# 智额 · Mac

macOS 菜单栏应用（Swift / Tuist）。

## 构建

```bash
cd Apps/Mac
tuist generate
./scripts/build-test-app.sh          # 桌面调试 App
./scripts/package-release.sh         # dmg/pkg → 仓库 releases/Mac/
```

依赖：macOS 15+、Xcode、[Tuist](https://tuist.io)。

更多：仓库根 `docs/DEVELOPER.md`、`docs/DISTRIBUTION.md`。

# 智额 · Mac

macOS **菜单栏**应用。  
技术：**Swift / SwiftUI / Tuist**  
当前版本：**0.3.15**（build 18）

与 [`../Windows`](../Windows/) **平级**。

---

## 功能摘要

| 能力 | 说明 |
|------|------|
| 菜单栏常驻 | 无 Dock 图标（发布包）；点 × 只关面板 |
| 核心四会员 | Codex / Kimi / MiniMax / Grok（默认开） |
| 扩展会员 | Claude / Gemini / Copilot / Cursor 等（默认关） |
| 额度 | **5H · 7D · 总额**；状态阈值；续费日着色 |
| 检查更新 | GitHub Releases → 下载 dmg → 打开（手动触发） |
| 密钥 | macOS Keychain |
| 配置 | `~/.smartquota/` |
| 多语言 | 10 种（设置内切换） |

---

## 构建

```bash
cd Apps/Mac
tuist generate
./scripts/build-test-app.sh          # 桌面调试 App
./scripts/package-release.sh         # dmg/pkg → ../../releases/Mac/v*
```

依赖：macOS 15+、Xcode、[Tuist](https://tuist.io)。

测试：

```bash
# 在 Xcode 中运行 Domain / Infrastructure / Acceptance schemes
# 或 tuist test（若已配置）
```

---

## 源码结构

```text
Apps/Mac/
├── Sources/
│   ├── App/              # SwiftUI、设置、卡片、本地化
│   ├── Domain/           # 纯领域模型（Provider / Update / Session…）
│   └── Infrastructure/   # 探针、Keychain、GitHub 更新下载
├── Tests/
├── scripts/
│   ├── build-test-app.sh
│   └── package-release.sh
├── Project.swift
└── Tuist/
```

---

## 发版

1. 改 `Sources/App/Info.plist` 版本与 build  
2. `./scripts/package-release.sh`  
3. 上传 GitHub：资产名 **SmartQuota-x.y.z.dmg / .pkg**（ASCII）  
4. 更新根 `CHANGELOG.md`、`releases/Mac/LATEST*`  

详见 [`docs/DISTRIBUTION.md`](../../docs/DISTRIBUTION.md)。

更多：[`docs/DEVELOPER.md`](../../docs/DEVELOPER.md)、[`docs/USER_GUIDE.md`](../../docs/USER_GUIDE.md)。

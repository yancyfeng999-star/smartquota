# 仓库目录规划（Mac / Windows 平级）

## 原则

1. **两端同等位置**：`Apps/Mac` 与 `Apps/Windows` 平级。  
2. **共用 vs 端专属**：品牌、文档、协议在根；各端工程在 `Apps/` 下。  
3. **名字直观**：Mac / Windows。

---

## 当前结构（已落地）

```text
智额/
├── Apps/
│   ├── README.md
│   ├── Mac/                          # macOS 智额
│   │   ├── Sources/  Tests/  Tuist/
│   │   ├── Project.swift  Tuist.swift
│   │   ├── scripts/                  # build-test-app / package-release
│   │   ├── CLAUDE.md  .claude/       # Mac 端 agent 技能
│   │   └── README.md
│   └── Windows/                      # Windows 智额
│       ├── src/                      # React UI
│       ├── src-tauri/                # Rust + 托盘 + NSIS
│       ├── package.json
│       └── README.md
├── Branding/
├── docs/
├── releases/
│   ├── Mac/                          # v0.3.2 等（dmg/pkg 二进制默认不入库）
│   └── Windows/                      # Setup.exe 发布说明位
├── .github/workflows/                # Mac CI working-directory: Apps/Mac
├── LICENSE  NOTICE  README.md …
└── PRODUCT.md  SECURITY.md …
```

---

## 对照表

| 东西 | 位置 |
|------|------|
| macOS 源码 | `Apps/Mac/` |
| Windows 源码 | `Apps/Windows/` |
| 共用 Logo | `Branding/` |
| 共用文档 | `docs/` |
| Mac 发布索引 | `releases/Mac/` |
| Windows 发布索引 | `releases/Windows/` |
| 用户配置 Mac | `~/.smartquota/` |
| 用户配置 Win | `%USERPROFILE%\.smartquota\` |
| 用户程序 Win | `%LOCALAPPDATA%\Programs\SmartQuota\` |

---

## 构建入口

```bash
# Mac
cd Apps/Mac
tuist generate
./scripts/build-test-app.sh
./scripts/package-release.sh   # → releases/Mac/

# Windows（在 Windows 机或 Win CI）
cd Apps/Windows
npm install
npm run tauri:build            # → NSIS Setup.exe
```

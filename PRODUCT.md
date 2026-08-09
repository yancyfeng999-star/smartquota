# 智额 · SmartQuota — 产品说明

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **一句话** | 本机 AI 会员额度，一眼看完 |
| **平台** | macOS 15+ 菜单栏 · Windows 托盘（Apps 平级） |
| **Mac 版本** | **0.3.20**（build 23） |
| **Windows 版本** | **0.5.0**（源码；Setup 发布包见 Release） |
| **状态** | **本阶段完结**（2026-08） |

---

## 要解决什么问题

开发者同时订阅多家 AI（ChatGPT、Kimi、MiniMax、Grok、Claude…），额度分散在各网页与 CLI 里。智额在菜单栏 / 托盘汇总**本机可读的**额度与重置节奏，不替代各厂商后台，只做「本地探针 + 展示」。

---

## 产品原则

1. **本机优先**：读本地登录态 / CLI / Keychain，不建云账号。  
2. **可开关**：只监控你打开的会员，避免噪音。  
3. **可解释**：设置里写清「如何检测」，可一键测连接。  
4. **可扩展**：内置 catalog + 用户脚本扩展。  
5. **可本地化**：默认中文，设置内切换多语言。  
6. **更新可控**：可手动检查 GitHub 新版本并下载安装包；**不做静默自动安装**。

---

## 范围

### 做

| 能力 | 说明 |
|------|------|
| 额度卡片 | **5H / 7D / 总额**、状态、套餐与续费展示 |
| 核心 4 会员 | ChatGPT、Kimi、MiniMax、Grok（默认开） |
| 扩展会员 | Claude、Gemini、Copilot、Cursor 等（默认关） |
| 设置 | 外观、语言、开关、检测配置、后台同步、日志、检查更新 |
| 固定窗口 / 排序 | 常驻查看、长按排序 |
| 告警 | 阈值偏低、临近重置未用完（可关） |
| 脚本扩展 | `~/.smartquota/extensions/` |
| 分发 | Mac dmg/pkg · Windows Setup.exe · GitHub Release |

### 不做（当前）

- 官方账号体系、云端同步额度  
- 代理支付、自动充值  
- 完整 IDE / Agent 工作台（仅额度监控）  
- Sparkle / 静默后台强制更新  
- 未公证签名的「零 Gatekeeper 警告」（可选后续 Developer ID）

---

## 阶段

| 阶段 | 状态 | 内容 |
|------|------|------|
| **A 本地可测** | ✅ | `build-test-app.sh` → 桌面 `智额.app` |
| **B 产品化** | ✅ | 多会员、多语言、Keychain、文档与 Mac/Windows 平级 |
| **C 正式分发** | ✅ | `package-release.sh` → dmg/pkg；GitHub Release；手动检查更新 |
| **D 本阶段完结** | ✅ | 文档齐全、源码入库、持续小版本热修（现 v0.3.20） |

```bash
cd Apps/Mac
./scripts/build-test-app.sh          # 本机调试
./scripts/package-release.sh         # 打安装包
```

安装与分发：[`docs/DISTRIBUTION.md`](./docs/DISTRIBUTION.md)  
下载入口：[README 下载安装](./README.md#下载安装推荐)

---

## 体验要点

- 主路径：**菜单栏 → 卡片列表 → 设置**  
- 视觉：额度摘要卡，主列 **5H · 7D · 总额**  
- 默认语言：简体中文  
- 发布包为菜单栏后台应用（`LSUIElement`）；点 × 只关面板，**退出**才结束进程  

---

## 成功标准（本阶段）

- [x] 核心四会员本机可探测、可配置  
- [x] 扩展会员可开关  
- [x] Mac 安装包可分发；GitHub Release ASCII 资产  
- [x] 设置内检查更新 → 下载 → 打开 dmg  
- [x] Windows 托盘 MVP + catalog 对齐推进  
- [x] 开源文档与隐私边界写清  

---

## 后续可选（非本阶段）

- Apple Developer ID 签名 + 公证  
- Windows 0.5.0 Setup 正式上传 Release  
- 更多厂商探针 / 报表卡  
- 应用商店分发（若需要）

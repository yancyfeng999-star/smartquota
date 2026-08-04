# 智额 · SmartQuota — 产品说明

| | |
|--|--|
| **中文名** | 智额 |
| **英文名** | SmartQuota |
| **一句话** | 本机 AI 会员额度，一眼看完 |
| **平台** | macOS 15+ 菜单栏 · Windows 托盘（Apps 平级） |
| **当前版本** | 0.3.2（见 `Sources/App/Info.plist`） |

---

## 要解决什么问题

开发者同时订阅多家 AI（ChatGPT、Kimi、MiniMax、Grok、Claude…），额度分散在各网页与 CLI 里。智额在菜单栏汇总**本机可读的**额度与重置节奏，不替代各厂商后台，只做「本地探针 + 展示」。

---

## 产品原则

1. **本机优先**：读本地登录态 / CLI / Keychain，不建云账号。  
2. **可开关**：只监控你打开的会员，避免噪音。  
3. **可解释**：设置里写清「如何检测」，可一键测连接。  
4. **可扩展**：内置 catalog + 用户脚本扩展。  
5. **可本地化**：默认中文，设置内切换多语言。  

---

## 范围

### 做

| 能力 | 说明 |
|------|------|
| 额度卡片 | 5H / 7d / 总额、状态、套餐与续费展示 |
| 核心 4 会员 | ChatGPT、Kimi、MiniMax、Grok（默认开） |
| 扩展会员 | Claude、Gemini、Copilot、Cursor 等（默认关） |
| 设置 | 外观、语言、开关、检测配置、后台同步、日志 |
| 固定窗口 / 排序 | 常驻查看、长按排序 |
| 脚本扩展 | `~/.smartquota/extensions/` |

### 不做（当前）

- 官方账号体系、云端同步额度  
- 代理支付、自动充值  
- 完整 IDE / Agent 工作台（仅额度监控）  
- 远程自动更新 / 云端账号  


---

## 阶段

| 阶段 | 状态 | 内容 |
|------|------|------|
| **A 本地可测** | ✅ 当前 | `build-test-app.sh` → 桌面 `智额.app` |
| **B 产品化** | 进行中 | 多会员、多语言、Keychain、文档与拆分 |
| **C 正式分发** | ✅ 可用 | `package-release.sh` → zip/dmg；可选 Developer ID 公证 |

```bash
cd Apps/Mac
Apps/Mac/scripts/build-test-app.sh          # 本机调试
Apps/Mac/scripts/package-release.sh         # 打安装包给别人
```

安装与分发说明：[`docs/DISTRIBUTION.md`](./docs/DISTRIBUTION.md)

---

## 体验要点

- 主路径：**菜单栏 → 卡片列表 → 设置**  
- 视觉：liquid glass 风格额度摘要卡  

- 默认语言：简体中文  
- 测试包：Dock 可见（`LSUIElement=false`），便于双击确认启动  

---

## 成功标准（阶段 A/B）

- [x] 双击可启动，菜单栏可用  
- [x] 核心四会员可探测（依赖本机凭证）  
- [x] 设置可开关会员、检测连接  
- [x] 语言可切换  
- [x] 密钥进 Keychain  
- [ ] 正式签名分发包（阶段 C）  

---

## 文档

- 用户：[docs/USER_GUIDE.md](./docs/USER_GUIDE.md)  
- 开发：[docs/DEVELOPER.md](./docs/DEVELOPER.md)  
- 入口：[README.md](./README.md)  

---

## 品牌与合规

- 应用内显示名：**智额**  
- 英文产品名：**SmartQuota**  
- Logo：`Branding/`  
- 许可证：**MIT**（见 `LICENSE`、`NOTICE`）  
- 非各 AI 厂商官方客户端；使用各服务须遵守其服务条款  
- **不包含**任何真实用户账户、会员档位或密钥；套餐/开通日仅用户本机填写  


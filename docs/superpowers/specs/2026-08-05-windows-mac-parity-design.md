# 智额 Windows ↔ Mac 功能对齐设计

| | |
|--|--|
| **状态** | 待评审（规格阶段，未开工实现） |
| **日期** | 2026-08-05 |
| **Mac 对照** | 源码 `CFBundleShortVersionString` **0.3.10** (build 13)；发布包最新 **0.3.9** |
| **Windows 现状** | **0.1.0** MVP（Tauri 2 + React + Rust） |
| **范围** | 差距清单、同步策略、分阶段交付、数据合约、非目标 |
| **负责人** | Windows 端开发（本规格约束后续实现） |

---

## 1. 目标与原则

### 1.1 产品目标

让 Windows 用户获得与 Mac **同等的核心产品体验**：本机可读 AI 会员额度一览、可开关、可检测、可配置，不建云账号、不上报密钥与用量。

### 1.2 技术原则（与 `docs/WINDOWS.md` 一致）

1. **独立实现**：不移植 SwiftUI / Domain Swift 代码；在 Tauri/Rust/React 中复刻**行为与合约**。
2. **合约优先**：`UsageSnapshot` / 卡片字段 / 状态语义与 Mac Domain 对齐，便于文案与测试共用。
3. **本机优先**：Credential Manager / 本地 auth 文件 / 用户填写 Key；禁止硬编码个人会员档位。
4. **渐进交付**：按里程碑发 Setup.exe，而不是等「全量会员」才发布。
5. **Windows 路径适配**：`%USERPROFILE%\.codex` 等；浏览器 Cookie 类路径二期再做。

### 1.3 明确非目标（本对齐工程）

| 不做 | 原因 |
|------|------|
| 共享 Rust/Swift 二进制核心 | 重写成本高，两端 UI 宿主不同 |
| 配置云同步 Mac↔Windows | 产品原则「本机优先」 |
| 微软商店 MSIX 上架 | 另立项 |
| 完整移植 Mac 菜单栏 Live Activity / 复杂 Chrome | Windows 托盘信息架构不同 |
| 一次上线全部 17 个 Mac 会员 | 周期失控；按优先级分批 |
| Cookie 深度抓取（Kimi Desktop 专用等） | Windows MVP 优先 API Key / CLI 文件 |

---

## 2. 现状快照

### 2.1 Mac（源码 0.3.10 / 发布 0.3.9）

| 层 | 内容 |
|----|------|
| 架构 | App / Domain / Infrastructure；Tuist；大量单元测试 |
| 核心会员（默认开） | `codex`, `kimi`, `minimax`, `grok` |
| 扩展会员（默认关） | claude, gemini, copilot, cursor, antigravity, zai, bedrock, alibaba, ampcode, kiro, mistral, opencode-go, omp |
| 额度模型 | `UsageSnapshot` → `[UsageQuota]`；类型：session / weekly / modelSpecific / timeLimit |
| 状态 | healthy / warning / critical / depleted（阈值 50 / 20 / 0） |
| 产品能力 | 阈值告警、临近重置「未用完」提醒、额外 meters、省电刷新档位、多语言、Keychain、脚本扩展、固定窗、卡片排序、日报类报告卡等 |
| 近期提交 | threshold alerts、near-reset、extra quota meters、idle CPU/IO 优化 |

### 2.2 Windows（0.1.0）

| 层 | 内容 |
|----|------|
| 架构 | React UI + Rust Tauri commands + `probes/*` |
| 会员 | **仅** `codex`, `minimax`, `grok`（**缺 Kimi**） |
| 额度模型 | `QuotaCard` + `Vec<QuotaMeter>`（label / remainingPercent / resetText） |
| 状态 | healthy / warning / critical / depleted / unknown / error / disabled / setup |
| 已有 | 托盘、设置开关、plan 自填、检测连接、DPAPI/Credential、自动刷新秒数、检查更新、NSIS、CI `windows.yml` |
| 缺失 | 核心四齐、告警、Mac 级刷新枚举、多语言真正切换 UI、扩展会员、扩展脚本、固定窗、排序等 |

---

## 3. 差距矩阵

### 3.1 会员 / 探针

| Provider | Mac | Windows | Windows 适配要点 | 建议阶段 |
|----------|-----|---------|------------------|----------|
| ChatGPT (Codex) | ✅ | ✅ | 已有 auth.json + usage API；核对 extra meters / 文案 | W1 校准 |
| MiniMax | ✅ | ✅ | API Key + 区域；对齐 meters 标签 | W1 校准 |
| Grok | ✅ | ✅ | `.grok\auth.json` + billing | W1 校准 |
| **Kimi** | ✅ CLI/API | ❌ | **优先 API**：`sk-kimi` → coding usages；Credential 存 Key；Cookie 二期 | **W1 必做** |
| Claude | ✅ | ❌ | CLI + API；路径 Windows 适配 | W3 |
| Gemini | ✅ | ❌ | 本地/API 探针 | W3 |
| Copilot | ✅ | ❌ | Token + GitHub API（文档已标可选） | W3 |
| Cursor | ✅ | ❌ | 本地状态文件 | W3 |
| 其余 catalog | ✅ | ❌ | 按需求与可探测性排序 | W4+ |
| 用户脚本扩展 | ✅ `~/.smartquota/extensions` | ❌ | 可跑可发现本地脚本 | W4 |

### 3.2 数据合约

| 能力 | Mac | Windows | 差距 |
|------|-----|---------|------|
| 多窗口 meters | `UsageQuota` 列表（session/weekly/extra） | `meters[]` 已有，但类型弱（仅 label 字符串） | 缺稳定 `quotaKey` / `kind`；启发式从 label 猜 session/weekly |
| 重置时间 | `resetsAt: Date?` + `resetText` | 仅 `resetText` 字符串 | 告警与 urgency 需要可解析时间 |
| 状态阈值 | 50/20/0 | 40/20/0（`status_from_remaining`） | **与 Mac 不一致**，应对齐 50/20/0 |
| 套餐名 | 用户填写 / 空默认 | 用户填写 | 已对齐原则 |
| 账户信息 | email / org 等 | 无 | W2 可选展示 |
| 美元额度 | dollarRemaining/Used/Cap | 无 | 扩展会员需要时再加 |

### 3.3 产品壳 / UX

| 能力 | Mac | Windows | 建议阶段 |
|------|-----|---------|----------|
| 托盘/菜单栏常驻 | ✅ 菜单栏 | ✅ 托盘 | 已有 |
| 额度卡片列表 | ✅ | ✅ 基础 | W1 强化多 meters + 状态色 |
| 会员开关 | ✅ | ✅ | 扩展 catalog 时沿用 |
| 检测连接 | ✅ | ✅ | 每增 provider 补 detect |
| 语言中/英 | ✅ 运行时 | settings 有字段，UI 硬编码中文 | W2 |
| 刷新策略 | off/5/10/15/30 分；默认 15 分 | 原始秒数，默认 300s | W2 对齐枚举 |
| 阈值告警 | ✅ 系统通知 | ❌ | W2 |
| 临近重置提醒 | ✅ | ❌ | W2 |
| 重置 urgency 着色 | ✅ | ❌ | W2 |
| 固定小窗 | ✅ | ❌（托盘弹层为主） | W3 可选 |
| 卡片排序 | ✅ | ❌ | W3 |
| 开机启动 | 产品规划 | 文档写了，实现需确认 | W2 核对 |
| 检查更新 | Sparkle 曾有/现策略不同 | GitHub releases 检查 | 保持 Windows 方案 |
| 日志打开 | ✅ | ✅ 路径打开 | 已有 |
| 性能（空闲 CPU/IO） | 近期优化 | 未专项 | W2 随刷新策略 |

### 3.4 工程 / 发布

| 项 | Mac | Windows | 建议 |
|----|-----|---------|------|
| 版本号 | 0.3.10 源码 | 0.1.0 | 对齐采用 **独立版本线**（见 §5），不强制同号 |
| 测试 | Domain/Infra/Acceptance 大量 | 几乎无自动化 | W1 起：Rust 解析单测 + 关键 UI 冒烟 |
| CI | build/tests/release | `windows.yml` | 保持；W1 后加 probe 单测 job |
| 文档 | USER_GUIDE 偏 Mac | WINDOWS.md + README | 同步写 USER_GUIDE Windows 小节 |

---

## 4. 三种同步路径（方案对比）

### 方案 A — 行为对齐、分波交付（**推荐**）

- 以 Mac 为**产品规格源**，Windows 独立实现。
- 先核心四 + 合约修正，再告警/刷新，再扩展会员。
- **优点**：风险可控、每波可发 Setup.exe、符合现有架构。  
- **缺点**：短期 Windows 功能仍少于 Mac 全量 catalog。

### 方案 B — 抽取跨端 probe 合约仓库

- 新建 `docs/probe-contracts` + 可选共享 JSON Schema；两端对照生成测试 fixture。
- **优点**：长期双端一致性最好。  
- **缺点**：前期文档/测试基建重；不直接产生用户功能。  
- **用法**：可作为方案 A 的**横切配套**（W1 起写合约，不必单独大项目）。

### 方案 C — 一次冲刺全量 catalog

- 并行移植全部 Mac providers。  
- **优点**：纸面上「同步完成」。  
- **缺点**：质量与 Windows 路径未知风险高；告警/合约未稳时叠加爆炸。  
- **不推荐**作为第一阶段。

**选定：方案 A + 方案 B 的轻量合约文档。**

---

## 5. 版本与里程碑

Windows 与 Mac **版本号独立**（平台构建节奏不同），但发布说明中写明「对齐 Mac 行为版本」。

| 里程碑 | Windows 版本目标 | 对齐 Mac 能力 | 验收标准 |
|--------|------------------|---------------|----------|
| **W0** | 文档 | 本规格 + 差距矩阵 | 本文评审通过 |
| **W1** | **0.2.0** | 核心四：+Kimi；状态阈值对齐；meters 合约增强；三探针校准 | 本机有凭证时可出 Codex/Kimi/MiniMax/Grok 卡；无凭证为 setup 非 crash |
| **W2** | **0.3.0** | 刷新枚举、阈值告警、临近重置、UI 中英、重置 urgency | 设置可配阈值；低额度/临近重置可系统通知（可关） |
| **W3** | **0.4.0** | 扩展会员第一批：Claude / Gemini / Copilot / Cursor（默认关） | 开关后可探测或清晰 setup 指引 |
| **W4** | **0.5.0+** | 其余 catalog + 扩展脚本 + 固定窗/排序（按需） | 按子规格裁剪 |

> 说明：不把 Windows 版本号硬改成 0.3.9，避免用户误以为安装包与 Mac 二进制同源。

---

## 6. 目标架构（Windows）

保持现有分层，**增强而非推倒**：

```text
Apps/Windows/
├── src/                          # React：卡片、设置、i18n
│   ├── App.tsx                   # 逐步拆分为 components/*
│   ├── i18n/                     # zh-Hans / en
│   └── types.ts                  # 与 Rust serde 对齐的 TS 类型
└── src-tauri/src/
    ├── models.rs                 # QuotaMeter / QuotaCard / Snapshot（增强）
    ├── settings.rs               # catalog、告警阈值、刷新枚举
    ├── secrets.rs                # + Kimi key 等
    ├── detect.rs                 # 每 provider 一条
    ├── alerts.rs                 # 纯规则（对齐 QuotaAlertPolicy）+ 通知调用
    ├── probes/
    │   ├── mod.rs                # 注册表 + probe_provider
    │   ├── codex.rs | minimax.rs | grok.rs | kimi.rs
    │   └── ...                   # W3+ 扩展
    ├── lib.rs                    # commands / tray
    └── update.rs
```

### 6.1 增强后的 IPC 合约（W1）

```ts
// QuotaMeter — 对齐 Mac UsageQuota 的可序列化子集
type QuotaMeter = {
  key: string;              // "session" | "weekly" | "model:opus" | "time:Monthly" | legacy label hash
  kind: "session" | "weekly" | "model" | "time" | "unknown";
  label: string;            // 展示用，如「5 小时」「7 天」
  remainingPercent: number | null;
  resetText: string | null;
  resetsAtUnix?: number | null;  // 秒；告警用
};

// QuotaCard — 保持现有字段，meters 用增强结构
// status 阈值：与 Mac 一致 remaining → depleted≤0, critical<20, warning<50, else healthy
```

**兼容**：旧 settings.json 无新字段时默认填充；UI 对缺 `kind` 的 meter 回退 label 启发式。

### 6.2 Kimi（W1）探测策略

优先级（与 Mac 一致，Windows 先落地可测路径）：

1. **API Key**（`sk-kimi-...`）：设置填写 → Credential Manager；  
   `GET https://api.kimi.com/coding/v1/usages`（5h + weekly）；可选 agent-gw 月额度。  
2. **环境变量** / 本地配置文件（若存在公开约定路径）。  
3. **CLI** `kimi`（若 PATH 可用）— 可选，W1 可后置。  
4. **浏览器 Cookie** — 明确 **W2+ / 不做首期**。

Detect：有 Key 或可解析 token → `ready`；否则 `setup` + how_to。

### 6.3 告警（W2）规则（移植 `QuotaAlertPolicy`）

| Kind | 条件（默认） |
|------|----------------|
| sessionLow | session remaining ≤ 20% |
| weeklyLow | weekly remaining ≤ 20% |
| weeklyUnderuseNearReset | weekly remaining ≥ 40% 且距 weekly 重置 ≤ 24h |

- 用户可关总开关；可改阈值。  
- 防抖：同一 provider+kind 在重置前只通知一次（或冷却 N 小时）。  
- 实现：Rust 评估 + Windows toast（`tauri-plugin-notification` 或 WinRT）；托盘 tooltip 可同步摘要。

### 6.4 刷新（W2）

对齐 Mac `RefreshInterval`：

- UI：关闭 / 5 / 10 / 15 / 30 分钟（去掉 1 分钟热轮询）。  
- 默认：15 分钟。  
- settings 存秒数或枚举字符串，兼容现有 `refreshIntervalSecs`。

---

## 7. 测试策略

| 层级 | W1 | W2 | W3 |
|------|----|----|-----|
| Rust 解析单测 | Codex/Kimi/MiniMax/Grok fixture JSON → meters | AlertPolicy 纯函数 | 新 provider 解析 |
| 手动冒烟 | 无凭证 setup；有凭证真机 | 改阈值触发通知 | 开关扩展会员 |
| CI | `cargo test` on windows-latest | + 通知相关单测 | 按需 |

禁止在仓库提交真实 token；fixture 脱敏。

---

## 8. 文档交付物（本阶段）

| 文件 | 用途 |
|------|------|
| 本文 | 主设计规格 |
| `docs/WINDOWS.md` | 增加「对齐状态」小节（链到本文） |
| `task_plan.md` / `findings.md` / `progress.md`（仓库根） | 执行时磁盘记忆（实现阶段使用） |
| 后续 `docs/superpowers/plans/2026-08-05-windows-w1-implementation.md` | 用户批准规格后由 writing-plans 产出 |

---

## 9. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 厂商 API 变更 | 探针隔离；fixture 回归；错误信息引导用户重登/改 Key |
| Windows 无 Cookie 可读 | Kimi 首期 Key-only；文案写清 |
| 全量会员期望过高 | 里程碑透明；PRODUCT/README 标明 Windows 已支持列表 |
| 告警吵 | 默认阈值保守 + 总开关 + 冷却 |
| 仅 macOS 开发、无 Windows 真机 | CI 打 Setup.exe；关键探针用 mock；真机验收清单给用户 |

---

## 10. 成功标准（整体对齐完成时）

- [ ] Windows 核心四会员与 Mac 同开关默认、同状态语义、同多 meters 展示能力  
- [ ] Kimi 在 Windows 可通过 API Key 稳定出卡  
- [ ] 阈值告警 / 临近重置可配置且可关  
- [ ] 刷新档位与 Mac 省电策略一致  
- [ ] 扩展会员可分批开启，默认不噪音  
- [ ] 每里程碑有可下载 Setup.exe + RELEASE 说明写清对齐点  
- [ ] 安全：密钥进 Credential Manager；无云账号；无硬编码个人套餐  

---

## 11. 规格自检

| 检查 | 结果 |
|------|------|
| 占位符 TBD | 无；阶段边界明确 |
| 内部一致 | 方案 A + 轻量合约；版本独立 |
| 范围 | 本文 = 对齐总纲；实现另出 W1 plan |
| 歧义 | 「同步」= 行为/合约对齐，非二进制同源；版本号独立 |

---

## 12. 请评审人确认

1. 是否同意 **方案 A（分波）**，W1 = 核心四 + 合约校准？  
2. 是否同意 Windows **独立版本线**（0.2 / 0.3…）而非强行 0.3.9？  
3. Kimi 首期是否接受 **仅 API Key**（不做 Cookie）？  
4. W3 扩展会员第一批是否固定为 Claude / Gemini / Copilot / Cursor？

确认后进入 **W1 实现计划**（`writing-plans`），再动代码。

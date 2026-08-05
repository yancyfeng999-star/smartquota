# Windows ↔ Mac 对齐状态

| 平台 | 版本 | 说明 |
|------|------|------|
| **macOS** | ~0.3.10 | 产品规格源 |
| **Windows** | **0.5.0** | 探针 / 壳层 / 扩展已全面补齐 |

## 能力清单

### 核心（默认开）

| ID | 实现 |
|----|------|
| codex | auth.json + usage API + token refresh |
| kimi | sk-kimi API + env + local config（Mac coding path） |
| minimax | Key / env / config.yaml + 区域 |
| grok | auth.json + billing + refresh |

### 扩展（默认关）

| ID | 实现 |
|----|------|
| claude | `claude /usage` Mac 级解析（% used/left、Extra usage、/cost） |
| gemini | oauth_creds + Cloud Code Assist API |
| copilot | GitHub Internal API + PAT |
| cursor | state.vscdb + usage-summary（sqlite3/扫描） |
| zai | Claude settings / Key + quota/limit API |
| alibaba | DashScope API coding plan 5h/7d/月 |
| ampcode | `amp usage` 解析 |
| kiro | kiro-cli `/usage` 解析 |
| opencode-go | `opencode db` 费用窗口 |
| omp | `omp usage --json` |
| mistral | Vibe `~/.vibe/logs/session` 今日用量 |
| antigravity | 进程检测 + 本地端口扫描 |
| bedrock | AWS CLI list models + 可选 Cost Explorer |

### 产品壳

- 阈值告警 + 临近重置 Toast（可配置）
- 刷新 0/5/10/15/30 分
- 中/英 i18n
- **窗口置顶（固定）**
- **卡片排序 ↑↓**
- **用户扩展** `~/.smartquota/extensions`（manifest.json + script / healthCheck）
- 凭据管理器密钥

## 测试

```bash
cd Apps/Windows/src-tauri && cargo test --lib   # 8 passed
```

## 构建 Setup.exe

```bash
cd Apps/Windows && npm run tauri:build   # 需 Windows
```

## 已知环境差异（非缺功能）

| 项 | 说明 |
|----|------|
| macOS Live Activity / 菜单栏百分比 | 平台专有，Windows 用托盘 + 主窗 |
| Antigravity 端口 | Windows 扫描常用端口；Mac 用 PID 精确发现 |
| 部分 CLI | 依赖本机是否安装（claude/amp/omp/opencode/aws） |

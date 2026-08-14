# 项目状态

| 字段 | 值 |
|------|-----|
| **日期** | 2026-08-14 |
| **Mac** | 源码 **0.3.29** (build 32) · 最后已发布 [Release v0.3.28](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.28) |
| **Windows** | 源码 0.5.0；公开安装包见 [windows-v0.1.0](https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0) |
| **状态** | 可日常使用；v0.3.29 源码候选；通用能力与开源治理持续推进 |

## 已完成

- [x] Mac 菜单栏额度监控（核心四会员 + 扩展 catalog）  
- [x] 额度 UI：5H / 7D / 总额、阈值、续费日  
- [x] **检查更新 → pkg 解包 + 退出后覆盖**（无确认框、无管理员密码）  
- [x] dmg/pkg 打包与 GitHub Release（ASCII `SmartQuota-*` 资产名）  
- [x] Windows 托盘 MVP 与 catalog 对齐推进  
- [x] 开源治理基线：Apache-2.0 / NOTICE / README / 用户手册 / 分发 / 开发 / 安全 / 变更日志

## 当前进行中

- [ ] 通用 Mac 能力：首次引导、诊断、刷新控制、迁移/备份、恢复、无障碍和性能保护。
- [ ] 公开仓库治理：Issue/PR 模板、依赖锁文件、NOTICE 自动核对和 CI/Release 门禁。

当前仓库的稳定版本、签名、公证、安装和远端 Release 状态必须分别以实际证据确认；源码或文档更新不自动等于已发布。

## 不在本阶段

- Apple Developer ID 公证  
- Windows 0.5.0 新 Setup 上传（需 Windows 机打包）  
- 应用商店上架  

## 本机只保留一份 App

| 用途 | 路径 |
|------|------|
| **日常使用（唯一）** | `/Applications/智额.app` |
| 开发调试 | `./scripts/build-test-app.sh` → 默认覆盖 Applications |
| 发版安装包 | `releases/Mac/vX.Y.Z/` + GitHub Release（**不要**长期留桌面 `.app`） |

## 下次开工

1. `git pull`  
2. [PRODUCT.md](./PRODUCT.md)  
3. 发版：[docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)  

# 项目状态

| 字段 | 值 |
|------|-----|
| **日期** | 2026-08-18 |
| **Mac** | **0.3.30** (build 33) · 已发布 [Release v0.3.30](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.30) |
| **Windows** | 源码 0.5.0；公开安装包见 [windows-v0.1.0](https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0) |
| **状态** | 可日常使用；v0.3.30 已发布；P2 更新通道与诊断上报仍未默认启用 |

## 已完成

- [x] Mac 菜单栏额度监控（核心四会员 + 扩展 catalog）  
- [x] 额度 UI：5H / 7D / 总额、阈值、续费日  
- [x] **检查更新 → pkg 解包 + 退出后覆盖**（无确认框、无管理员密码）
- [x] dmg/pkg 打包与 GitHub Release（ASCII `SmartQuota-*` 资产名）
- [x] Mac 通用能力：首次引导、手动刷新/取消、诊断、导入导出、备份恢复、兼容性、无障碍、帮助、迁移与安全模式恢复
- [x] Windows 托盘 MVP 与 catalog 对齐推进
- [x] 开源治理基线：Apache-2.0 / NOTICE / README / 用户手册 / 分发 / 开发 / 安全 / 变更日志
- [x] v0.3.30 打包并发布 GitHub Release（DMG / PKG / SHA256）

## 当前进行中

- [ ] P2 更新增强：Beta 更新通道、自动更新开关；崩溃报告和匿名诊断上报需先完成隐私同意与脱敏设计。

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

# 项目状态

| 字段 | 值 |
|------|-----|
| **日期** | 2026-08-11 |
| **Mac** | **0.3.26** (build 29) · [Release v0.3.26](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.26) |
| **Windows** | 源码 0.5.0；公开安装包见 [windows-v0.1.0](https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0) |
| **状态** | 可日常使用；按需热修 |

## 已完成

- [x] Mac 菜单栏额度监控（核心四会员 + 扩展 catalog）  
- [x] 额度 UI：5H / 7D / 总额、阈值、续费日  
- [x] **检查更新 → pkg 解包 + 退出后覆盖**（无确认框、无管理员密码）  
- [x] dmg/pkg 打包与 GitHub Release（ASCII `SmartQuota-*` 资产名）  
- [x] Windows 托盘 MVP 与 catalog 对齐推进  
- [x] 开源文档：README / 用户手册 / 分发 / 开发 / 安全 / 变更日志  

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

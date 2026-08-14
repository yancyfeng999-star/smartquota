# 贡献指南 · Contributing

感谢关注 **智额 · SmartQuota**。

## 开始之前

1. 阅读 [README.md](./README.md)、[docs/DEVELOPER.md](./docs/DEVELOPER.md)。  
2. 遵守 [SECURITY.md](./SECURITY.md)：不要引入遥测、硬编码密钥或远程更新后门。  
3. 遵守下方 **隐私红线**。

## 隐私红线（必读）

**绝对不要**把下列内容提交进本仓库或 Pull Request：

- 个人或公司的 API Key、Token、Cookie、OAuth 刷新令牌  
- 本机 `~/.smartquota/settings.json`、`~/.codex/auth.json`、`~/.grok/auth.json` 等  
- 真实套餐名、开通日、账单金额、邮箱、手机号、账号 ID  
- 含个人额度数字的截图 / 录屏（可打码后再用）  
- 签名证书（`.p12` / `.pem`）、公证日志中的私密字段  

测试请使用明显假数据，例如 `sk-test-key-123`、`test-token`。

`ProviderCatalog.defaultPlanLabels` 在开源树中保持为空；若需演示套餐名，在本地设置里填写，不要写回源码。

## 开发流程建议

```bash
tuist generate
open SmartQuota.xcworkspace
# 修改 → 运行测试（Domain / Infrastructure / Acceptance schemes）
./scripts/build-test-app.sh   # 可选：打出桌面测试 App
```

- 新功能：优先 Domain 模型 + 测试，再 Infrastructure probe，最后 App UI。  
- 新会员：见 `.claude/skills/add-provider/` 与 `docs/DEVELOPER.md`。  
- 提交信息：说明「改了什么、为什么」；中英文均可。

## Pull Request

1. 基于最新 `main` 开分支。  
2. 保持改动聚焦；大重构请单独 PR。  
3. 确认未误加 `releases/**/*.dmg`、`.app`、密钥文件（见 `.gitignore`）。  
4. 若涉及安全边界，在 PR 描述里写明网络出口与本地读写范围。

## 许可

贡献代码默认同意以本仓库 [MIT License](./LICENSE) 授权，并接受 [NOTICE](./NOTICE) 中的第三方声明。

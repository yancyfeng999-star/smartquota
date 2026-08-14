# 贡献指南 · Contributing

感谢关注 **智额 · SmartQuota**。本项目是本机优先的开源工具，欢迎修复问题、改进文档、增加测试和提交可维护的功能。

开始贡献前，请先阅读：

1. [README.md](./README.md)：项目范围、安装方式和当前状态。
2. [docs/DEVELOPER.md](./docs/DEVELOPER.md)：工程结构、构建、测试和 Provider 约定。
3. [SECURITY.md](./SECURITY.md)：安全边界、网络出口和漏洞报告方式。
4. [LICENSE](./LICENSE) 与 [NOTICE](./NOTICE)：仓库授权和第三方声明。
5. [docs/REPOSITORY_GOVERNANCE.md](./docs/REPOSITORY_GOVERNANCE.md) 与 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)：协作、分支、发布和行为准则。

## 隐私红线（必读）

绝对不要把下列内容提交进本仓库、Issue、Pull Request、截图或日志：

- 个人或公司的 API Key、Token、Cookie、OAuth 刷新令牌、Keychain 导出或认证文件原文。
- 本机 `~/.smartquota/settings.json`、`~/.codex/auth.json`、`~/.grok/auth.json` 等运行时文件。
- 真实套餐名、开通日、账单金额、邮箱、手机号、账号 ID 或额度明细。
- 未打码的真实截图、录屏、崩溃日志、终端输出、路径或 Release 资产。
- 签名证书、`.p12` / `.pem`、公证日志中的私密字段、CI secret 或环境变量文件。

测试和文档请使用明显的占位数据，例如 `test-token`、`sk-test-key-123`、`user@example.com`。示例数据不得与真实用户相似到足以造成误认。

`ProviderCatalog.defaultPlanLabels` 在开源树中保持为空；套餐名称、续费日期和账号信息只能在本机设置中填写。

## 本地开发

环境要求：macOS 15+、完整 Xcode、Swift 6、Tuist。

```bash
cd Apps/Mac
tuist install
tuist generate --no-open
open SmartQuota.xcworkspace
```

常用验证：

```bash
cd Apps/Mac
tuist test
./scripts/build-test-app.sh
cd ../..
./scripts/check-open-source-docs.sh
```

如果工程生成或测试依赖本机 CLI、Keychain、浏览器 Cookie、真实网络或签名证书，请使用 mock/fixture，并在 PR 中明确写出未验证的运行环境；不要把真实凭证带入测试。

## 改动规则

- 新功能优先补 Domain 模型和测试，再接 Infrastructure，最后接 App UI。
- 用户可见文字进入 `Apps/Mac/Sources/App/Localization/L10n.swift`，不要在 SwiftUI 视图中散落硬编码文案。
- Provider 改动必须说明读取的本地路径、网络端点、凭证来源、失败状态和日志脱敏方式。
- 同一 Provider 的多账号逻辑必须保持邮箱/外部 ID 匹配规则，不得因一次读不到就覆盖或清空旧账号快照。
- 不要为了修复 Mac 文档或 UI 顺手改 Windows、计费、远端服务或发布凭证。
- 新增依赖时必须同时更新 `Apps/Mac/Tuist/Package.swift`、`Apps/Mac/Tuist/Package.resolved`、`NOTICE`、开发文档和 CHANGELOG，并说明许可证兼容性。
- 新增图标、字体、截图、示例数据或生成文件时必须在 PR 中写明来源、许可证和是否随 App 分发；没有来源证据的资源不要提交。

## Pull Request

请基于最新 `main` 创建分支，并保持每个 PR 主题单一。PR 描述至少包含：

- 改了什么、为什么改、影响哪些平台/模块。
- 复现步骤、测试命令和结果；如果无法运行真实 App，明确写出未验证项。
- 是否改变本地读写、网络出口、权限、Keychain、更新行为或公开隐私承诺。
- 是否改变依赖、第三方许可证、商标、资源来源或文档链接。
- 对用户可见功能，附对应用户文档、开发文档和 CHANGELOG 更新。

提交前检查：

- [ ] 没有加入 `releases/**/*.dmg`、`.app`、密钥、证书、运行时配置或真实账号数据。
- [ ] `./scripts/check-open-source-docs.sh` 通过。
- [ ] `git diff --check` 通过。
- [ ] 相关单元/基础设施/Acceptance 测试通过，或已说明环境限制。
- [ ] README、NOTICE、SECURITY、文档索引和版本号没有相互矛盾。

仓库中的 Issue/PR 模板会要求脱敏环境和复现信息；请不要把凭证贴到任何公开字段。

## 许可证与贡献授权

仓库自有代码、文档和脚本采用 [Apache License 2.0](./LICENSE)。提交贡献时，你应当拥有相应权利，并同意该贡献按本仓库 Apache-2.0 发布；本仓库当前不要求额外 CLA，也不通过贡献指南引入未声明的商业附加条款。

第三方代码必须保留其原许可证和版权声明，并在 [NOTICE](./NOTICE) 中登记。不能把复制来的第三方代码、字体、图标或截图直接标成 Apache-2.0。

## 安全问题

安全漏洞、真实凭证泄露和隐私问题不要发到公开 Issue。请按 [SECURITY.md](./SECURITY.md) 的私密报告流程提交，并只提供脱敏后的复现信息。普通功能问题和文档建议再使用 Issue 模板。

# 开源仓库治理

本文档定义智额 · SmartQuota 的公开仓库协作、依赖、发布和隐私治理规则。当前 Mac 源码版本为 0.3.29（build 32），最后一个已发布 Release 为 v0.3.28。仓库自有代码、文档和脚本采用 [Apache License 2.0](../LICENSE)；第三方依赖、资源、商标和服务边界见 [NOTICE](../NOTICE)。

## 1. 权威来源

- 授权正文：根目录 [LICENSE](../LICENSE)。
- 第三方声明和锁定依赖：[NOTICE](../NOTICE) 与 Apps/Mac/Tuist/Package.resolved。
- 当前 Mac 版本：Apps/Mac/Sources/App/Info.plist 的 CFBundleShortVersionString；README、用户手册和 Release 文档必须与它一致。
- 产品范围：[PRODUCT.md](../PRODUCT.md)。
- 当前完成度和未验证项：[PROJECT_STATUS.md](../PROJECT_STATUS.md)。
- 安全、网络出口和本地数据边界：[SECURITY.md](../SECURITY.md)。
- 用户安装与开发流程：[docs/USER_GUIDE.md](./USER_GUIDE.md) 和 [docs/DEVELOPER.md](./DEVELOPER.md)。

文档只能描述已经由源码、测试、CI 或实际 Release 证据支持的行为。不能把“计划中”“本地实现”“构建成功”写成“已发布”“已签名”“已公证”或“所有用户设备均验证”。

## 2. 分支和 Pull Request

### 2.1 推荐的 GitHub 设置

仓库管理员应在 GitHub 的 Rulesets/Branch protection 中配置以下规则；本文件记录要求，不假设当前 GitHub 设置已经自动完成：

1. main 禁止直接推送、强制推送和删除；所有变更通过 Pull Request 进入。
2. Pull Request 必须通过 Mac Build and Verify (Mac)、Mac Unit Tests with Coverage (Mac) 和 Windows 对应 CI；治理检查必须作为这些工作流的前置步骤。
3. 合并前要求至少一名维护者审查；涉及凭证、网络出口、更新、公证、依赖许可证或隐私声明时，必须在 PR 中明确写出影响和回滚方式。
4. 要求分支在合并前保持最新，关闭未解决的审查线程；不使用绕过保护规则的管理员合并作为日常流程。
5. 发布只能由受控的 v* 标签或明确的 workflow_dispatch 触发；Release workflow 不得向 main 自动提交或推送源码变更。

### 2.2 分支命名和提交

- 功能、修复、文档和治理使用短生命周期分支，例如 feat/、fix/、docs/、governance/。
- 一个 PR 保持一个主题；跨 Mac、Windows、依赖和发布系统的改动应拆分，除非它们必须原子变更。
- 提交信息说明行为变化和原因，不在提交中包含真实凭证、运行时文件或二进制安装包。
- 不使用 git add -A 盲目收集工作区；提交前检查 git status --short 和 git diff --check。

## 3. Issue、PR 和隐私

- Bug 和功能请求使用 .github/ISSUE_TEMPLATE/ 模板；复现信息应使用假账号、假 Token 和脱敏日志。
- 公开 Issue、PR、截图和 CI 日志不得出现真实邮箱、账号 ID、套餐、额度、Token、Cookie、Keychain 内容、OAuth 文件或完整本机路径。
- 安全漏洞、凭证泄露和隐私问题遵守 [SECURITY.md](../SECURITY.md) 的私密报告流程，不在公开 Issue 里披露。
- 维护者可以关闭重复、缺少安全信息、超出范围或包含敏感数据的内容；关闭前尽可能说明原因并指导脱敏。
- 行为冲突按照 [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) 处理，技术分歧以可复现证据、测试和源码为准。

## 4. 依赖、资源和许可证

- 新增、删除或升级依赖必须同时检查 Package.swift、Package.resolved、NOTICE、构建结果和许可证兼容性。
- Package.resolved 必须纳入版本控制；NOTICE 至少登记每个 resolved identity 的版本、许可证和上游地址。
- 第三方源代码、字体、图标、截图、模型资产和生成资源必须有来源与许可证记录；没有证据的资源不进入仓库或安装包。
- 仓库自有内容使用 Apache-2.0；第三方内容保留原许可证，不能因为被引用、打包或文档提及就改标为 Apache-2.0。
- 发布资产应同时提供 LICENSE 和 NOTICE，或在同一 Release 中提供明确可访问的对应文件；二进制不等于许可证声明已经随附。

## 5. CI、构建和发布

提交或 PR 至少运行：

    ./scripts/check-open-source-docs.sh

该检查覆盖必需文档、Apache-2.0 正文、NOTICE/锁文件对应关系、公开文档本地链接、当前版本、邮箱样式文件名和高置信度凭证模式。它是预检，不替代人工安全评审、依赖上游公告审查、真实设备验收或签名/公证验证。

发布前维护者还必须确认：

1. CHANGELOG.md 有对应版本段，Release Notes 与实际变更一致。
2. Release 资产有 SHA256，安装方式、最低 macOS 版本、架构、签名和公证状态写实。
3. 发布工作流只读取仓库并上传 Release 资产；CHANGELOG、版本文档和源码变更先通过普通 PR 合并。
4. 默认 Mac 构建不启用 Sparkle 或后台自动更新；任何更新通道、遥测或崩溃上报都必须单独评审、单独记录隐私影响和回滚条件。
5. 发布失败时保留当前已发布版本，不删除用户本地配置，不用 sudo 或隐藏的远程执行恢复。

## 6. 维护者例行检查

### 每个 PR

- [ ] 变更范围、隐私边界、网络出口和本地文件读写已说明。
- [ ] 相关测试、治理脚本和 git diff --check 已运行。
- [ ] 依赖、NOTICE、资源来源、用户文档和 CHANGELOG 已同步（如适用）。
- [ ] 未混入真实账号、凭证、日志、截图或二进制构建产物。

### 每次发布

- [ ] Info.plist、README、用户/开发者/发布文档版本一致。
- [ ] LICENSE、NOTICE 已随 Release 可访问。
- [ ] 签名、公证、Gatekeeper、安装、升级和回滚状态分别有证据。
- [ ] Release workflow 没有修改或推送 main 的步骤。

### 定期

- [ ] 检查依赖上游许可证、安全公告和锁定版本。
- [ ] 复核 GitHub Ruleset、Actions 权限、Secrets/Variables 最小权限和维护者名单。
- [ ] 复核 SECURITY、CONTRIBUTING、CODE_OF_CONDUCT、Issue/PR 模板与实际处理流程一致。

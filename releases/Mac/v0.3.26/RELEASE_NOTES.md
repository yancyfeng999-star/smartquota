# SmartQuota v0.3.26 Release Notes

## 新增功能

### 全会员多账号支持
- 每个 AI 会员支持任意数量账号
- 同一时间只读取本机当前可用账号
- 其他账号保留最后一次成功额度并显示"未登录"

### 账号发现状态机
- 自动识别当前登录账号
- 支持邮箱标准化（去除首尾空格并转小写）
- 历史账号恢复
- 新账号确认流程（前台确认 / 后台待确认）

### 账号级持久化
- 账号配置和额度快照本地缓存
- 支持账号级套餐名称和续费日期
- 原子写入和 0600 文件权限

### 多账号 UI
- 账号选择器
- 待确认横幅
- 账号管理卡片
- 支持 VoiceOver 和键盘导航

### 全部 Mac Provider 接入
- 18 个内置 AI 会员均支持多账号
- 包括 Codex、Kimi、MiniMax、Grok、Claude、Gemini、Copilot 等

### Windows 行为对齐
- Rust 账号状态机
- React 账号 UI
- Windows Credential Manager 按账号隔离密钥

### 隐私与安全
- 邮箱、额度、Keychain 和普通设置的存储边界明确
- 历史快照不参与告警
- 不上传任何账号信息

## 安装

### macOS
1. 下载 `SmartQuota-0.3.26.dmg` 或 `SmartQuota-0.3.26.pkg`
2. 打开 DMG → 拖到 Applications；或双击 PKG 按向导安装
3. 首次打开若提示「无法验证开发者」：Control + 点击 → 打开

### 已安装用户
- 设置 → 检查更新 → 优先下载 `.pkg` 并静默安装后自动重启

## 系统要求
- macOS 15.0+
- Xcode (for development)
- Tuist (for development)

## 下载

- [SmartQuota-0.3.26.dmg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.26/SmartQuota-0.3.26.dmg)
- [SmartQuota-0.3.26.pkg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.26/SmartQuota-0.3.26.pkg)

## 完整更新日志

- 全会员多账号支持
- 账号发现状态机
- 账号级持久化
- 多账号 UI
- 全部 Mac Provider 接入
- Windows 行为对齐
- 隐私与安全文档更新

# SmartQuota v0.3.27 Release Notes

## 新增功能

### 指纹解锁保护
- 支持使用 Touch ID 保护敏感 API 密钥
- 生物识别模板存储在 Secure Enclave 中，永不离开设备
- 敏感密钥使用 Keychain 访问控制保护

### 密钥管理界面
- 设置中新增"安全"卡片
- 可管理密钥和生物识别设置
- 支持启用/禁用指纹保护

### 安全存储增强
- 敏感密钥使用 `kSecAttrAccessControl` 保护
- 需要用户交互才能访问
- 支持密码回退（生物识别不可用时）

### 权限说明
- 新增 `com.apple.security.personal-information.biometric` 权限
- 用于访问设备生物识别传感器

## 安全说明

- 生物识别模板存储在 Secure Enclave 中，永不离开设备
- 敏感密钥使用 Keychain 访问控制保护
- 每次访问都需要用户交互验证
- 设备丢失后，密钥无法被他人访问

## 安装

### macOS
1. 下载 `SmartQuota-0.3.27.dmg` 或 `SmartQuota-0.3.27.pkg`
2. 打开 DMG → 拖到 Applications；或双击 PKG 按向导安装
3. 首次打开若提示「无法验证开发者」：Control + 点击 → 打开

### 已安装用户
- 设置 → 检查更新 → 优先下载 `.pkg` 并静默安装后自动重启

## 系统要求
- macOS 15.0+
- Touch ID 支持的设备（MacBook Pro、MacBook Air、Magic Keyboard）

## 下载

- [SmartQuota-0.3.27.dmg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.27/SmartQuota-0.3.27.dmg)
- [SmartQuota-0.3.27.pkg](https://github.com/yancyfeng999-star/smartquota/releases/download/v0.3.27/SmartQuota-0.3.27.pkg)

## 完整更新日志

- 指纹解锁保护
- 密钥管理界面
- 安全存储增强
- 权限说明

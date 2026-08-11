# 智额密钥管理与指纹解锁实施计划

> **日期：** 2026-08-11
> **工作模式：** Standard
> **预计完成时间：** 15天
> **总体风险：** 中等（涉及权限和安全）

---

## 1. 首轮边界读数

```text
工作模式：Standard（涉及权限、安全存储、UI变化）
已确认事实：
  - 文件：KeychainSecretStore.swift, CredentialRepository.swift, entitlements.plist
  - 入口：Apps/Mac/Sources/Infrastructure/Storage/
  - 当前状态：使用 Keychain 存储密钥，无生物识别保护
  - 版本来源：Info.plist (0.3.26, build 29)

合理假设：
  - 用户设备支持 Touch ID 或 Face ID
  - 用户愿意使用生物识别保护敏感数据
  - macOS 15.0+ 支持 LocalAuthentication 框架

本次范围：添加密钥管理和指纹解锁功能
明确不做：远程密钥同步、云备份、多设备同步
验收标准：密钥可安全存储、指纹解锁可用、向后兼容
未确认事项：所有设备生物识别可用性、用户接受度
```

---

## 2. 需求合同

### 2.1 目标

**用户问题：** 当前密钥存储在 Keychain 中，虽然安全但需要用户手动管理，且无法防止设备被解锁后的未授权访问。

**目标用户：** 使用智额管理多个 AI 会员额度的开发者，特别是处理敏感 API 密钥的用户。

**核心假设：**
1. 用户希望在访问敏感密钥时进行二次验证
2. 指纹解锁比密码更便捷且安全
3. 用户愿意为此功能授予权限

### 2.2 核心动作

```
触发 → 用户访问密钥管理页面 → 系统提示指纹验证 → 验证成功 → 显示/编辑密钥
    → 验证失败 → 显示错误提示 → 允许重试或取消
```

### 2.3 输入输出

| 输入 | 处理 | 输出 |
|------|------|------|
| 用户指纹/面容 | LocalAuthentication 验证 | 验证结果 |
| API 密钥 | Keychain 安全存储 | 加密存储 |
| 密钥标识 | 索引管理 | 快速检索 |

### 2.4 明确不做

- ❌ 远程密钥同步
- ❌ 云备份密钥
- ❌ 多设备同步
- ❌ 密码管理器集成
- ❌ 自动填充功能

---

## 3. 架构设计

### 3.1 分层架构

```
┌─────────────────────────────────────────────┐
│  APP LAYER                                  │
│  - BiometricAuthView (指纹解锁UI)           │
│  - KeyManagementView (密钥管理UI)           │
│  - SettingsView (设置入口)                  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  DOMAIN LAYER                               │
│  - BiometricAuthManager (认证管理)          │
│  - SecureKeyRepository (安全密钥仓库)       │
│  - KeyMigrationService (迁移服务)           │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  INFRASTRUCTURE LAYER                       │
│  - LocalAuthenticationService (生物识别)    │
│  - SecureKeychainStore (安全Keychain)       │
│  - KeychainMigrationTool (迁移工具)         │
└─────────────────────────────────────────────┘
```

### 3.2 核心组件

#### 3.2.1 BiometricAuthManager

```swift
@MainActor
@Observable
public final class BiometricAuthManager {
    public enum AuthState {
        case notAvailable
        case available
        case authenticated
        case failed(Error)
    }
    
    public var authState: AuthState = .notAvailable
    public var isBiometricAvailable: Bool { ... }
    public var biometricType: BiometricType { ... }
    
    public func authenticate() async throws -> Bool
    public func requireAuthForSensitiveOperations() -> Bool
}

public enum BiometricType {
    case touchID
    case faceID
    case none
}
```

#### 3.2.2 SecureKeyRepository

```swift
public protocol SecureKeyRepository: CredentialRepository {
    /// 保存密钥，需要生物识别验证
    func saveSecure(_ value: String, forKey key: String, requireBiometric: Bool) async throws
    
    /// 获取密钥，需要生物识别验证
    func getSecure(forKey key: String, requireBiometric: Bool) async throws -> String?
    
    /// 检查密钥是否需要生物识别
    func requiresBiometric(forKey key: String) -> Bool
    
    /// 设置密钥的生物识别要求
    func setBiometricRequirement(_ required: Bool, forKey key: String)
}
```

#### 3.2.3 SecureKeychainStore

```swift
public final class SecureKeychainStore: SecureKeyRepository {
    private let keychain: KeychainSecretStore.Type
    private let authManager: BiometricAuthManager
    
    // 使用 kSecAttrAccessControl 添加生物识别要求
    private func createAccessControl(
        requireBiometric: Bool
    ) -> SecAccessControl? {
        var accessFlags: SecAccessControlCreateFlags = [.userPresence]
        if requireBiometric {
            accessFlags = [.biometryCurrentSet]
        }
        return SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            accessFlags,
            nil
        )
    }
}
```

### 3.3 数据流

```
用户操作 → UI请求密钥 → 检查是否需要生物识别
    ↓
需要生物识别 → 调用LocalAuthentication → 系统弹出指纹验证
    ↓
验证成功 → 从Keychain读取密钥 → 返回给UI
    ↓
验证失败 → 显示错误 → 允许重试或取消
```

---

## 4. 实施任务

### 4.1 Phase 1: 生物识别基础设施 (3天)

#### Task 1.1: 添加 LocalAuthentication 依赖

**文件：**
- Modify: `Apps/Mac/Project.swift` (添加 LocalAuthentication 框架)
- Create: `Apps/Mac/Sources/Infrastructure/Security/LocalAuthenticationService.swift`

**实现：**
```swift
import LocalAuthentication

public final class LocalAuthenticationService: @unchecked Sendable {
    public static let shared = LocalAuthenticationService()
    
    public func canEvaluateBiometric() -> (available: Bool, type: BiometricType, error: Error?) {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        let type: BiometricType
        switch context.biometryType {
        case .touchID: type = .touchID
        case .faceID: type = .faceID
        default: type = .none
        }
        
        return (canEvaluate, type, error)
    }
    
    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用密码"
        
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }
}
```

**测试：**
- Create: `Apps/Mac/Tests/InfrastructureTests/Security/LocalAuthenticationServiceTests.swift`

#### Task 1.2: 实现 BiometricAuthManager

**文件：**
- Create: `Apps/Mac/Sources/Domain/Security/BiometricAuthManager.swift`
- Create: `Apps/Mac/Sources/Domain/Security/BiometricType.swift`

**实现：**
```swift
@MainActor
@Observable
public final class BiometricAuthManager {
    public enum AuthState: Equatable {
        case notAvailable
        case available
        case authenticated
        case failed(String)
    }
    
    public var authState: AuthState = .notAvailable
    public var isBiometricAvailable: Bool = false
    public var biometricType: BiometricType = .none
    
    private let authService: LocalAuthenticationService
    
    public init(authService: LocalAuthenticationService = .shared) {
        self.authService = authService
        checkAvailability()
    }
    
    public func checkAvailability() {
        let result = authService.canEvaluateBiometric()
        isBiometricAvailable = result.available
        biometricType = result.type
        authState = result.available ? .available : .notAvailable
    }
    
    public func authenticate(reason: String) async throws -> Bool {
        do {
            let success = try await authService.authenticate(reason: reason)
            authState = success ? .authenticated : .failed("验证失败")
            return success
        } catch {
            authState = .failed(error.localizedDescription)
            throw error
        }
    }
}
```

**测试：**
- Create: `Apps/Mac/Tests/DomainTests/Security/BiometricAuthManagerTests.swift`

#### Task 1.3: 更新 entitlements

**文件：**
- Modify: `Apps/Mac/Sources/App/entitlements.plist`

**添加权限：**
```xml
<key>com.apple.security.personal-information.biometric</key>
<true/>
```

---

### 4.2 Phase 2: 安全密钥存储 (4天)

#### Task 2.1: 实现 SecureKeychainStore

**文件：**
- Create: `Apps/Mac/Sources/Infrastructure/Security/SecureKeychainStore.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/KeychainSecretStore.swift`

**实现：**
```swift
public final class SecureKeychainStore: SecureKeyRepository {
    private let keychain: KeychainSecretStore.Type
    private let authManager: BiometricAuthManager
    
    public init(
        keychain: KeychainSecretStore.Type = KeychainSecretStore.self,
        authManager: BiometricAuthManager
    ) {
        self.keychain = keychain
        self.authManager = authManager
    }
    
    public func saveSecure(
        _ value: String,
        forKey key: String,
        requireBiometric: Bool
    ) async throws {
        if requireBiometric {
            guard try await authManager.authenticate(reason: "验证身份以保存密钥") else {
                throw SecurityError.authenticationFailed
            }
        }
        
        if requireBiometric {
            try saveWithAccessControl(value, forKey: key)
        } else {
            keychain.set(value, account: key)
        }
    }
    
    public func getSecure(
        forKey key: String,
        requireBiometric: Bool
    ) async throws -> String? {
        if requireBiometric {
            guard try await authManager.authenticate(reason: "验证身份以访问密钥") else {
                throw SecurityError.authenticationFailed
            }
        }
        
        return keychain.get(account: key)
    }
    
    private func saveWithAccessControl(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecurityError.encodingFailed
        }
        
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.biometryCurrentSet, .userPresence],
            nil
        ) else {
            throw SecurityError.accessControlCreationFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.smartquota.app",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status)
        }
    }
}

public enum SecurityError: LocalizedError {
    case authenticationFailed
    case encodingFailed
    case accessControlCreationFailed
    case keychainError(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "身份验证失败"
        case .encodingFailed:
            return "数据编码失败"
        case .accessControlCreationFailed:
            return "无法创建访问控制"
        case .keychainError(let status):
            return "Keychain 错误: \(status)"
        }
    }
}
```

**测试：**
- Create: `Apps/Mac/Tests/InfrastructureTests/Security/SecureKeychainStoreTests.swift`

#### Task 2.2: 实现 KeyMigrationService

**文件：**
- Create: `Apps/Mac/Sources/Domain/Security/KeyMigrationService.swift`

**实现：**
```swift
public final class KeyMigrationService {
    private let oldStore: CredentialRepository
    private let newStore: SecureKeyRepository
    private let authManager: BiometricAuthManager
    
    public init(
        oldStore: CredentialRepository,
        newStore: SecureKeyRepository,
        authManager: BiometricAuthManager
    ) {
        self.oldStore = oldStore
        self.newStore = newStore
        self.authManager = authManager
    }
    
    public func migrateExistingKeys(
        enableBiometric: Bool
    ) async throws -> MigrationResult {
        var migrated: [String] = []
        var failed: [String] = []
        
        let existingKeys = getExistingKeys()
        
        for key in existingKeys {
            do {
                if let value = oldStore.get(forKey: key) {
                    try await newStore.saveSecure(
                        value,
                        forKey: key,
                        requireBiometric: enableBiometric
                    )
                    migrated.append(key)
                }
            } catch {
                failed.append(key)
            }
        }
        
        return MigrationResult(
            migrated: migrated,
            failed: failed,
            biometricEnabled: enableBiometric
        )
    }
    
    private func getExistingKeys() -> [String] {
        return [
            CredentialKey.githubToken,
            CredentialKey.githubUsername,
        ]
    }
}

public struct MigrationResult {
    public let migrated: [String]
    public let failed: [String]
    public let biometricEnabled: Bool
    
    public var successCount: Int { migrated.count }
    public var failureCount: Int { failed.count }
    public var isComplete: Bool { failed.isEmpty }
}
```

**测试：**
- Create: `Apps/Mac/Tests/DomainTests/Security/KeyMigrationServiceTests.swift`

#### Task 2.3: 更新 CredentialRepository 协议

**文件：**
- Modify: `Apps/Mac/Sources/Domain/Provider/CredentialRepository.swift`

**添加：**
```swift
public protocol SecureCredentialRepository: CredentialRepository {
    func saveSecure(_ value: String, forKey key: String, requireBiometric: Bool) async throws
    func getSecure(forKey key: String, requireBiometric: Bool) async throws -> String?
    func requiresBiometric(forKey key: String) -> Bool
}
```

---

### 4.3 Phase 3: UI 实现 (3天)

#### Task 3.1: 创建 BiometricAuthView

**文件：**
- Create: `Apps/Mac/Sources/App/Views/Security/BiometricAuthView.swift`

**实现：**
```swift
import SwiftUI

struct BiometricAuthView: View {
    @State private var authManager: BiometricAuthManager
    @Binding var isUnlocked: Bool
    
    init(authManager: BiometricAuthManager, isUnlocked: Binding<Bool>) {
        _authManager = State(initialValue: authManager)
        _isUnlocked = isUnlocked
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: biometricIcon)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("需要验证身份")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("使用\(biometricTypeName)解锁密钥管理")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("验证") {
                Task {
                    do {
                        let success = try await authManager.authenticate(
                            reason: "验证身份以访问密钥管理"
                        )
                        if success {
                            isUnlocked = true
                        }
                    } catch {
                        // 错误处理
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            if case .failed(let message) = authManager.authState {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(40)
        .frame(width: 300, height: 250)
    }
    
    private var biometricIcon: String {
        switch authManager.biometricType {
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .none: return "lock.fill"
        }
    }
    
    private var biometricTypeName: String {
        switch authManager.biometricType {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .none: return "密码"
        }
    }
}
```

#### Task 3.2: 创建 KeyManagementView

**文件：**
- Create: `Apps/Mac/Sources/App/Views/Security/KeyManagementView.swift`

**实现：**
```swift
import SwiftUI

struct KeyManagementView: View {
    @State private var authManager: BiometricAuthManager
    @State private var secureStore: SecureKeyRepository
    @State private var isUnlocked = false
    @State private var keys: [KeyItem] = []
    
    var body: some View {
        Group {
            if isUnlocked {
                keyListView
            } else {
                BiometricAuthView(
                    authManager: authManager,
                    isUnlocked: $isUnlocked
                )
            }
        }
        .onAppear {
            authManager.checkAvailability()
        }
    }
    
    private var keyListView: some View {
        List {
            Section("API 密钥") {
                ForEach(keys) { key in
                    KeyRowView(key: key)
                }
            }
            
            Section("安全设置") {
                Toggle("启用指纹保护", isOn: $enableBiometric)
                
                if enableBiometric {
                    Text("所有敏感密钥将需要指纹验证才能访问")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("密钥管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("锁定") {
                    isUnlocked = false
                }
            }
        }
    }
}

struct KeyItem: Identifiable {
    let id: String
    let name: String
    let requiresBiometric: Bool
    let lastUsed: Date?
}

struct KeyRowView: View {
    let key: KeyItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(key.name)
                    .font(.headline)
                
                if let lastUsed = key.lastUsed {
                    Text("最后使用: \(lastUsed, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if key.requiresBiometric {
                Image(systemName: "lock.fill")
                    .foregroundColor(.green)
            }
        }
    }
}
```

#### Task 3.3: 更新 SettingsView

**文件：**
- Modify: `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift`

**添加入口：**
```swift
Section("安全") {
    NavigationLink {
        KeyManagementView()
    } label: {
        Label("密钥管理", systemImage: "key.fill")
    }
    
    Toggle("启用指纹保护", isOn: $enableBiometric)
}
```

---

### 4.4 Phase 4: 集成与测试 (3天)

#### Task 4.1: 集成到现有系统

**文件：**
- Modify: `Apps/Mac/Sources/App/SmartQuotaApp.swift`
- Modify: `Apps/Mac/Sources/Infrastructure/Storage/JSONSettingsRepository.swift`

**实现：**
```swift
@main
struct SmartQuotaApp: App {
    @State private var authManager = BiometricAuthManager()
    @State private var secureStore: SecureKeychainStore
    
    init() {
        let auth = BiometricAuthManager()
        _authManager = State(initialValue: auth)
        _secureStore = State(initialValue: SecureKeychainStore(authManager: auth))
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
                .environmentObject(authManager)
                .environment(\.secureKeyRepository, secureStore)
        } label: {
            StatusBarIcon(monitor: monitor)
        }
    }
}
```

#### Task 4.2: 编写验收测试

**文件：**
- Create: `Apps/Mac/Tests/AcceptanceTests/BiometricSecuritySpec.swift`

**测试场景：**
1. 生物识别可用性检测
2. 指纹验证成功流程
3. 指纹验证失败处理
4. 密钥保存需要验证
5. 密钥读取需要验证
6. 迁移现有密钥
7. 向后兼容性

#### Task 4.3: 运行完整测试

```bash
cd Apps/Mac
tuist generate
xcodebuild -workspace SmartQuota.xcworkspace \
  -scheme SmartQuota \
  -destination 'platform=macOS' \
  test
```

**预期：** 所有测试通过，包括新增的安全测试

---

### 4.5 Phase 5: 文档与发布 (2天)

#### Task 5.1: 更新文档

**文件：**
- Modify: `SECURITY.md` - 添加生物识别安全部分
- Modify: `docs/USER_GUIDE.md` - 添加指纹解锁使用说明
- Modify: `docs/DEVELOPER.md` - 添加安全架构说明
- Modify: `PRODUCT.md` - 更新功能列表

#### Task 5.2: 更新版本号

**文件：**
- Modify: `Apps/Mac/Sources/App/Info.plist` - 版本号 0.3.27
- Modify: `CHANGELOG.md` - 添加生物识别功能说明

#### Task 5.3: 构建与发布

```bash
cd Apps/Mac
./scripts/package-release.sh
```

**产物：**
- SmartQuota-0.3.27.dmg
- SmartQuota-0.3.27.pkg

---

## 5. 安全评估

### 5.1 威胁模型

| 资产 | 威胁 | 控制 |
|------|------|------|
| API 密钥 | 设备解锁后未授权访问 | 生物识别验证 |
| 密钥存储 | 物理设备被盗 | Keychain 加密 + 生物识别 |
| 认证状态 | 绕过验证 | LocalAuthentication 框架 |
| 迁移过程 | 数据丢失 | 原子操作 + 回滚机制 |

### 5.2 权限矩阵

| 权限 | 用途 | 最小范围 | 拒绝后降级 |
|------|------|----------|------------|
| 生物识别 | 访问敏感密钥 | 仅密钥操作 | 使用密码回退 |
| Keychain | 安全存储 | 仅应用密钥 | 使用普通存储 |

### 5.3 隐私评估

| 数据类别 | 敏感级别 | 存储位置 | 保留期限 |
|----------|----------|----------|----------|
| 生物识别模板 | 高 | Secure Enclave | 永不离开设备 |
| API 密钥 | 高 | Keychain (加密) | 用户删除时 |
| 认证状态 | 中 | 内存 | 应用关闭时 |

### 5.4 放行条件

```text
local_review       ✅ 已完成安全架构审查
local_tests        ⚠️ 需要真实设备测试
local_build        ⚠️ 需要构建验证
runtime_verified   ⚠️ 需要真实设备验证
remote_release     ⚠️ 需要发布后验证
update_verified    ⚠️ 需要更新验证
user_installed     ⚠️ 需要用户安装验证
```

---

## 6. 风险与缓解

### 6.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 设备不支持生物识别 | 功能不可用 | 提供密码回退 |
| Keychain 访问控制失败 | 密钥无法存储 | 降级到普通存储 |
| 迁移过程中断 | 数据丢失 | 原子操作 + 备份 |
| 用户拒绝权限 | 功能受限 | 清晰说明用途 |

### 6.2 兼容性风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| macOS 版本不兼容 | 功能不可用 | 检查系统版本 |
| 旧版本数据迁移 | 配置丢失 | 渐进式迁移 |
| 第三方依赖冲突 | 构建失败 | 版本锁定 |

---

## 7. 估算与时间表

### 7.1 总体估算

| 阶段 | 时间 | 依赖 |
|------|------|------|
| Phase 1: 基础设施 | 3天 | 无 |
| Phase 2: 安全存储 | 4天 | Phase 1 |
| Phase 3: UI 实现 | 3天 | Phase 2 |
| Phase 4: 集成测试 | 3天 | Phase 3 |
| Phase 5: 文档发布 | 2天 | Phase 4 |
| **总计** | **15天** | |

### 7.2 里程碑

| 里程碑 | 日期 | 交付物 |
|--------|------|--------|
| M1: 生物识别可用 | Day 3 | LocalAuthenticationService, BiometricAuthManager |
| M2: 安全存储完成 | Day 7 | SecureKeychainStore, KeyMigrationService |
| M3: UI 完成 | Day 10 | BiometricAuthView, KeyManagementView |
| M4: 集成测试通过 | Day 13 | 验收测试通过 |
| M5: 发布完成 | Day 15 | v0.3.27 发布 |

---

## 8. 验收标准

### 8.1 功能验收

- [ ] 生物识别可用性检测正确
- [ ] 指纹验证成功后可访问密钥
- [ ] 指纹验证失败后显示错误提示
- [ ] 密钥保存时可选择是否需要生物识别
- [ ] 现有密钥可迁移到安全存储
- [ ] 向后兼容，旧版本数据不丢失

### 8.2 安全验收

- [ ] 生物识别模板不离开设备
- [ ] 密钥存储在 Keychain 中
- [ ] 访问控制正确配置
- [ ] 错误处理安全

### 8.3 性能验收

- [ ] 生物识别验证 < 2秒
- [ ] 密钥读取 < 1秒
- [ ] 应用启动时间无显著增加
- [ ] 内存占用无显著增加

---

## 9. 下一步行动

1. **确认需求** - 与用户确认功能范围和优先级
2. **环境准备** - 确保开发设备支持生物识别
3. **开始实施** - 按照 Phase 1-5 顺序执行
4. **持续验证** - 每个阶段完成后进行验证
5. **发布准备** - 完成文档和发布流程

---

## 附录：相关文件清单

### 需要修改的文件

| 文件 | 修改内容 |
|------|----------|
| `Apps/Mac/Project.swift` | 添加 LocalAuthentication 框架 |
| `Apps/Mac/Sources/App/entitlements.plist` | 添加生物识别权限 |
| `Apps/Mac/Sources/Domain/Provider/CredentialRepository.swift` | 扩展安全协议 |
| `Apps/Mac/Sources/Infrastructure/Storage/KeychainSecretStore.swift` | 集成安全存储 |
| `Apps/Mac/Sources/App/SmartQuotaApp.swift` | 初始化安全组件 |
| `Apps/Mac/Sources/App/Views/Settings/SettingsView.swift` | 添加安全设置入口 |
| `SECURITY.md` | 更新安全文档 |
| `docs/USER_GUIDE.md` | 添加使用说明 |
| `docs/DEVELOPER.md` | 添加架构说明 |
| `PRODUCT.md` | 更新功能列表 |
| `CHANGELOG.md` | 添加版本说明 |
| `Apps/Mac/Sources/App/Info.plist` | 更新版本号 |

### 需要创建的文件

| 文件 | 用途 |
|------|------|
| `Apps/Mac/Sources/Infrastructure/Security/LocalAuthenticationService.swift` | 生物识别服务 |
| `Apps/Mac/Sources/Infrastructure/Security/SecureKeychainStore.swift` | 安全密钥存储 |
| `Apps/Mac/Sources/Domain/Security/BiometricAuthManager.swift` | 认证管理器 |
| `Apps/Mac/Sources/Domain/Security/BiometricType.swift` | 生物识别类型 |
| `Apps/Mac/Sources/Domain/Security/KeyMigrationService.swift` | 密钥迁移服务 |
| `Apps/Mac/Sources/App/Views/Security/BiometricAuthView.swift` | 指纹解锁UI |
| `Apps/Mac/Sources/App/Views/Security/KeyManagementView.swift` | 密钥管理UI |
| `Apps/Mac/Tests/InfrastructureTests/Security/LocalAuthenticationServiceTests.swift` | 生物识别测试 |
| `Apps/Mac/Tests/InfrastructureTests/Security/SecureKeychainStoreTests.swift` | 安全存储测试 |
| `Apps/Mac/Tests/DomainTests/Security/BiometricAuthManagerTests.swift` | 认证管理测试 |
| `Apps/Mac/Tests/DomainTests/Security/KeyMigrationServiceTests.swift` | 迁移服务测试 |
| `Apps/Mac/Tests/AcceptanceTests/BiometricSecuritySpec.swift` | 验收测试 |

---

**计划制定时间：** 2026-08-11
**工作模式：** Standard
**预计完成时间：** 15天
**总体风险：** 中等（涉及权限和安全）

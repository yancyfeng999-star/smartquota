import SwiftUI
import Domain
import Infrastructure

/// 密钥项
struct KeyItem: Identifiable {
    let id: String
    let name: String
    let requiresBiometric: Bool
    let lastUsed: Date?
}

/// 密钥行视图
struct KeyRowView: View {
    let key: KeyItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
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
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 密钥管理视图
struct KeyManagementView: View {
    @State private var authManager: BiometricAuthManager
    @State private var secureStore: SecureKeychainStore
    @State private var isUnlocked = false
    @State private var enableBiometric = true
    @State private var keys: [KeyItem] = []
    
    init(authManager: BiometricAuthManager, secureStore: SecureKeychainStore) {
        _authManager = State(initialValue: authManager)
        _secureStore = State(initialValue: secureStore)
    }
    
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
            loadKeys()
        }
    }
    
    private var keyListView: some View {
        List {
            Section("API 密钥") {
                if keys.isEmpty {
                    Text("暂无存储的密钥")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(keys) { key in
                        KeyRowView(key: key)
                    }
                }
            }
            
            Section("安全设置") {
                Toggle(isOn: $enableBiometric) {
                    Label("启用指纹保护", systemImage: "lock.shield")
                }
                .onChange(of: enableBiometric) { _, newValue in
                    updateBiometricSetting(newValue)
                }
                
                if enableBiometric {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("所有敏感密钥将需要指纹验证才能访问")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("操作") {
                Button {
                    loadKeys()
                } label: {
                    Label("刷新密钥列表", systemImage: "arrow.clockwise")
                }
                
                Button(role: .destructive) {
                    lockView()
                } label: {
                    Label("锁定", systemImage: "lock.fill")
                }
            }
        }
        .navigationTitle("密钥管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("锁定") {
                    lockView()
                }
            }
        }
    }
    
    private func loadKeys() {
        // 加载密钥列表
        keys = [
            KeyItem(
                id: CredentialKey.githubToken,
                name: "GitHub Token",
                requiresBiometric: secureStore.requiresBiometric(forKey: CredentialKey.githubToken),
                lastUsed: nil
            ),
            KeyItem(
                id: CredentialKey.githubUsername,
                name: "GitHub 用户名",
                requiresBiometric: secureStore.requiresBiometric(forKey: CredentialKey.githubUsername),
                lastUsed: nil
            ),
        ]
    }
    
    private func updateBiometricSetting(_ enabled: Bool) {
        for key in keys {
            secureStore.setBiometricRequirement(enabled, forKey: key.id)
        }
        loadKeys()
    }
    
    private func lockView() {
        isUnlocked = false
        authManager.resetAuthState()
    }
}

#Preview {
    NavigationStack {
        KeyManagementView(
            authManager: BiometricAuthManager(authService: LocalAuthenticationService.shared),
            secureStore: SecureKeychainStore(authManager: BiometricAuthManager(authService: LocalAuthenticationService.shared))
        )
    }
}

import SwiftUI
import Domain
import Infrastructure

/// 指纹解锁视图
struct BiometricAuthView: View {
    @State private var authManager: BiometricAuthManager
    @Binding var isUnlocked: Bool
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    
    init(authManager: BiometricAuthManager, isUnlocked: Binding<Bool>) {
        _authManager = State(initialValue: authManager)
        _isUnlocked = isUnlocked
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // 图标
            Image(systemName: authManager.biometricIconName)
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse, isActive: isAuthenticating)
            
            // 标题
            Text("需要验证身份")
                .font(.title2)
                .fontWeight(.semibold)
            
            // 说明
            Text("使用\(authManager.biometricTypeName)解锁密钥管理")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // 验证按钮
            Button {
                authenticate()
            } label: {
                HStack {
                    if isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isAuthenticating ? "验证中..." : "验证")
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)
            
            // 错误信息
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            // 密码回退按钮
            if authManager.biometricType != .none {
                Button("使用密码") {
                    authenticateWithPassword()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(40)
        .frame(width: 320, height: 300)
        .onAppear {
            authManager.checkAvailability()
        }
    }
    
    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await authManager.authenticate(reason: "验证身份以访问密钥管理")
                if success {
                    isUnlocked = true
                } else {
                    errorMessage = "验证失败，请重试"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
    
    private func authenticateWithPassword() {
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await authManager.authenticateWithPassword(reason: "验证身份以访问密钥管理")
                if success {
                    isUnlocked = true
                } else {
                    errorMessage = "验证失败，请重试"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}

#Preview {
    BiometricAuthView(
        authManager: BiometricAuthManager(authService: LocalAuthenticationService.shared),
        isUnlocked: .constant(false)
    )
}

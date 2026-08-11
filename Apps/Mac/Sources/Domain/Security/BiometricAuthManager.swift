import Foundation
import Mockable

/// 认证状态
public enum AuthState: Equatable, Sendable {
    case notAvailable
    case available
    case authenticated
    case failed(String)
}

/// 生物识别认证管理器
@MainActor
@Observable
public final class BiometricAuthManager {
    /// 当前认证状态
    public var authState: AuthState = .notAvailable
    
    /// 生物识别是否可用
    public var isBiometricAvailable: Bool = false
    
    /// 生物识别类型
    public var biometricType: BiometricType = .none
    
    /// 是否需要生物识别保护敏感操作
    public var requireBiometricForSensitiveOps: Bool = true
    
    private let authService: LocalAuthenticationServiceProtocol
    
    public init(authService: LocalAuthenticationServiceProtocol) {
        self.authService = authService
        checkAvailability()
    }
    
    /// 检查生物识别可用性
    public func checkAvailability() {
        let result = authService.canEvaluateBiometric()
        isBiometricAvailable = result.available
        biometricType = result.type
        authState = result.available ? .available : .notAvailable
    }
    
    /// 使用生物识别进行认证
    /// - Parameter reason: 认证原因
    /// - Returns: 认证是否成功
    public func authenticate(reason: String) async throws -> Bool {
        guard isBiometricAvailable else {
            authState = .failed("生物识别不可用")
            return false
        }
        
        do {
            let success = try await authService.authenticate(reason: reason)
            authState = success ? .authenticated : .failed("验证失败")
            return success
        } catch {
            authState = .failed(error.localizedDescription)
            throw error
        }
    }
    
    /// 使用密码进行认证（回退方案）
    /// - Parameter reason: 认证原因
    /// - Returns: 认证是否成功
    public func authenticateWithPassword(reason: String) async throws -> Bool {
        do {
            let success = try await authService.authenticateWithPassword(reason: reason)
            authState = success ? .authenticated : .failed("验证失败")
            return success
        } catch {
            authState = .failed(error.localizedDescription)
            throw error
        }
    }
    
    /// 重置认证状态
    public func resetAuthState() {
        authState = isBiometricAvailable ? .available : .notAvailable
    }
    
    /// 检查是否已认证
    public var isAuthenticated: Bool {
        authState == .authenticated
    }
    
    /// 获取生物识别类型的显示名称
    public var biometricTypeName: String {
        switch biometricType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .none:
            return "密码"
        }
    }
    
    /// 获取生物识别图标名称
    public var biometricIconName: String {
        switch biometricType {
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .none:
            return "lock.fill"
        }
    }
}

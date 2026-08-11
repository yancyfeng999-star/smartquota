import Foundation
import LocalAuthentication
import Domain

/// 本地认证服务实现
public final class LocalAuthenticationService: LocalAuthenticationServiceProtocol, @unchecked Sendable {
    public static let shared = LocalAuthenticationService()
    
    private init() {}
    
    /// 检查生物识别是否可用
    public func canEvaluateBiometric() -> BiometricResult {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        let type: BiometricType
        switch context.biometryType {
        case .touchID:
            type = .touchID
        case .faceID:
            type = .faceID
        default:
            type = .none
        }
        
        return BiometricResult(available: canEvaluate, type: type, error: error)
    }
    
    /// 使用生物识别进行认证
    /// - Parameter reason: 认证原因，会显示给用户
    /// - Returns: 认证是否成功
    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用密码"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            throw error
        }
    }
    
    /// 使用密码进行认证（生物识别的回退方案）
    /// - Parameter reason: 认证原因
    /// - Returns: 认证是否成功
    public func authenticateWithPassword(reason: String) async throws -> Bool {
        let context = LAContext()
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch {
            throw error
        }
    }
}

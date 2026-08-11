import Foundation

/// 生物识别类型
public enum BiometricType: Sendable {
    case touchID
    case faceID
    case none
}

/// 生物识别认证结果
public struct BiometricResult: Sendable {
    public let available: Bool
    public let type: BiometricType
    public let error: Error?
    
    public init(available: Bool, type: BiometricType, error: Error? = nil) {
        self.available = available
        self.type = type
        self.error = error
    }
}

/// 本地认证服务协议
public protocol LocalAuthenticationServiceProtocol: Sendable {
    /// 检查生物识别是否可用
    func canEvaluateBiometric() -> BiometricResult
    
    /// 使用生物识别进行认证
    func authenticate(reason: String) async throws -> Bool
    
    /// 使用密码进行认证
    func authenticateWithPassword(reason: String) async throws -> Bool
}

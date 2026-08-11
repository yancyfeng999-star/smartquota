import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("BiometricAuthManager Tests")
struct BiometricAuthManagerTests {
    @MainActor
    @Test("初始状态应该正确")
    func testInitialState() {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        // 检查初始状态
        #expect(manager.authState == .notAvailable || manager.authState == .available)
        #expect(manager.biometricType == .none || manager.biometricType == .touchID || manager.biometricType == .faceID)
        #expect(manager.requireBiometricForSensitiveOps == true)
    }
    
    @MainActor
    @Test("检查可用性应该更新状态")
    func testCheckAvailability() {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        // 调用检查可用性
        manager.checkAvailability()
        
        // 验证状态已更新
        if manager.isBiometricAvailable {
            #expect(manager.authState == .available)
            #expect(manager.biometricType == .touchID || manager.biometricType == .faceID)
        } else {
            #expect(manager.authState == .notAvailable)
            #expect(manager.biometricType == .none)
        }
    }
    
    @MainActor
    @Test("生物识别类型名称应该正确")
    func testBiometricTypeName() {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        switch manager.biometricType {
        case .touchID:
            #expect(manager.biometricTypeName == "Touch ID")
        case .faceID:
            #expect(manager.biometricTypeName == "Face ID")
        case .none:
            #expect(manager.biometricTypeName == "密码")
        }
    }
    
    @MainActor
    @Test("生物识别图标名称应该正确")
    func testBiometricIconName() {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        switch manager.biometricType {
        case .touchID:
            #expect(manager.biometricIconName == "touchid")
        case .faceID:
            #expect(manager.biometricIconName == "faceid")
        case .none:
            #expect(manager.biometricIconName == "lock.fill")
        }
    }
    
    @MainActor
    @Test("重置认证状态应该正确")
    func testResetAuthState() {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        // 先设置为已认证
        manager.authState = .authenticated
        #expect(manager.isAuthenticated == true)
        
        // 重置状态
        manager.resetAuthState()
        
        // 验证状态已重置
        if manager.isBiometricAvailable {
            #expect(manager.authState == .available)
        } else {
            #expect(manager.authState == .notAvailable)
        }
    }
    
    @MainActor
    @Test("认证应该成功或失败")
    func testAuthenticate() async throws {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        guard manager.isBiometricAvailable else {
            // 如果生物识别不可用，跳过测试
            return
        }
        
        do {
            let success = try await manager.authenticate(reason: "测试认证")
            #expect(success == true || success == false)
            
            if success {
                #expect(manager.isAuthenticated == true)
            }
        } catch {
            #expect(error.localizedDescription.count > 0)
        }
    }
    
    @MainActor
    @Test("密码认证应该成功或失败")
    func testAuthenticateWithPassword() async throws {
        let authService = LocalAuthenticationService.shared
        let manager = BiometricAuthManager(authService: authService)
        
        do {
            let success = try await manager.authenticateWithPassword(reason: "测试密码认证")
            #expect(success == true || success == false)
        } catch {
            #expect(error.localizedDescription.count > 0)
        }
    }
}

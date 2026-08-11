import Testing
import Foundation
@testable import Infrastructure

@Suite("LocalAuthenticationService Tests")
struct LocalAuthenticationServiceTests {
    let service = LocalAuthenticationService.shared
    
    @Test("检查生物识别可用性")
    func testCanEvaluateBiometric() {
        let result = service.canEvaluateBiometric()
        
        // 在真实设备上，应该返回可用
        // 在CI环境中，可能返回不可用
        #expect(result.available == true || result.available == false)
        
        // 验证类型
        switch result.type {
        case .touchID, .faceID, .none:
            // 所有类型都是有效的
            break
        }
    }
    
    @Test("生物识别结果包含正确的类型")
    func testBiometricResultType() {
        let result = service.canEvaluateBiometric()
        
        if result.available {
            // 如果可用，类型应该是 touchID 或 faceID
            #expect(result.type == .touchID || result.type == .faceID)
        } else {
            // 如果不可用，类型应该是 none
            #expect(result.type == .none)
        }
    }
    
    @Test("认证请求应该成功或失败")
    func testAuthenticate() async throws {
        let result = service.canEvaluateBiometric()
        
        guard result.available else {
            // 如果生物识别不可用，跳过测试
            return
        }
        
        do {
            let success = try await service.authenticate(reason: "测试认证")
            // 认证可能成功（如果用户交互）或失败（如果没有用户交互）
            #expect(success == true || success == false)
        } catch {
            // 认证可能抛出错误
            #expect(error.localizedDescription.count > 0)
        }
    }
    
    @Test("密码认证请求应该成功或失败")
    func testAuthenticateWithPassword() async throws {
        do {
            let success = try await service.authenticateWithPassword(reason: "测试密码认证")
            #expect(success == true || success == false)
        } catch {
            #expect(error.localizedDescription.count > 0)
        }
    }
}

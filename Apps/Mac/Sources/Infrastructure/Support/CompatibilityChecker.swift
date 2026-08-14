import Foundation
import Security
import UserNotifications
import Domain

public struct EnabledProviderDependency: Sendable, Equatable {
    public let providerId: String
    public let cliName: String?

    public init(providerId: String, cliName: String?) {
        self.providerId = providerId
        self.cliName = cliName
    }
}

public struct CompatibilityEnvironment: Sendable {
    public var osMajorVersion: Int
    public var architecture: String
    public var appDirectory: URL
    public var isDirectoryWritable: @Sendable (URL) -> Bool
    public var keychainAvailable: @Sendable () -> Bool
    public var notificationStatus: @Sendable () async -> CompatibilityNotificationStatus
    public var locateCLI: @Sendable (String) -> String?
    public var enabledProviders: (@Sendable () -> [EnabledProviderDependency])?

    public init(
        osMajorVersion: Int,
        architecture: String,
        appDirectory: URL,
        isDirectoryWritable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) },
        keychainAvailable: @escaping @Sendable () -> Bool,
        notificationStatus: @escaping @Sendable () async -> CompatibilityNotificationStatus,
        locateCLI: @escaping @Sendable (String) -> String?,
        enabledProviders: (@Sendable () -> [EnabledProviderDependency])?
    ) {
        self.osMajorVersion = osMajorVersion
        self.architecture = architecture
        self.appDirectory = appDirectory
        self.isDirectoryWritable = isDirectoryWritable
        self.keychainAvailable = keychainAvailable
        self.notificationStatus = notificationStatus
        self.locateCLI = locateCLI
        self.enabledProviders = enabledProviders
    }

    public static func live(appDirectory: URL = AppIdentity.configDirectoryURL) -> CompatibilityEnvironment {
        CompatibilityEnvironment(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            architecture: currentArchitecture(),
            appDirectory: appDirectory,
            isDirectoryWritable: { FileManager.default.isWritableFile(atPath: $0.path) },
            keychainAvailable: probeKeychain,
            notificationStatus: currentNotificationStatus,
            locateCLI: { BinaryLocator.which($0) },
            enabledProviders: nil
        )
    }

    public static func currentArchitecture() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { machine in
                String(cString: machine)
            }
        }
    }

    public static func probeKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.appBundleId,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return true
        default:
            return false
        }
    }

    public static func currentNotificationStatus() async -> CompatibilityNotificationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .provisional:
            return .provisional
        @unknown default:
            return .denied
        }
    }
}

public protocol CompatibilityChecking: Sendable {
    func check() async -> CompatibilityReport
}

public final class CompatibilityChecker: CompatibilityChecking, Sendable {
    private let store: JSONSettingsStore?
    private let environment: CompatibilityEnvironment

    public init(
        store: JSONSettingsStore? = nil,
        environment: CompatibilityEnvironment = .live()
    ) {
        self.store = store
        self.environment = environment
    }

    public func check() async -> CompatibilityReport {
        let writable = environment.isDirectoryWritable(environment.appDirectory)
        let providers = resolveEnabledProviders()
        var checks: [String: ProviderCompatibility] = [:]
        for provider in providers {
            let installed: Bool
            let action: CompatibilityAction
            if let cliName = provider.cliName {
                installed = environment.locateCLI(cliName) != nil
                action = installed ? .none : .installOrSignInCLI
            } else {
                installed = true
                action = .none
            }
            checks[provider.providerId] = ProviderCompatibility(
                providerId: provider.providerId,
                enabled: true,
                cliName: provider.cliName,
                cliInstalled: installed,
                suggestedAction: action
            )
        }

        return CompatibilityReport.make(
            minimumOSSatisfied: CompatibilityOSPolicy.isSatisfied(majorVersion: environment.osMajorVersion),
            architecture: environment.architecture,
            supportedArchitecture: CompatibilityArchitecture.isSupported(environment.architecture),
            appDirectoryWritable: writable,
            keychainAvailable: environment.keychainAvailable(),
            notificationStatus: await environment.notificationStatus(),
            providerChecks: checks
        )
    }

    private func resolveEnabledProviders() -> [EnabledProviderDependency] {
        if let override = environment.enabledProviders {
            return override()
        }
        guard let store else { return [] }
        let providers = store.readAll()["providers"] as? [String: Any] ?? [:]
        return providers.keys.sorted().compactMap { id in
            guard let entry = providers[id] as? [String: Any] else { return nil }
            guard entry["isEnabled"] as? Bool == true else { return nil }
            return EnabledProviderDependency(
                providerId: id,
                cliName: ProviderExternalDependency.cliName(for: id)
            )
        }
    }
}

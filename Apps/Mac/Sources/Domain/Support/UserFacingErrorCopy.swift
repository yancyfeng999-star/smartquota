import Foundation

/// User-visible failure kinds that always explain what happened, whether
/// old data is kept, and what to do next.
public enum SupportErrorKind: String, CaseIterable, Sendable {
    case refreshNetwork
    case refreshNotLoggedIn
    case refreshMissingCLI
    case refreshMissingKey
    case refreshServiceRejected
    case refreshFailed
    case updateCheckFailed
    case settingsSaveFailed
    case backupRestoreFailed
    case exportFailed
    case importFailed
    case migrationFailed
    case settingsCorrupt

    public var whatKey: String { "error.\(rawValue).what" }
    public var keptKey: String { "error.\(rawValue).kept" }
    public var nextKey: String { "error.\(rawValue).next" }

    public var l10nKeys: [String] { [whatKey, keptKey, nextKey] }
}

public struct UserFacingErrorCopy: Equatable, Sendable {
    public let kind: SupportErrorKind
    public let whatHappened: String
    public let dataRetention: String
    public let nextStep: String

    public init(kind: SupportErrorKind, whatHappened: String, dataRetention: String, nextStep: String) {
        self.kind = kind
        self.whatHappened = whatHappened
        self.dataRetention = dataRetention
        self.nextStep = nextStep
    }

    public var fullMessage: String {
        [whatHappened, dataRetention, nextStep]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum SupportErrorCatalog: Sendable {
    public static func copy(for kind: SupportErrorKind, language: SupportLanguage) -> UserFacingErrorCopy {
        UserFacingErrorCopy(
            kind: kind,
            whatHappened: SupportCopy.text(kind.whatKey, language),
            dataRetention: SupportCopy.text(kind.keptKey, language),
            nextStep: SupportCopy.text(kind.nextKey, language)
        )
    }

    public static var allL10nKeys: [String] {
        SupportErrorKind.allCases.flatMap(\.l10nKeys)
    }

    public static func classify(_ error: Error?, providerId: String? = nil) -> SupportErrorKind {
        if let probe = error as? ProbeError {
            switch probe {
            case .authenticationRequired, .sessionExpired:
                if let providerId,
                   DiagnosticClassification.credential(
                       providerId: providerId,
                       available: false,
                       lastError: error
                   ) == .missingKey {
                    return .refreshMissingKey
                }
                return .refreshNotLoggedIn
            case .cliNotFound:
                return .refreshMissingCLI
            case .timeout:
                return .refreshNetwork
            case .rateLimited:
                return .refreshServiceRejected
            default:
                return .refreshFailed
            }
        }
        if error is ManualUpdateError {
            return .updateCheckFailed
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .refreshNetwork
            default:
                break
            }
        }
        return .refreshFailed
    }
}

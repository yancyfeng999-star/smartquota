import Foundation

public enum RefreshScope: Sendable, Equatable {
    case provider(String)
    case allEnabledProviders
}

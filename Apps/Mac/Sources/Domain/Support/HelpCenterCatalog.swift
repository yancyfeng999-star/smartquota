import Foundation

public enum HelpTopicID: String, CaseIterable, Sendable {
    case firstSetup
    case checkUpdates
    case logLocation
    case multiAccount
    case keySecurity
    case privacy
    case faq
}

public struct HelpTopic: Equatable, Sendable, Identifiable {
    public let id: HelpTopicID
    public let titleKey: String
    public let bodyKey: String

    public init(id: HelpTopicID, titleKey: String, bodyKey: String) {
        self.id = id
        self.titleKey = titleKey
        self.bodyKey = bodyKey
    }
}

public enum HelpDestination: String, CaseIterable, Sendable, Hashable {
    case logs
    case diagnostics
    case githubReleases
    case userGuide

    public var titleKey: String {
        switch self {
        case .logs: "help.open_logs"
        case .diagnostics: "help.open_diagnostics"
        case .githubReleases: "help.open_releases"
        case .userGuide: "help.open_guide"
        }
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .logs: AccessibilityChrome.ID.helpOpenLogs
        case .diagnostics: AccessibilityChrome.ID.helpOpenDiagnostics
        case .githubReleases: AccessibilityChrome.ID.helpOpenReleases
        case .userGuide: AccessibilityChrome.ID.helpOpenUserGuide
        }
    }
}

public enum HelpCenterCatalog: Sendable {
    public static let topics: [HelpTopic] = HelpTopicID.allCases.map { id in
        HelpTopic(
            id: id,
            titleKey: "help.topic.\(id.rawValue.snakeCased).title",
            bodyKey: "help.topic.\(id.rawValue.snakeCased).body"
        )
    }

    public static let destinations: [HelpDestination] = HelpDestination.allCases

    public static var requiredStringKeys: [String] {
        var keys = [
            "help.title",
            "help.subtitle",
            "help.section.actions",
            "help.section.topics",
            "settings.help",
            "settings.help_sub",
        ]
        keys.append(contentsOf: destinations.map(\.titleKey))
        keys.append(contentsOf: topics.flatMap { [$0.titleKey, $0.bodyKey] })
        return keys
    }

    public static var githubReleasesURL: URL {
        AppIdentity.githubReleasesPageURL
    }

    /// Prefers a bundled `USER_GUIDE.md`, then walks up from `searchFrom` to `docs/USER_GUIDE.md`.
    public static func userGuideURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        searchFrom path: String = #filePath
    ) -> URL? {
        if let bundled = bundle.url(forResource: "USER_GUIDE", withExtension: "md") {
            return bundled
        }
        var dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        for _ in 0..<16 {
            let candidate = dir.appendingPathComponent("docs/USER_GUIDE.md")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}

private extension String {
    /// `firstSetup` → `first_setup`, `logLocation` → `log_location`.
    var snakeCased: String {
        var scalars: [Character] = []
        for character in self {
            if character.isUppercase {
                scalars.append("_")
                scalars.append(contentsOf: character.lowercased())
            } else {
                scalars.append(character)
            }
        }
        return String(scalars)
    }
}

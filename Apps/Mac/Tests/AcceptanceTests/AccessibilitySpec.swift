import Testing
import Foundation
@testable import Domain

/// Feature: Accessibility, help center, and unified error copy
///
/// Acceptance: VoiceOver labels/hints/values exist for icon buttons;
/// keyboard-relevant identifiers cover menu → settings → diagnostics → help
/// and refresh / export; help and error strings exist in zh-Hans and English
/// with what happened / whether old data is kept / what to do next.
@Suite("Feature: Accessibility")
struct AccessibilitySpec {

    @Test
    func `help center covers first setup updates logs accounts keys privacy and FAQ`() {
        let ids = Set(HelpCenterCatalog.topics.map(\.id))
        #expect(ids == Set(HelpTopicID.allCases))
        #expect(ids.contains(.firstSetup))
        #expect(ids.contains(.checkUpdates))
        #expect(ids.contains(.logLocation))
        #expect(ids.contains(.multiAccount))
        #expect(ids.contains(.keySecurity))
        #expect(ids.contains(.privacy))
        #expect(ids.contains(.faq))

        for topic in HelpCenterCatalog.topics {
            for language in SupportLanguage.allCases {
                let title = SupportCopy.text(topic.titleKey, language)
                let body = SupportCopy.text(topic.bodyKey, language)
                #expect(title != topic.titleKey, "missing \(topic.titleKey) (\(language))")
                #expect(body != topic.bodyKey, "missing \(topic.bodyKey) (\(language))")
                #expect(!title.isEmpty)
                #expect(body.count > 20)
            }
        }
    }

    @Test
    func `help center can open logs diagnostics GitHub releases and local user guide`() {
        let destinations = Set(HelpCenterCatalog.destinations)
        #expect(destinations == Set(HelpDestination.allCases))
        #expect(destinations.contains(.logs))
        #expect(destinations.contains(.diagnostics))
        #expect(destinations.contains(.githubReleases))
        #expect(destinations.contains(.userGuide))

        #expect(HelpCenterCatalog.githubReleasesURL == AppIdentity.githubReleasesPageURL)
        #expect(HelpCenterCatalog.githubReleasesURL.absoluteString.contains("/releases"))

        let guide = HelpCenterCatalog.userGuideURL(searchFrom: #filePath)
        #expect(guide != nil)
        #expect(guide?.lastPathComponent == "USER_GUIDE.md")
        if let guide {
            #expect(FileManager.default.fileExists(atPath: guide.path))
            let text = (try? String(contentsOf: guide, encoding: .utf8)) ?? ""
            #expect(text.contains("智额"))
        }

        for destination in HelpDestination.allCases {
            for language in SupportLanguage.allCases {
                let title = SupportCopy.text(destination.titleKey, language)
                #expect(title != destination.titleKey)
                #expect(!title.isEmpty)
            }
            #expect(!destination.accessibilityIdentifier.isEmpty)
        }
    }

    @Test
    func `error copy always says what happened whether data is kept and what to do next`() {
        for kind in SupportErrorKind.allCases {
            for language in SupportLanguage.allCases {
                let copy = SupportErrorCatalog.copy(for: kind, language: language)
                #expect(copy.kind == kind)
                #expect(!copy.whatHappened.isEmpty)
                #expect(!copy.dataRetention.isEmpty)
                #expect(!copy.nextStep.isEmpty)
                #expect(copy.whatHappened != kind.whatKey)
                #expect(copy.dataRetention != kind.keptKey)
                #expect(copy.nextStep != kind.nextKey)
                #expect(copy.fullMessage.contains(copy.whatHappened))
                #expect(copy.fullMessage.contains(copy.dataRetention))
                #expect(copy.fullMessage.contains(copy.nextStep))

                let kept = copy.dataRetention.lowercased()
                let keptSignals = ["保留", "未", "仍", "不变", "kept", "unchanged", "not cleared", "not ", "still", "left"]
                #expect(keptSignals.contains { kept.contains($0) }, "kept text should mention retention: \(copy.dataRetention)")
            }
        }
    }

    @Test
    func `refresh errors classify into distinct copies without mixing login and network`() {
        #expect(SupportErrorCatalog.classify(ProbeError.timeout) == .refreshNetwork)
        #expect(SupportErrorCatalog.classify(ProbeError.authenticationRequired) == .refreshNotLoggedIn)
        #expect(SupportErrorCatalog.classify(ProbeError.sessionExpired()) == .refreshNotLoggedIn)
        #expect(SupportErrorCatalog.classify(ProbeError.cliNotFound("claude")) == .refreshMissingCLI)
        #expect(SupportErrorCatalog.classify(ProbeError.rateLimited(retryAt: Date())) == .refreshServiceRejected)
        #expect(SupportErrorCatalog.classify(ManualUpdateError.network("offline")) == .updateCheckFailed)
        #expect(SupportErrorCatalog.classify(URLError(.notConnectedToInternet)) == .refreshNetwork)
        #expect(
            SupportErrorCatalog.classify(ProbeError.authenticationRequired, providerId: "claude")
                == .refreshNotLoggedIn
        )
        #expect(
            SupportErrorCatalog.classify(ProbeError.authenticationRequired, providerId: "copilot")
                == .refreshMissingKey
        )
        #expect(
            SupportErrorCatalog.classify(ProbeError.sessionExpired(), providerId: "minimax")
                == .refreshMissingKey
        )

        let login = SupportErrorCatalog.copy(for: .refreshNotLoggedIn, language: .zhHans)
        let network = SupportErrorCatalog.copy(for: .refreshNetwork, language: .zhHans)
        let missingKey = SupportErrorCatalog.copy(for: .refreshMissingKey, language: .zhHans)
        #expect(login.whatHappened != network.whatHappened)
        #expect(login.whatHappened != missingKey.whatHappened)
        #expect(login.whatHappened.contains("登录") || login.whatHappened.contains("登录态"))
        #expect(network.whatHappened.contains("网络"))
        #expect(missingKey.whatHappened.contains("密钥") || missingKey.whatHappened.contains("凭证"))
    }

    @Test
    func `diagnostic warning label is not the quota-low string`() {
        let zh = SupportCopy.text("status.severity.warning", .zhHans)
        let en = SupportCopy.text("status.severity.warning", .en)
        #expect(zh == "警告")
        #expect(en == "Warning")
        #expect(!zh.contains("偏低"))
        #expect(AccessibilityChrome.requiredStringKeys.contains("status.severity.warning"))
    }

    @Test
    func `icon buttons have VoiceOver label hint and value keys`() {
        #expect(AccessibilityChrome.iconButtons.count >= 5)
        let ids = Set(AccessibilityChrome.iconButtons.map(\.id))
        #expect(ids.contains(AccessibilityChrome.ID.menuRefresh))
        #expect(ids.contains(AccessibilityChrome.ID.menuPin))
        #expect(ids.contains(AccessibilityChrome.ID.menuHelp))
        #expect(ids.contains(AccessibilityChrome.ID.settingsBack))

        for spec in AccessibilityChrome.iconButtons {
            #expect(!spec.labelKey.isEmpty)
            #expect(!spec.hintKey.isEmpty)
            #expect(!spec.valueKeys.isEmpty)
            for language in SupportLanguage.allCases {
                for key in spec.allKeys {
                    let value = SupportCopy.text(key, language)
                    #expect(SupportCopy.contains(key), "missing support string \(key)")
                    #expect(value != key)
                    #expect(!value.isEmpty)
                }
            }
        }

        #expect(AccessibilityChrome.decorativeElementIds.contains(AccessibilityChrome.ID.decorativeAppLogo))
        #expect(AccessibilityChrome.decorativeElementIds.contains(AccessibilityChrome.ID.decorativeCardIcon))
    }

    @Test
    func `keyboard identifiers cover refresh settings diagnostics help and export`() throws {
        let ids = Set(AccessibilityChrome.keyboardControls.map(\.id))
        #expect(ids.contains(AccessibilityChrome.ID.menuRefresh))
        #expect(ids.contains(AccessibilityChrome.ID.menuSettings))
        #expect(ids.contains(AccessibilityChrome.ID.settingsOpenDiagnostics))
        #expect(ids.contains(AccessibilityChrome.ID.settingsOpenHelp))
        #expect(ids.contains(AccessibilityChrome.ID.helpOpenLogs))
        #expect(ids.contains(AccessibilityChrome.ID.helpOpenDiagnostics))
        #expect(ids.contains(AccessibilityChrome.ID.helpOpenReleases))
        #expect(ids.contains(AccessibilityChrome.ID.helpOpenUserGuide))
        #expect(ids.contains(AccessibilityChrome.ID.recoveryExport))
        #expect(ids.contains(AccessibilityChrome.ID.recoveryReset))
        #expect(ids.contains(AccessibilityChrome.ID.diagRun))

        let refresh = try #require(AccessibilityChrome.keyboardControls.first { $0.id == AccessibilityChrome.ID.menuRefresh })
        #expect(refresh.shortcut == "r")
        let help = try #require(AccessibilityChrome.keyboardControls.first { $0.id == AccessibilityChrome.ID.menuHelp })
        #expect(help.shortcut == "?")
    }

    @Test
    func `help and error strings exist in Chinese and English`() {
        let keys = Set(HelpCenterCatalog.requiredStringKeys)
            .union(SupportErrorCatalog.allL10nKeys)
            .union(AccessibilityChrome.requiredStringKeys)
        #expect(keys.count > 40)
        for key in keys {
            #expect(SupportCopy.contains(key), "missing \(key)")
            let zh = SupportCopy.text(key, .zhHans)
            let en = SupportCopy.text(key, .en)
            #expect(zh != key)
            #expect(en != key)
            #expect(!zh.isEmpty)
            #expect(!en.isEmpty)
        }
    }
}

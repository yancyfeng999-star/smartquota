import Testing
import Foundation
@testable import Domain

@Suite("SettingsMigrationStep Tests")
struct SettingsMigrationStepTests {

    @Test
    func `catalog is unidirectional one version at a time`() {
        let steps = SettingsMigrationCatalog.orderedSteps
        #expect(!steps.isEmpty)
        var expectedFrom = 0
        for step in steps {
            #expect(step.fromVersion == expectedFrom)
            #expect(step.toVersion == step.fromVersion + 1)
            expectedFrom = step.toVersion
        }
        #expect(steps.last?.toVersion == SettingsSchema.currentVersion)
        #expect(SettingsSchema.currentVersion >= 2)
    }

    @Test
    func `v0 step stamps version 1 and does not jump to current`() throws {
        let step = LegacySettingsToV1Step()
        #expect(step.fromVersion == 0)
        #expect(step.toVersion == 1)

        let output = try step.migrate(["legacyRootKey": "keep"])
        #expect(SettingsJSON.intValue(output[SettingsSchema.versionKey]) == 1)
        #expect(output["legacyRootKey"] as? String == "keep")
        let app = try #require(output["app"] as? [String: Any])
        #expect(app["themeMode"] as? String == "system")
        #expect(app["language"] as? String == "zh-Hans")
    }

    @Test
    func `v1 to v2 preserves unknown fields and does not invent v0 mappings`() throws {
        let step = SettingsV1ToV2Step()
        #expect(step.fromVersion == 1)
        #expect(step.toVersion == 2)

        let input: [String: Any] = [
            SettingsSchema.versionKey: 1,
            "legacyRootKey": "must-survive",
            "app": [
                "themeMode": "cli",
                "language": "en",
                "futureV2Flag": "keep-through-v2",
                "overviewMode": true,
            ],
        ]
        let output = try step.migrate(input)
        #expect(SettingsJSON.intValue(output[SettingsSchema.versionKey]) == 2)
        #expect(output["legacyRootKey"] as? String == "must-survive")
        let app = try #require(output["app"] as? [String: Any])
        #expect(app["themeMode"] as? String == "cli")
        #expect(app["futureV2Flag"] as? String == "keep-through-v2")
        #expect(app["overviewMode"] as? Bool == true)
        #expect(app["overviewModeEnabled"] == nil)
        #expect(app["usageDisplayMode"] as? String == "remaining")
    }

    @Test
    func `validator accepts future enum strings and rejects wrong types`() throws {
        var valid: [String: Any] = [
            SettingsSchema.versionKey: SettingsSchema.currentVersion,
            "app": [
                "themeMode": "high-contrast-future",
                "language": "xx-Future",
                "usageDisplayMode": "orbit",
                "membershipOrder": ["claude"],
                "backgroundSyncInterval": 900,
            ],
            "providers": [
                "claude": ["isEnabled": true, "planLabel": "Pro"],
            ],
        ]
        try SettingsValidator.validate(valid, expectedVersion: SettingsSchema.currentVersion)

        valid["app"] = ["themeMode": 42]
        #expect(throws: SettingsPersistenceError.self) {
            try SettingsValidator.validate(valid, expectedVersion: SettingsSchema.currentVersion)
        }
    }

    @Test
    func `file policy is owner-read-write only`() {
        #expect(SettingsSchema.posixFilePermission == 0o600)
    }
}

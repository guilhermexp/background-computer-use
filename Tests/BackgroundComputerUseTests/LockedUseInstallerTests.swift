import BackgroundComputerUseLockedInstaller
import Foundation
import Testing

struct LockedUseInstallerTests {
    private let mechanism = "xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote"

    private func fixture() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "class": "evaluate-mechanisms",
                "tries": 10000,
                "mechanisms": [
                    "builtin:authenticate,privileged",
                    "com.openai.sky.CUAService.AuthorizationPlugin.remote",
                    "use-login-window-ui",
                ],
            ],
            format: .xml,
            options: 0
        )
    }

    @Test
    func dryRunPreservesCodexAndInsertsBeforeLoginUI() throws {
        let installer = LockedUseInstaller(mechanism: mechanism)
        let plan = try installer.plan(
            rightName: "system.login.screensaver",
            currentRule: fixture(),
            pluginSignatureValid: true
        )
        #expect(plan.mutatesAuthorizationDatabase == false)
        let decoded = try #require(
            PropertyListSerialization.propertyList(from: plan.updatedRule, options: [], format: nil) as? [String: Any]
        )
        #expect(decoded["mechanisms"] as? [String] == [
            "builtin:authenticate,privileged",
            "com.openai.sky.CUAService.AuthorizationPlugin.remote",
            mechanism,
            "use-login-window-ui",
        ])
    }

    @Test
    func planningIsIdempotentAndRecoveryRestoresExactBytes() throws {
        let installer = LockedUseInstaller(mechanism: mechanism)
        let first = try installer.plan(
            rightName: "system.login.screensaver",
            currentRule: fixture(),
            pluginSignatureValid: true
        )
        let second = try installer.plan(
            rightName: "system.login.screensaver",
            currentRule: first.updatedRule,
            pluginSignatureValid: true,
            existingBackup: first.backup
        )
        let secondDecoded = try #require(
            PropertyListSerialization.propertyList(from: second.updatedRule, options: [], format: nil) as? [String: Any]
        )
        #expect((secondDecoded["mechanisms"] as? [String])?.filter { $0 == mechanism }.count == 1)
        #expect(try installer.recoveryData(from: first.backup).ruleData == fixture())
        #expect(try installer.recoveryData(from: second.backup).ruleData == fixture())
        #expect(throws: LockedUseInstallerError.existingInstallationMissingBackup) {
            _ = try installer.plan(
                rightName: "system.login.screensaver",
                currentRule: first.updatedRule,
                pluginSignatureValid: true
            )
        }

        var cleanRule = try #require(
            PropertyListSerialization.propertyList(from: fixture(), options: [], format: nil) as? [String: Any]
        )
        cleanRule["tries"] = 42
        let changedCleanRule = try PropertyListSerialization.data(
            fromPropertyList: cleanRule,
            format: .xml,
            options: 0
        )
        let nextCycle = try installer.plan(
            rightName: "system.login.screensaver",
            currentRule: changedCleanRule,
            pluginSignatureValid: true,
            existingBackup: first.backup
        )
        #expect(try installer.recoveryData(from: nextCycle.backup).ruleData == changedCleanRule)
    }

    @Test
    func consoleRightAndInvalidSignatureAreRejected() throws {
        let installer = LockedUseInstaller(mechanism: mechanism)
        #expect(throws: LockedUseInstallerError.forbiddenAuthorizationRight) {
            _ = try installer.plan(
                rightName: "system.login.console",
                currentRule: fixture(),
                pluginSignatureValid: true
            )
        }
        #expect(throws: LockedUseInstallerError.invalidPluginSignature) {
            _ = try installer.plan(
                rightName: "system.login.screensaver",
                currentRule: fixture(),
                pluginSignatureValid: false
            )
        }
    }

    @Test
    func corruptBackupCannotBeRecovered() throws {
        let installer = LockedUseInstaller(mechanism: mechanism)
        let plan = try installer.plan(
            rightName: "system.login.screensaver",
            currentRule: fixture(),
            pluginSignatureValid: true
        )
        var corrupt = plan.backup
        corrupt.ruleData.append(0)
        #expect(throws: LockedUseInstallerError.backupDigestMismatch) {
            _ = try installer.recoveryData(from: corrupt)
        }
    }
}

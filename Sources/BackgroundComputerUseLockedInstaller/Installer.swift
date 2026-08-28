import BackgroundComputerUseLockedShared
import CryptoKit
import Foundation

public enum LockedUseInstallerError: Error, Equatable, Sendable {
    case forbiddenAuthorizationRight
    case invalidPluginSignature
    case backupDigestMismatch
    case invalidBackupVersion
    case invalidBackupRight
    case existingInstallationMissingBackup
}

public struct LockedUseRuleBackup: Codable, Sendable {
    public var version: Int
    public var rightName: String
    public var ruleData: Data
    public var sha256: Data

    public init(version: Int, rightName: String, ruleData: Data, sha256: Data) {
        self.version = version
        self.rightName = rightName
        self.ruleData = ruleData
        self.sha256 = sha256
    }
}

public struct LockedUseInstallPlan: Sendable {
    public let rightName: String
    public let mechanism: String
    public let originalRule: Data
    public let updatedRule: Data
    public let backup: LockedUseRuleBackup
    public let mutatesAuthorizationDatabase: Bool
}

public struct LockedUseRecoveryData: Sendable {
    public let rightName: String
    public let ruleData: Data
}

public struct LockedUseInstaller: Sendable {
    public static let allowedRight = "system.login.screensaver"
    public let mechanism: String

    public init(mechanism: String) {
        self.mechanism = mechanism
    }

    public func plan(
        rightName: String,
        currentRule: Data,
        pluginSignatureValid: Bool,
        existingBackup: LockedUseRuleBackup? = nil
    ) throws -> LockedUseInstallPlan {
        guard rightName == Self.allowedRight else {
            throw LockedUseInstallerError.forbiddenAuthorizationRight
        }
        guard pluginSignatureValid else {
            throw LockedUseInstallerError.invalidPluginSignature
        }
        let snapshot = try AuthorizationRuleSnapshot(data: currentRule)
        if snapshot.contains(mechanism: mechanism), existingBackup == nil {
            throw LockedUseInstallerError.existingInstallationMissingBackup
        }
        let updated = try snapshot.inserting(mechanism: mechanism)
        let backup: LockedUseRuleBackup
        if snapshot.contains(mechanism: mechanism), let existingBackup {
            _ = try recoveryData(from: existingBackup)
            backup = existingBackup
        } else {
            backup = LockedUseRuleBackup(
                version: 1,
                rightName: rightName,
                ruleData: currentRule,
                sha256: digest(currentRule)
            )
        }
        return LockedUseInstallPlan(
            rightName: rightName,
            mechanism: mechanism,
            originalRule: currentRule,
            updatedRule: updated,
            backup: backup,
            mutatesAuthorizationDatabase: false
        )
    }

    public func recoveryData(from backup: LockedUseRuleBackup) throws -> LockedUseRecoveryData {
        guard backup.version == 1 else {
            throw LockedUseInstallerError.invalidBackupVersion
        }
        guard backup.rightName == Self.allowedRight else {
            throw LockedUseInstallerError.invalidBackupRight
        }
        guard constantTimeEqual(backup.sha256, digest(backup.ruleData)) else {
            throw LockedUseInstallerError.backupDigestMismatch
        }
        return LockedUseRecoveryData(
            rightName: backup.rightName,
            ruleData: backup.ruleData
        )
    }

    private func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { partial, pair in
            partial | (pair.0 ^ pair.1)
        } == 0
    }
}

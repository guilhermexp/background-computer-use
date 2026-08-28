import BackgroundComputerUseLockedInstaller
import Foundation

private func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

guard let command = CommandLine.arguments.dropFirst().first else {
    fail("usage: BackgroundComputerUseLockedRecovery plan|recover ...")
}

let installer = LockedUseInstaller(
    mechanism: "xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote"
)

do {
    switch command {
    case "plan":
        guard let rulePath = argument("--rule"),
              let updatedPath = argument("--updated"),
              let backupPath = argument("--backup")
        else {
            fail("plan requires --rule, --updated, and --backup")
        }
        let signatureValid = argument("--signature-valid") == "true"
        let existingBackup = try argument("--existing-backup").map {
            try JSONDecoder().decode(
                LockedUseRuleBackup.self,
                from: Data(contentsOf: URL(fileURLWithPath: $0))
            )
        }
        let plan = try installer.plan(
            rightName: argument("--right") ?? LockedUseInstaller.allowedRight,
            currentRule: Data(contentsOf: URL(fileURLWithPath: rulePath)),
            pluginSignatureValid: signatureValid,
            existingBackup: existingBackup
        )
        try plan.updatedRule.write(to: URL(fileURLWithPath: updatedPath), options: .atomic)
        let backupData = try JSONEncoder().encode(plan.backup)
        try backupData.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: backupPath
        )
        print("dry_run=true right=\(plan.rightName) mechanism=\(plan.mechanism)")

    case "recover":
        guard let backupPath = argument("--backup"),
              let outputPath = argument("--output")
        else {
            fail("recover requires --backup and --output")
        }
        let backup = try JSONDecoder().decode(
            LockedUseRuleBackup.self,
            from: Data(contentsOf: URL(fileURLWithPath: backupPath))
        )
        let recovery = try installer.recoveryData(from: backup)
        try recovery.ruleData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("recovery_valid=true right=\(recovery.rightName)")

    default:
        fail("unknown command: \(command)")
    }
} catch {
    fail("locked-use recovery error: \(error)")
}

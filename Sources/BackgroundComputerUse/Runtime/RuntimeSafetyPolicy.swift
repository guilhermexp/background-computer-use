import Foundation

struct RuntimeSafetyDecision: Sendable {
    let blocked: Bool
    let reason: String?

    static let allowed = RuntimeSafetyDecision(blocked: false, reason: nil)

    static func blocked(_ reason: String) -> RuntimeSafetyDecision {
        RuntimeSafetyDecision(blocked: true, reason: reason)
    }
}

enum RuntimeSafetyPolicy {
    private static let destructivePatterns = [
        "delete",
        "remove",
        "erase",
        "trash",
        "discard",
        "don't save",
        "dont save",
        "reset",
        "format",
        "uninstall",
        "destroy",
        "wipe",
        "shut down",
        "log out",
        "cancel subscription",
        "kill build",
        "clear deployments",
    ]

    static func evaluateLabel(_ label: String?, confirmed: Bool) -> RuntimeSafetyDecision {
        guard confirmed == false,
              let label,
              label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .allowed
        }

        let normalized = label.lowercased()
        guard let pattern = destructivePatterns.first(where: { normalized.contains($0) }) else {
            return .allowed
        }

        return .blocked(
            "\"\(label)\" looks destructive or irreversible (matched \"\(pattern)\"). Retry with confirm=true to proceed."
        )
    }

    static func evaluateValueChange(
        currentValue: String?,
        newValue: String,
        confirmed: Bool
    ) -> RuntimeSafetyDecision {
        guard confirmed == false else {
            return .allowed
        }
        guard let currentValue,
              currentValue.isEmpty == false,
              newValue.isEmpty else {
            return .allowed
        }
        return .blocked("This action clears an existing value. Retry with confirm=true to proceed.")
    }

    static func evaluateSecureTextEntry(
        rawRole: String?,
        rawSubrole: String?,
        displayRole: String?,
        confirmed: Bool
    ) -> RuntimeSafetyDecision {
        guard confirmed == false else {
            return .allowed
        }
        let signals = [rawRole, rawSubrole, displayRole]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard signals.contains("secure") || signals.contains("password") else {
            return .allowed
        }
        return .blocked("The target looks like a secure/password text field. Retry with confirm=true to proceed.")
    }

    static func evaluateKey(_ key: String, confirmed: Bool) -> RuntimeSafetyDecision {
        guard confirmed == false else {
            return .allowed
        }
        let normalized = key
            .lowercased()
            .replacingOccurrences(of: "super", with: "command")
            .replacingOccurrences(of: "cmd", with: "command")
        guard normalized.contains("command"),
              normalized.contains("delete") || normalized.contains("backspace") else {
            return .allowed
        }
        return .blocked("\"\(key)\" looks like a destructive keyboard shortcut. Retry with confirm=true to proceed.")
    }
}

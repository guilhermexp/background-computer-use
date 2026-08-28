import Foundation

public enum AuthorizationRuleSnapshotError: Error, Equatable, Sendable {
    case invalidPropertyList
    case invalidRuleDictionary
    case missingMechanisms
}

public struct AuthorizationRuleSnapshot: @unchecked Sendable {
    private let originalData: Data
    private let originalRule: [String: Any]
    private let format: PropertyListSerialization.PropertyListFormat

    public init(data: Data) throws {
        var detectedFormat = PropertyListSerialization.PropertyListFormat.xml
        guard let rule = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &detectedFormat
        ) as? [String: Any] else {
            throw AuthorizationRuleSnapshotError.invalidPropertyList
        }
        guard rule["mechanisms"] is [String] else {
            throw AuthorizationRuleSnapshotError.missingMechanisms
        }
        originalData = data
        originalRule = rule
        format = detectedFormat
    }

    public func inserting(mechanism: String) throws -> Data {
        guard mechanism.isEmpty == false else {
            throw AuthorizationRuleSnapshotError.invalidRuleDictionary
        }
        var rule = originalRule
        guard var mechanisms = rule["mechanisms"] as? [String] else {
            throw AuthorizationRuleSnapshotError.missingMechanisms
        }
        if mechanisms.contains(mechanism) == false {
            if let loginUI = mechanisms.firstIndex(of: "use-login-window-ui") {
                mechanisms.insert(mechanism, at: loginUI)
            } else {
                mechanisms.append(mechanism)
            }
        }
        rule["mechanisms"] = mechanisms
        return try PropertyListSerialization.data(
            fromPropertyList: rule,
            format: format,
            options: 0
        )
    }

    public func restoreData() -> Data {
        originalData
    }

    public func contains(mechanism: String) -> Bool {
        (originalRule["mechanisms"] as? [String])?.contains(mechanism) == true
    }

    public func isSemanticallyEqualToOriginal(_ candidate: Data) throws -> Bool {
        guard let decoded = try? PropertyListSerialization.propertyList(
            from: candidate,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw AuthorizationRuleSnapshotError.invalidPropertyList
        }
        return NSDictionary(dictionary: decoded).isEqual(to: originalRule)
    }
}

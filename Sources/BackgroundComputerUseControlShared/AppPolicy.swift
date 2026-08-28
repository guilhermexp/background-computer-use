import Foundation

public enum AppPolicyDecision: String, Codable, Sendable {
    case ask
    case allowOnce
    case alwaysAllow
    case deny
}

public enum AppPolicyError: Error, Equatable, Sendable {
    case protectedIdentity
    case sessionRequired
    case invalidPersistentDecision
    case invalidPersistence
}

private struct PersistedPolicyRecord: Codable {
    let identity: AppIdentity
    let decision: AppPolicyDecision
}

private struct PersistedPolicyFile: Codable {
    let version: Int
    let records: [PersistedPolicyRecord]
}

public final class AppPolicyStore: @unchecked Sendable {
    private let fileURL: URL
    private let protectedBundleIDs: Set<String>
    private let lock = NSLock()
    private var persisted: [AppIdentity: AppPolicyDecision]
    private var sessionAllows: [String: Set<AppIdentity>] = [:]

    public init(
        fileURL: URL,
        protectedBundleIDs: Set<String> = AppPolicyStore.defaultProtectedBundleIDs
    ) throws {
        self.fileURL = fileURL
        self.protectedBundleIDs = protectedBundleIDs
        persisted = try Self.load(fileURL: fileURL)
    }

    public func evaluate(identity: AppIdentity, sessionID: String?) -> AppPolicyDecision {
        lock.lock()
        defer { lock.unlock() }
        if protectedBundleIDs.contains(identity.bundleID) {
            return .deny
        }
        if persisted[identity] == .deny {
            return .deny
        }
        if let sessionID, sessionAllows[sessionID]?.contains(identity) == true {
            return .allowOnce
        }
        if persisted[identity] == .alwaysAllow {
            return .alwaysAllow
        }
        return .ask
    }

    public func set(
        _ decision: AppPolicyDecision,
        for identity: AppIdentity,
        sessionID: String?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if protectedBundleIDs.contains(identity.bundleID), decision != .deny, decision != .ask {
            throw AppPolicyError.protectedIdentity
        }

        switch decision {
        case .ask:
            persisted.removeValue(forKey: identity)
            removeSessionAllows(for: identity)
            try persistLocked()

        case .allowOnce:
            guard let sessionID, sessionID.isEmpty == false else {
                throw AppPolicyError.sessionRequired
            }
            guard persisted[identity] != .deny else { return }
            sessionAllows[sessionID, default: []].insert(identity)

        case .alwaysAllow:
            persisted[identity] = .alwaysAllow
            removeSessionAllows(for: identity)
            try persistLocked()

        case .deny:
            persisted[identity] = .deny
            removeSessionAllows(for: identity)
            try persistLocked()
        }
    }

    public func endSession(_ sessionID: String) {
        lock.lock()
        sessionAllows.removeValue(forKey: sessionID)
        lock.unlock()
    }

    public func endAllSessions() {
        lock.lock()
        sessionAllows.removeAll()
        lock.unlock()
    }

    public func revoke(identity: AppIdentity) throws {
        try set(.ask, for: identity, sessionID: nil)
    }

    public func persistedPolicies() -> [(identity: AppIdentity, decision: AppPolicyDecision)] {
        lock.lock()
        defer { lock.unlock() }
        return persisted
            .map { (identity: $0.key, decision: $0.value) }
            .sorted { left, right in
                if left.identity.bundleID != right.identity.bundleID {
                    return left.identity.bundleID < right.identity.bundleID
                }
                return left.identity.teamID < right.identity.teamID
            }
    }

    public static let defaultProtectedBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
    ]

    private func removeSessionAllows(for identity: AppIdentity) {
        for sessionID in Array(sessionAllows.keys) {
            sessionAllows[sessionID]?.remove(identity)
            if sessionAllows[sessionID]?.isEmpty == true {
                sessionAllows.removeValue(forKey: sessionID)
            }
        }
    }

    private func persistLocked() throws {
        let directory = fileURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directory.path
            )
        }
        let records = persisted.map { PersistedPolicyRecord(identity: $0.key, decision: $0.value) }
            .sorted { left, right in
                if left.identity.bundleID != right.identity.bundleID {
                    return left.identity.bundleID < right.identity.bundleID
                }
                return left.identity.teamID < right.identity.teamID
            }
        let data = try JSONEncoder().encode(PersistedPolicyFile(version: 1, records: records))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
    }

    private static func load(fileURL: URL) throws -> [AppIdentity: AppPolicyDecision] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        guard let decoded = try? JSONDecoder().decode(
            PersistedPolicyFile.self,
            from: Data(contentsOf: fileURL)
        ), decoded.version == 1 else {
            throw AppPolicyError.invalidPersistence
        }
        var result: [AppIdentity: AppPolicyDecision] = [:]
        for record in decoded.records {
            guard record.decision == .alwaysAllow || record.decision == .deny else {
                throw AppPolicyError.invalidPersistentDecision
            }
            if result.updateValue(record.decision, forKey: record.identity) != nil {
                throw AppPolicyError.invalidPersistence
            }
        }
        return result
    }
}

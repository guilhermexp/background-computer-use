@testable import BackgroundComputerUseControlShared
import Foundation
import Testing

struct AppPolicyTests {
    private func identity(teamID: String = "TEAMONE", bundleID: String = "com.example.Editor") -> AppIdentity {
        AppIdentity(
            bundleID: bundleID,
            teamID: teamID,
            designatedRequirement: "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        )
    }

    @Test
    func sameBundleWithDifferentSignerDoesNotReusePersistentAllow() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppPolicyStore(fileURL: file)
        try store.set(.alwaysAllow, for: identity(), sessionID: nil)

        #expect(store.evaluate(identity: identity(), sessionID: "session") == .alwaysAllow)
        #expect(store.evaluate(identity: identity(teamID: "TEAMTWO"), sessionID: "session") == .ask)
    }

    @Test
    func allowOnceExpiresWithItsSession() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppPolicyStore(fileURL: file)
        try store.set(.allowOnce, for: identity(), sessionID: "session-a")

        #expect(store.evaluate(identity: identity(), sessionID: "session-a") == .allowOnce)
        #expect(store.evaluate(identity: identity(), sessionID: "session-b") == .ask)
        store.endSession("session-a")
        #expect(store.evaluate(identity: identity(), sessionID: "session-a") == .ask)
    }

    @Test
    func denyOverridesExistingAllows() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppPolicyStore(fileURL: file)
        try store.set(.allowOnce, for: identity(), sessionID: "session")
        try store.set(.deny, for: identity(), sessionID: nil)

        #expect(store.evaluate(identity: identity(), sessionID: "session") == .deny)
    }

    @Test
    func protectedIdentityCannotBeAllowed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let protected = identity(bundleID: "com.apple.keychainaccess")
        let store = try AppPolicyStore(
            fileURL: file,
            protectedBundleIDs: [protected.bundleID]
        )

        #expect(throws: AppPolicyError.protectedIdentity) {
            try store.set(.alwaysAllow, for: protected, sessionID: nil)
        }
        #expect(store.evaluate(identity: protected, sessionID: "session") == .deny)
    }

    @Test
    func persistenceIsOwnerOnlyAndSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("policies.json")
        let store = try AppPolicyStore(fileURL: file)
        try store.set(.alwaysAllow, for: identity(), sessionID: nil)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let reloaded = try AppPolicyStore(fileURL: file)
        #expect(reloaded.evaluate(identity: identity(), sessionID: nil) == .alwaysAllow)
    }
}

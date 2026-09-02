import Foundation

enum RuntimeBuildIdentity {
    static let current = load(from: Bundle.main.infoDictionary ?? [:])

    static func load(from info: [String: Any]) -> RuntimeBuildIdentityDTO {
        guard let identity = info["BCUBuildIdentity"] as? String,
              let commit = info["BCUBuildCommit"] as? String,
              let dirty = info["BCUBuildDirty"] as? Bool,
              let digest = info["BCUSourcesSHA256"] as? String
        else {
            return RuntimeBuildIdentityDTO(
                identity: "development-unknown",
                commit: "unknown",
                dirty: true,
                sourcesSHA256: "unknown"
            )
        }
        return RuntimeBuildIdentityDTO(
            identity: identity,
            commit: commit,
            dirty: dirty,
            sourcesSHA256: digest
        )
    }
}

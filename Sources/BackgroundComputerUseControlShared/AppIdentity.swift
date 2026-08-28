import Foundation

public struct AppIdentity: Codable, Hashable, Sendable {
    public let bundleID: String
    public let teamID: String
    public let designatedRequirement: String

    public init(bundleID: String, teamID: String, designatedRequirement: String) {
        self.bundleID = bundleID
        self.teamID = teamID
        self.designatedRequirement = designatedRequirement
    }
}

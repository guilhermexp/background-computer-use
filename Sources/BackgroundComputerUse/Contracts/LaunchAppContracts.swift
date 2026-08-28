import BackgroundComputerUseControlShared
import Foundation

public struct LaunchAppRequest: Decodable, Sendable {
    public let bundleID: String?
    public let appPath: String?
    public let sessionID: String

    public init(bundleID: String?, appPath: String?, sessionID: String) {
        self.bundleID = bundleID
        self.appPath = appPath
        self.sessionID = sessionID
    }
}

public enum LaunchAppStateDTO: String, Encodable, Sendable {
    case blocked
    case alreadyRunning = "already_running"
    case launched
}

public struct LaunchAppResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let classification: ActionClassificationDTO
    public let failureDomain: ActionFailureDomainDTO?
    public let summary: String
    public let identity: AppIdentity?
    public let policyDecision: AppPolicyDecision
    public let pid: pid_t?
    public let launchState: LaunchAppStateDTO
    public let windows: [String]
    public let activates: Bool
    public let foregroundPIDBefore: pid_t?
    public let foregroundPIDAfter: pid_t?
    public let foregroundPreserved: Bool
}

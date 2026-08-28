import BackgroundComputerUseControlShared
import Foundation

@objc public protocol LockedUseBrokerXPCProtocol: NSObjectProtocol {
    func armLease(_ encodedLease: Data, reply: @escaping (Bool) -> Void)
    func consumeCurrentLease(reply: @escaping (Bool) -> Void)
    func heartbeat(taskSessionID: String, reply: @escaping (Bool) -> Void)
    func revoke(taskSessionID: String, reply: @escaping () -> Void)
    func relock(reason: String, reply: @escaping (Bool) -> Void)
    func manualUnlockObserved(reply: @escaping (Bool) -> Void)
}

public enum LockedUseBrokerMachService {
    public static let name = "xyz.dubdub.backgroundcomputeruse.locked-broker"
}

public enum LockedUseBrokerPeerRole: String, Codable, Sendable {
    case control
    case core
    case authorizationHost = "authorization_host"
}

public struct LockedUseBrokerPeer: Codable, Hashable, Sendable {
    public let identity: AppIdentity
    public let role: LockedUseBrokerPeerRole

    public init(identity: AppIdentity, role: LockedUseBrokerPeerRole) {
        self.identity = identity
        self.role = role
    }
}

import BackgroundComputerUseControlShared
import BackgroundComputerUseLockedShared
import Foundation

public final class LockedUseBrokerConnectionService: NSObject, LockedUseBrokerXPCProtocol, @unchecked Sendable {
    private let broker: LockedUseBrokerService
    private let role: LockedUseBrokerPeerRole
    private let identity: AppIdentity

    public init(
        broker: LockedUseBrokerService,
        role: LockedUseBrokerPeerRole,
        identity: AppIdentity
    ) {
        self.broker = broker
        self.role = role
        self.identity = identity
    }

    public func armLease(_ encodedLease: Data, reply: @escaping (Bool) -> Void) {
        guard role == .control,
              let lease = try? JSONDecoder().decode(LockedUseLease.self, from: encodedLease)
        else {
            reply(false)
            return
        }
        reply(broker.arm(
            lease,
            authenticatedControlDesignatedRequirement: identity.designatedRequirement
        ))
    }

    public func consumeCurrentLease(reply: @escaping (Bool) -> Void) {
        guard role == .authorizationHost else { reply(false); return }
        reply(broker.consumeCurrentLease())
    }

    public func heartbeat(taskSessionID: String, reply: @escaping (Bool) -> Void) {
        guard role == .control else { reply(false); return }
        reply(broker.heartbeat(taskSessionID: taskSessionID))
    }

    public func revoke(taskSessionID: String, reply: @escaping () -> Void) {
        if role == .control {
            broker.revoke(taskSessionID: taskSessionID)
            reply()
        } else {
            reply()
        }
    }

    public func relock(reason: String, reply: @escaping (Bool) -> Void) {
        guard role == .control else { reply(false); return }
        reply(broker.relock(reason: reason))
    }

    public func manualUnlockObserved(reply: @escaping (Bool) -> Void) {
        guard role == .control else { reply(false); return }
        reply(broker.manualUnlockObserved())
    }
}

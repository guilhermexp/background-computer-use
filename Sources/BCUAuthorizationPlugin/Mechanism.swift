import Foundation

public enum AuthorizationMechanismResult: Equatable, Sendable {
    case allow
    case deny
}

public protocol AuthorizationBrokerClient {
    func consumeLease() throws -> Bool
}

public protocol AuthorizationMechanismCallbacks: AnyObject {
    func setResult(_ result: AuthorizationMechanismResult)
    func didDeactivate()
}

public final class AuthorizationMechanism: @unchecked Sendable {
    private let lock = NSLock()
    private weak var callbacks: (any AuthorizationMechanismCallbacks)?
    private var broker: (any AuthorizationBrokerClient)?
    private var resolved = false
    private var deactivated = false
    public private(set) var isDestroyed = false

    public init(
        callbacks: any AuthorizationMechanismCallbacks,
        broker: any AuthorizationBrokerClient
    ) {
        self.callbacks = callbacks
        self.broker = broker
    }

    public func invoke() {
        lock.lock()
        guard resolved == false else {
            lock.unlock()
            return
        }
        let callbacks = callbacks
        let broker = broker
        let mustDeny = deactivated || isDestroyed
        resolved = true
        lock.unlock()

        if mustDeny {
            callbacks?.setResult(.deny)
            return
        }
        let brokerAllowed = (try? broker?.consumeLease()) == true
        lock.lock()
        let result: AuthorizationMechanismResult =
            deactivated || isDestroyed || brokerAllowed == false ? .deny : .allow
        lock.unlock()
        callbacks?.setResult(result)
    }

    public func deactivate() {
        lock.lock()
        let shouldAcknowledge = deactivated == false
        deactivated = true
        let callbacks = callbacks
        lock.unlock()
        if shouldAcknowledge {
            callbacks?.didDeactivate()
        }
    }

    public func destroy() {
        lock.lock()
        isDestroyed = true
        broker = nil
        lock.unlock()
    }
}

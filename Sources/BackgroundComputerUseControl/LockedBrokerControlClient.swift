import BackgroundComputerUseLockedShared
import Foundation

public final class LockedBrokerControlClient: LockedUseBrokerControlling, @unchecked Sendable {
    public init() {}

    public func arm(_ lease: LockedUseLease) -> Bool {
        guard let data = try? JSONEncoder().encode(lease) else { return false }
        return call { broker, reply in broker.armLease(data, reply: reply) }
    }

    public func revoke(taskSessionID: String) {
        let connection = makeConnection()
        defer { connection.invalidate() }
        guard let broker = connection.remoteObjectProxy as? LockedUseBrokerXPCProtocol else { return }
        let semaphore = DispatchSemaphore(value: 0)
        broker.revoke(taskSessionID: taskSessionID) { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 1)
    }

    public func relock(reason: String) -> Bool {
        call { broker, reply in broker.relock(reason: reason, reply: reply) }
    }

    public func heartbeat(taskSessionID: String) -> Bool {
        call { broker, reply in broker.heartbeat(taskSessionID: taskSessionID, reply: reply) }
    }

    public func manualUnlockObserved() {
        _ = call { broker, reply in broker.manualUnlockObserved(reply: reply) }
    }

    private func call(
        _ body: (LockedUseBrokerXPCProtocol, @escaping (Bool) -> Void) -> Void
    ) -> Bool {
        let connection = makeConnection()
        defer { connection.invalidate() }
        guard let broker = connection.remoteObjectProxy as? LockedUseBrokerXPCProtocol else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBrokerBoolBox()
        body(broker) { value in box.set(value); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 1) == .success else { return false }
        return box.value
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: LockedUseBrokerMachService.name,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LockedUseBrokerXPCProtocol.self)
        connection.resume()
        return connection
    }
}

private final class LockedBrokerBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        lock.lock(); defer { lock.unlock() }; return stored
    }

    func set(_ value: Bool) {
        lock.lock(); stored = value; lock.unlock()
    }
}

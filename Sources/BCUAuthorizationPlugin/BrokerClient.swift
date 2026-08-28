import BackgroundComputerUseLockedShared
import Foundation

struct XPCBrokerClient: AuthorizationBrokerClient {
    func consumeLease() throws -> Bool {
        let connection = NSXPCConnection(
            machServiceName: LockedUseBrokerMachService.name,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LockedUseBrokerXPCProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        let box = BrokerReplyBox()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            box.set(false)
            semaphore.signal()
        }
        guard let broker = proxy as? LockedUseBrokerXPCProtocol else {
            return false
        }
        broker.consumeCurrentLease { allowed in
            box.set(allowed)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 1) == .success else { return false }
        return box.value
    }
}

private final class BrokerReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Bool) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

@_cdecl("BCUAuthorizationPluginConsumeLease")
public func BCUAuthorizationPluginConsumeLease() -> Int32 {
    ((try? XPCBrokerClient().consumeLease()) == true) ? 1 : 0
}

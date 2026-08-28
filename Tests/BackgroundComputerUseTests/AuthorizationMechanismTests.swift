import BCUAuthorizationPlugin
import Foundation
import Testing

struct AuthorizationMechanismTests {
    @Test
    func validConsumedLeaseAllowsExactlyOnce() {
        let callbacks = FakeAuthorizationCallbacks()
        let mechanism = AuthorizationMechanism(
            callbacks: callbacks,
            broker: FakeBrokerClient(result: .success(true))
        )
        mechanism.invoke()
        mechanism.invoke()

        #expect(callbacks.results == [.allow])
    }

    @Test
    func everyBrokerErrorDeniesExactlyOnce() {
        let callbacks = FakeAuthorizationCallbacks()
        let mechanism = AuthorizationMechanism(
            callbacks: callbacks,
            broker: FakeBrokerClient(result: .failure(FakeError.failed))
        )
        mechanism.invoke()
        mechanism.invoke()

        #expect(callbacks.results == [.deny])
    }

    @Test
    func deactivateAcknowledgesAndPreventsLaterAllow() {
        let callbacks = FakeAuthorizationCallbacks()
        let mechanism = AuthorizationMechanism(
            callbacks: callbacks,
            broker: FakeBrokerClient(result: .success(true))
        )
        mechanism.deactivate()
        mechanism.invoke()

        #expect(callbacks.deactivations == 1)
        #expect(callbacks.results == [.deny])
    }

    @Test
    func destroyReleasesMechanismState() {
        let callbacks = FakeAuthorizationCallbacks()
        let mechanism = AuthorizationMechanism(
            callbacks: callbacks,
            broker: FakeBrokerClient(result: .success(true))
        )
        mechanism.destroy()
        mechanism.invoke()

        #expect(mechanism.isDestroyed)
        #expect(callbacks.results == [.deny])
    }

    @Test
    func deactivationWhileBrokerConsumeIsPendingNeverAllows() async {
        let callbacks = FakeAuthorizationCallbacks()
        let broker = BlockingBrokerClient()
        let mechanism = AuthorizationMechanism(callbacks: callbacks, broker: broker)
        let invocation = Task.detached { mechanism.invoke() }
        for _ in 0 ..< 1000 where broker.hasStarted == false {
            await Task.yield()
        }
        #expect(broker.hasStarted)

        mechanism.deactivate()
        broker.release.signal()
        await invocation.value

        #expect(callbacks.deactivations == 1)
        #expect(callbacks.results == [.deny])
    }
}

private enum FakeError: Error { case failed }

private struct FakeBrokerClient: AuthorizationBrokerClient {
    let result: Result<Bool, Error>
    func consumeLease() throws -> Bool {
        try result.get()
    }
}

private final class BlockingBrokerClient: AuthorizationBrokerClient, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    let release = DispatchSemaphore(value: 0)

    var hasStarted: Bool {
        lock.lock(); defer { lock.unlock() }; return started
    }

    func consumeLease() throws -> Bool {
        lock.lock(); started = true; lock.unlock()
        _ = release.wait(timeout: .now() + 1)
        return true
    }
}

private final class FakeAuthorizationCallbacks: AuthorizationMechanismCallbacks, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [AuthorizationMechanismResult] = []
    private var storedDeactivations = 0

    var results: [AuthorizationMechanismResult] {
        lock.lock(); defer { lock.unlock() }; return storedResults
    }

    var deactivations: Int {
        lock.lock(); defer { lock.unlock() }; return storedDeactivations
    }

    func setResult(_ result: AuthorizationMechanismResult) {
        lock.lock(); storedResults.append(result); lock.unlock()
    }

    func didDeactivate() {
        lock.lock(); storedDeactivations += 1; lock.unlock()
    }
}

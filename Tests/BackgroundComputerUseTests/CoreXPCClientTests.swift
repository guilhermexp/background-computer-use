import BackgroundComputerUseControl
import BackgroundComputerUseControlShared
import Testing

struct CoreXPCClientTests {
    @Test
    func unavailableTransportFailsClosed() {
        let client = CoreXPCClient(sessionID: "task", transportFactory: { nil })
        #expect(client.start() == false)
        #expect(client.allows(.read) == false)
        #expect(client.allows(.mutation) == false)
    }

    @Test
    func clientRehydratesPausedStateAfterServiceRestart() {
        var authority = CoreSessionAuthority()
        let client = CoreXPCClient(
            sessionID: "task",
            transportFactory: { FakeCoreXPCTransport(authority: authority) }
        )
        #expect(client.start())
        #expect(client.setState(.paused))
        #expect(client.allows(.read))
        #expect(client.allows(.mutation) == false)

        authority = CoreSessionAuthority()
        #expect(client.allows(.read))
        #expect(client.allows(.mutation) == false)
    }

    @Test
    func stoppedClientCannotBeReactivatedInTheSameSession() {
        let authority = CoreSessionAuthority()
        let client = CoreXPCClient(
            sessionID: "task",
            transportFactory: { FakeCoreXPCTransport(authority: authority) }
        )
        #expect(client.start())
        #expect(client.setState(.stopped))
        #expect(client.setState(.active) == false)
        #expect(client.allows(.read) == false)
    }
}

private final class FakeCoreXPCTransport: CoreXPCTransporting, @unchecked Sendable {
    let authority: CoreSessionAuthority

    init(authority: CoreSessionAuthority) {
        self.authority = authority
    }

    func ping() -> Bool {
        true
    }

    func configure(sessionID: String, state: CoreSessionState) -> Bool {
        authority.configure(sessionID: sessionID, state: state)
    }

    func transition(sessionID: String, state: CoreSessionState) -> Bool {
        authority.transition(sessionID: sessionID, to: state)
    }

    func authorize(sessionID: String, operation: CoreOperationKind) -> CoreAuthorizationDecision {
        authority.authorize(sessionID: sessionID, operation: operation)
    }
}

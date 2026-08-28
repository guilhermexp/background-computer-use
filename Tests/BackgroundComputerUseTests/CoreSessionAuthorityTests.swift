import BackgroundComputerUseControlShared
import Testing

struct CoreSessionAuthorityTests {
    @Test
    func unconfiguredAuthorityFailsClosed() {
        let authority = CoreSessionAuthority()
        #expect(authority.authorize(sessionID: "task", operation: .read) == .unavailable)
        #expect(authority.authorize(sessionID: "task", operation: .mutation) == .unavailable)
    }

    @Test
    func pausePreservesReadsAndBlocksMutations() {
        let authority = CoreSessionAuthority()
        #expect(authority.configure(sessionID: "task", state: .active))
        #expect(authority.transition(sessionID: "task", to: .paused))
        #expect(authority.authorize(sessionID: "task", operation: .read) == .allowed)
        #expect(authority.authorize(sessionID: "task", operation: .mutation) == .paused)
    }

    @Test
    func stopIsIrreversibleForTheSameSessionAndWrongSessionDenies() {
        let authority = CoreSessionAuthority()
        #expect(authority.configure(sessionID: "task", state: .active))
        #expect(authority.transition(sessionID: "task", to: .stopped))
        #expect(authority.transition(sessionID: "task", to: .active) == false)
        #expect(authority.authorize(sessionID: "task", operation: .read) == .stopped)
        #expect(authority.authorize(sessionID: "other", operation: .read) == .sessionMismatch)
    }

    @Test
    func aNewSessionCanBeConfiguredAfterAStoppedSession() {
        let authority = CoreSessionAuthority()
        #expect(authority.configure(sessionID: "old", state: .active))
        #expect(authority.transition(sessionID: "old", to: .stopped))
        #expect(authority.configure(sessionID: "new", state: .active))
        #expect(authority.authorize(sessionID: "new", operation: .mutation) == .allowed)
    }
}

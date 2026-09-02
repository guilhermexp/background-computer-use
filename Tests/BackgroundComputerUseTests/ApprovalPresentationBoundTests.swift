import Foundation
import Testing
@testable import BackgroundComputerUseControl
@testable import BackgroundComputerUseControlShared

/// `NSAlert.runModal()` owns the main run loop and does not drain the main dispatch
/// queue, so an approval arriving while another alert is up must not park its request
/// thread forever. Measured 2026-09-02 before this bound existed: a request thread sat
/// in `DispatchQueue.main.sync` for the whole 5m56s life of the runtime and every
/// window-authorizing route hung with no error.
@Suite(.serialized)
struct ApprovalPresentationBoundTests {
    private static func request() -> ApprovalRequest {
        ApprovalRequest(
            id: "ar_bound",
            identity: AppIdentity(
                bundleID: "com.example.fixture",
                teamID: "adhoc-cdhash:abc123",
                designatedRequirement: "cdhash H\"abc123\""
            ),
            pid: 4242,
            sessionID: "bound-session",
            operation: "click"
        )
    }

    @Test
    func starvedMainThreadDeniesWithinTheBoundInsteadOfHanging() async throws {
        let presenter = ApprovalWindowPresenter(
            timeout: 0.2,
            waitGrace: 0.1,
            dispatchToMain: { _ in }
        )
        #expect(abs(presenter.waitBound - 0.3) < 0.001)

        let decision = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: presenter.present(Self.request()))
            }
        }

        #expect(decision == .deny)
    }

    @Test
    func abandonedPresentationIsNeverShown() {
        let handoff = ApprovalHandoff()

        #expect(handoff.wait(timeout: 0.05) == .deny)
        // The main thread finally gets around to the block after the waiter gave up.
        #expect(handoff.beginPresentation() == false)
    }

    @Test
    func decisionReachesTheWaiterWhenPresentationCompletesInTime() async throws {
        let handoff = ApprovalHandoff()
        #expect(handoff.beginPresentation())

        Thread.detachNewThread {
            handoff.finish(.allowOnce)
        }

        #expect(handoff.wait(timeout: 5) == .allowOnce)
    }

    @Test
    func onlyOnePresentationCanStartPerRequest() {
        let handoff = ApprovalHandoff()

        #expect(handoff.beginPresentation())
        #expect(handoff.beginPresentation() == false)
    }

    @Test
    func lateDecisionAfterAbandonmentIsDiscarded() {
        let handoff = ApprovalHandoff()

        #expect(handoff.wait(timeout: 0.05) == .deny)
        handoff.finish(.alwaysAllow)

        // A decision that arrives after the request was already answered must not be
        // observable, otherwise a stale approval could authorize a later request.
        #expect(handoff.wait(timeout: 0.05) == .deny)
    }
}

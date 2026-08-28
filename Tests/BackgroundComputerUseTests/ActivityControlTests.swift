@testable import BackgroundComputerUse
@testable import BackgroundComputerUseControl
import BackgroundComputerUseControlShared
import Foundation
import Testing

@Suite(.serialized)
struct ActivityControlTests {
    @Test
    func newActivityReplacesPresentationFromAnotherWindow() throws {
        var presentation = ActivityPiPPresentationState()

        let firstCandidate = presentation.present(makeActivity(id: "one", windowID: "window-a"))
        let secondCandidate = presentation.present(makeActivity(id: "two", windowID: "window-b"))
        let firstGeneration = try #require(firstCandidate)
        let secondGeneration = try #require(secondCandidate)

        #expect(firstGeneration == 1)
        #expect(secondGeneration == 2)
        #expect(presentation.activity?.id == "two")
        #expect(presentation.activity?.windowID == "window-b")
    }

    @Test
    func staleDismissalCannotHideNewerActivity() throws {
        var presentation = ActivityPiPPresentationState()
        let staleCandidate = presentation.present(makeActivity(id: "one", windowID: "window-a"))
        let currentCandidate = presentation.present(makeActivity(id: "two", windowID: "window-b"))
        let staleGeneration = try #require(staleCandidate)
        let currentGeneration = try #require(currentCandidate)

        let staleDismissed = presentation.dismiss(generation: staleGeneration)
        #expect(staleDismissed == false)
        #expect(presentation.activity?.id == "two")
        let currentDismissed = presentation.dismiss(generation: currentGeneration)
        #expect(currentDismissed)
        #expect(presentation.activity == nil)
    }

    @Test
    func disabledPresentationClearsAndBlocksUntilReenabled() throws {
        var presentation = ActivityPiPPresentationState()
        let staleCandidate = presentation.present(makeActivity(id: "one", windowID: "window-a"))
        let staleGeneration = try #require(staleCandidate)

        presentation.setEnabled(false)

        #expect(presentation.activity == nil)
        #expect(presentation.dismiss(generation: staleGeneration) == false)
        let blockedCandidate = presentation.present(makeActivity(id: "blocked", windowID: "window-b"))
        #expect(blockedCandidate == nil)

        presentation.setEnabled(true)
        let resumedCandidate = presentation.present(makeActivity(id: "resumed", windowID: "window-c"))
        let resumedGeneration = try #require(resumedCandidate)
        #expect(resumedGeneration > staleGeneration)
        #expect(presentation.activity?.id == "resumed")
    }

    @Test
    func pauseBlocksMutationsButKeepsReadsAvailable() {
        let controls = SessionControls()
        #expect(controls.allows(.mutation))
        controls.pause()
        #expect(controls.allows(.mutation) == false)
        #expect(controls.allows(.read))
        controls.resume()
        #expect(controls.allows(.mutation))
    }

    @Test
    func sessionControlsPublishEveryEffectiveStateTransition() {
        var transitions: [SessionControlState] = []
        let controls = SessionControls(onStateChange: { transitions.append($0) })
        controls.pause()
        controls.pause()
        controls.resume()
        controls.stop()
        controls.resume()

        #expect(transitions == [.paused, .active, .stopped])
    }

    @Test
    func stopIsPermanentAndRevokesExternalLeases() {
        var revocations = 0
        let controls = SessionControls(onStop: { revocations += 1 })
        controls.stop()
        controls.resume()

        #expect(controls.state == .stopped)
        #expect(controls.allows(.read) == false)
        #expect(revocations == 1)
    }

    @Test
    func historyIsNewestFirstPerWindowAndStoresNoRequestPayload() throws {
        let history = ActivityHistoryStore(capacity: 3)
        history.append(ActivityEnvelope(
            id: "one",
            sessionID: "session",
            appBundleID: "com.example.App",
            windowID: "window-a",
            action: "type_text",
            verdict: "success",
            summary: "Text verified",
            screenshotPath: nil,
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        history.append(ActivityEnvelope(
            id: "two",
            sessionID: "session",
            appBundleID: "com.example.App",
            windowID: "window-a",
            action: "click",
            verdict: "success",
            summary: "Click verified",
            screenshotPath: nil,
            timestamp: Date(timeIntervalSince1970: 2)
        ))

        #expect(history.activities(windowID: "window-a").map(\.id) == ["two", "one"])
        let fieldNames = try Mirror(reflecting: #require(history.activities().first)).children.compactMap(\.label)
        #expect(fieldNames.contains("requestPayload") == false)
        #expect(fieldNames.contains("responsePayload") == false)
    }

    @Test
    func latestWindowScreenshotIsReplacedByNewerActivity() {
        let history = ActivityHistoryStore(capacity: 3)
        history.append(ActivityEnvelope(
            id: "one",
            sessionID: "session",
            appBundleID: "com.example.App",
            windowID: "window-a",
            action: "click",
            verdict: "success",
            summary: "first",
            screenshotPath: "/tmp/first.png",
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        history.append(ActivityEnvelope(
            id: "two",
            sessionID: "session",
            appBundleID: "com.example.App",
            windowID: "window-a",
            action: "click",
            verdict: "success",
            summary: "second",
            screenshotPath: "/tmp/second.png",
            timestamp: Date(timeIntervalSince1970: 2)
        ))

        #expect(history.latestScreenshotPath(windowID: "window-a") == "/tmp/second.png")
    }

    @Test
    func synchronousActivityPublicationFitsUpdateBudget() {
        let history = ActivityHistoryStore(capacity: 10)
        let started = ContinuousClock.now
        history.append(ActivityEnvelope(
            id: "one",
            sessionID: "session",
            appBundleID: nil,
            windowID: nil,
            action: "click",
            verdict: "success",
            summary: "Verified",
            screenshotPath: nil,
            timestamp: Date()
        ))
        let elapsed = started.duration(to: .now)
        #expect(elapsed < .milliseconds(150))
    }

    @Test
    func pausedControlBlocksHTTPActionsButNotReads() throws {
        let router = Router(
            auth: .disabled,
            controlPolicy: RouterControlPolicy(
                readAllowed: { true },
                mutationAllowed: { false },
                arbitraryScriptAllowed: { false },
                authorizeWindow: { _, _ in .deny }
            )
        )
        let action = try makeControlRequest(path: "/v1/click")
        let read = try makeControlRequest(path: "/v1/list_apps")

        #expect(router.response(for: action, context: RouterContext(baseURL: nil, startedAt: nil)).statusCode == 423)
        #expect(router.response(for: read, context: RouterContext(baseURL: nil, startedAt: nil)).statusCode == 200)
    }

    @Test
    func stoppedControlBlocksReadAndMutationRoutes() throws {
        let router = Router(
            auth: .disabled,
            controlPolicy: RouterControlPolicy(
                readAllowed: { false },
                mutationAllowed: { false },
                arbitraryScriptAllowed: { false },
                authorizeWindow: { _, _ in .deny }
            )
        )
        let read = try makeControlRequest(path: "/v1/list_apps")
        #expect(router.response(for: read, context: RouterContext(baseURL: nil, startedAt: nil)).statusCode == 423)
    }

    @Test
    func connectedControlBlocksArbitraryScriptPolicyBypass() throws {
        let router = Router(
            auth: .disabled,
            controlPolicy: RouterControlPolicy(
                readAllowed: { true },
                mutationAllowed: { true },
                arbitraryScriptAllowed: { false },
                authorizeWindow: { _, _ in .deny }
            )
        )
        let request = try makeControlRequest(path: "/v1/run_script")
        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        #expect(response.statusCode == 403)
        let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(payload["error"] as? String == "control_policy_required")
    }

    @Test
    func signedServerFailsClosedWhenControlIsUnavailable() throws {
        BackgroundComputerUseControlBridge.disconnect()
        let router = Router(auth: .disabled, controlRequired: true)
        let read = try makeControlRequest(path: "/v1/list_apps")

        let response = router.response(
            for: read,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 423)
    }
}

private func makeActivity(id: String, windowID: String) -> ActivityEnvelope {
    ActivityEnvelope(
        id: id,
        sessionID: "session",
        appBundleID: "com.example.App",
        windowID: windowID,
        action: "click",
        verdict: "success",
        summary: "Verified",
        screenshotPath: nil,
        timestamp: Date(timeIntervalSince1970: 1)
    )
}

private func makeControlRequest(path: String) throws -> HTTPRequest {
    let raw = "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
    guard case let .complete(request) = HTTPRequest.parse(Data(raw.utf8)) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return request
}

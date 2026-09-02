import Dispatch
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite("Recorded AX route regressions")
struct RecordedAXRouteRegressionTests {
    private let fixtureNames = [
        "electron-deep-tree",
        "electron-window-chrome-flap-a",
        "electron-window-chrome-flap-b",
        "finder-window",
        "safari-textarea",
        "system-settings",
        "textedit-document",
    ]

    @Test
    func everyFixtureReplaysOnNetworkWorkerStack() throws {
        for name in fixtureNames {
            let fixture = try loadFixture(named: name)
            let envelope = try replayOnSmallStack(fixture)

            #expect(envelope.response.tree.truncated == fixture.rawCapture.truncated)
            for node in envelope.response.tree.nodes where node.displayRole == "text entry area" {
                #expect(node.nodeID?.isEmpty == false)
            }
        }
    }

    @Test
    func consecutiveElectronCapturesKeepInteractionIdentity() throws {
        let first = try replayOnSmallStack(loadFixture(named: "electron-window-chrome-flap-a"))
        let second = try replayOnSmallStack(loadFixture(named: "electron-window-chrome-flap-b"))

        #expect(first.response.interactionToken == second.response.interactionToken)
    }

    @Test(arguments: ["electron-deep-tree", "safari-textarea"])
    func findElementsMatchesRecordedTextEntry(fixtureName: String) throws {
        let fixture = try loadFixture(named: fixtureName)
        let response = try replayOnSmallStack(fixture).response
        let state = routeState(from: response)
        let request = FindElementsRequest(
            window: fixture.window.windowID,
            role: "text entry area",
            text: AXFixtureSanitizer.placeholder
        )

        let result = try FindElementsRouteService.response(from: state, request: request)

        #expect(result.matches.isEmpty == false)
        #expect(result.matches.allSatisfy { $0.nodeID?.isEmpty == false })
    }

    private func loadFixture(named name: String) throws -> StatePipelineFixture {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/AX"
        ))
        return try StatePipelineExperiment().loadFixture(at: url.path)
    }

    private func replayOnSmallStack(_ fixture: StatePipelineFixture) throws -> StatePipelineEnvelope {
        let finished = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var envelope: StatePipelineEnvelope?
        let thread = Thread {
            envelope = StatePipelineExperiment().replayFixture(fixture, imageMode: .omit)
            finished.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        finished.wait()
        return try #require(envelope)
    }

    private func routeState(from response: AXPipelineV2Response) -> GetWindowStateResponse {
        GetWindowStateResponse(
            contractVersion: response.contractVersion,
            stateToken: response.stateToken,
            interactionToken: response.interactionToken,
            window: response.window,
            attachedSurfaces: response.attachedSurfaces,
            screenshot: response.screenshot,
            tree: response.tree,
            menuPresentation: response.menuPresentation,
            focusedElement: response.focusedElement,
            selectionSummary: response.selectionSummary,
            backgroundSafety: response.backgroundSafety,
            performance: ReadPerformanceDTO(
                resolveMs: 0,
                captureMs: 0,
                projectionMs: 0,
                screenshotMs: 0,
                totalMs: 0
            ),
            debug: nil,
            ocr: nil,
            notes: response.notes
        )
    }
}

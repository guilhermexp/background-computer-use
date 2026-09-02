import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite("Recorded AX action orchestration")
struct RecordedAXActionOrchestrationTests {
    @Test
    func delayedElectronCommitRereadsTwiceWithoutRedispatch() throws {
        let fixture = try loadFixture(named: "electron-deep-tree")
        let baselineCapture = replayedCapture(of: fixture)
        let target = try #require(
            baselineCapture.envelope.response.tree.nodes.first { $0.displayRole == "text entry area" }
        )
        let expectedText = "delayed-commit"
        let committedFixture = try replacingValue(
            in: fixture,
            canonicalIndex: target.primaryCanonicalIndex,
            with: expectedText
        )
        let committedCapture = replayedCapture(of: committedFixture)
        let provider = ScriptedStateProvider(
            initial: baselineCapture,
            rereads: [baselineCapture, committedCapture]
        )
        let foreground = ForegroundApplicationSnapshot(pid: 999, bundleID: "com.example.user")
        let dispatchCounter = Counter()
        let baselineState = TypeTextObservedStateDTO(
            valuePreview: "",
            valueString: "",
            length: 0,
            truncated: false,
            selectedTextRange: TypeTextSelectionRangeDTO(location: 0, length: 0),
            isFocused: true
        )
        let committedState = TypeTextObservedStateDTO(
            valuePreview: expectedText,
            valueString: expectedText,
            length: expectedText.utf16.count,
            truncated: false,
            selectedTextRange: TypeTextSelectionRangeDTO(
                location: expectedText.utf16.count,
                length: 0
            ),
            isFocused: true
        )
        let runtime = TypeTextActionRuntime(
            readTextState: { _ in
                provider.rereadCount >= 2 ? committedState : baselineState
            },
            dispatchText: { _ in
                dispatchCounter.increment()
                return TextDispatchResult(
                    succeeded: true,
                    primitive: "fixture_transport",
                    strategiesAttempted: [.axValue],
                    fallbackReason: nil,
                    foregroundFallbackUsed: false,
                    foregroundBeforeDispatch: foreground,
                    preparationMs: 0
                )
            }
        )
        let resolver = AXActionTargetResolver(
            executionOptions: .visualCursorDisabled,
            stateProvider: provider
        )
        let service = TypeTextRouteService(
            executionOptions: .visualCursorDisabled,
            foregroundApplication: { foreground },
            targetResolver: resolver,
            actionRuntime: runtime
        )
        let targetNodeID = try #require(target.nodeID)
        let response = try service.typeText(request: TypeTextRequest(
            window: fixture.window.windowID,
            target: .nodeID(targetNodeID),
            text: expectedText,
            includeMenuBar: false,
            maxNodes: 6500
        ))

        #expect(dispatchCounter.value == 1)
        #expect(response.strategiesAttempted == [AdaptiveTextStrategy.axValue.rawValue])
        #expect(response.strategiesAttempted.contains(AdaptiveTextStrategy.pidUnicode.rawValue) == false)
        #expect(provider.rereadCount == 2)
        #expect(response.classification == .success)
    }

    private func loadFixture(named name: String) throws -> StatePipelineFixture {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/AX"
        ))
        return try StatePipelineExperiment().loadFixture(at: url.path)
    }

    private func replacingValue(
        in fixture: StatePipelineFixture,
        canonicalIndex: Int,
        with text: String
    ) throws -> StatePipelineFixture {
        let data = try JSONSupport.encoder.encode(fixture)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rawCapture = try #require(object["rawCapture"] as? [String: Any])
        var nodes = try #require(rawCapture["nodes"] as? [[String: Any]])
        var node = nodes[canonicalIndex]
        node["value"] = [
            "kind": "string",
            "preview": text,
            "length": text.count,
            "truncated": false,
        ]
        nodes[canonicalIndex] = node
        rawCapture["nodes"] = nodes
        object["rawCapture"] = rawCapture
        return try JSONSupport.decoder.decode(
            StatePipelineFixture.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func replayedCapture(of fixture: StatePipelineFixture) -> AXActionStateCapture {
        let envelope = StatePipelineExperiment().replayFixture(fixture, imageMode: .omit)
        let window = envelope.response.window
        let element = AXUIElementCreateApplication(getpid())
        let frame = window.frameAppKit
        let resolved = ResolvedWindowTarget(
            windowID: window.windowID,
            bundleID: window.bundleID,
            launchDate: nil,
            app: NSRunningApplication.current,
            appElement: element,
            window: AXWindowRecord(
                element: element,
                windowNumber: window.windowNumber,
                title: window.title,
                role: "AXWindow",
                subrole: nil,
                frameAppKit: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                isFocused: false,
                isMain: false,
                isMinimized: false,
                isOnScreen: false
            ),
            resolutionStrategy: "recorded-fixture",
            notes: []
        )
        return AXActionStateCapture(
            windowID: window.windowID,
            includeMenuBar: false,
            includeCursorOverlay: false,
            menuPathComponents: [],
            webTraversal: .visible,
            maxNodes: 6500,
            resolved: resolved,
            envelope: envelope,
            liveElementsByCanonicalIndex: Dictionary(
                uniqueKeysWithValues: envelope.rawCapture.nodes.indices.map { ($0, element) }
            ),
            displayIndexByProjectedIndex: Dictionary(
                uniqueKeysWithValues: envelope.response.tree.lineMappings.map {
                    ($0.projectedIndex, $0.displayIndex)
                }
            )
        )
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

private final class ScriptedStateProvider: AXActionStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let initial: AXActionStateCapture
    private var rereads: [AXActionStateCapture]
    private var storedRereadCount = 0

    init(initial: AXActionStateCapture, rereads: [AXActionStateCapture]) {
        self.initial = initial
        self.rereads = rereads
    }

    var rereadCount: Int {
        lock.withLock { storedRereadCount }
    }

    func capture(
        windowID _: String,
        includeMenuBar _: Bool,
        menuPathComponents _: [String],
        webTraversal _: AXWebTraversalMode,
        maxNodes _: Int,
        imageMode _: ImageMode,
        includeCursorOverlay _: Bool?
    ) throws -> AXActionStateCapture {
        initial
    }

    func reread(
        after _: AXActionStateCapture,
        imageMode _: ImageMode
    ) throws -> AXActionStateCapture {
        lock.withLock {
            storedRereadCount += 1
            return rereads.isEmpty ? initial : rereads.removeFirst()
        }
    }
}

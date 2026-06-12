import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct RuntimeEnhancementTests {
    @Test
    func safetyPolicyRequiresConfirmationForDestructiveLabels() throws {
        let decision = RuntimeSafetyPolicy.evaluateLabel("Delete deployment", confirmed: false)

        #expect(decision.blocked)
        #expect(decision.reason?.contains("Delete deployment") == true)
        #expect(!RuntimeSafetyPolicy.evaluateLabel("Delete deployment", confirmed: true).blocked)
        #expect(!RuntimeSafetyPolicy.evaluateLabel("View logs", confirmed: false).blocked)
    }

    @Test
    func safetyPolicyRequiresConfirmationBeforeClearingExistingValues() {
        let decision = RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "existing",
            newValue: "",
            confirmed: false
        )

        #expect(decision.blocked)
        #expect(!RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "existing",
            newValue: "",
            confirmed: true
        ).blocked)
        #expect(!RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "",
            newValue: "",
            confirmed: false
        ).blocked)
    }

    @Test
    func waitConditionMatchesRoleLabelAndValue() {
        let node = WaitForMatcherNode(
            role: "button",
            title: "Deploy",
            description: nil,
            valuePreview: nil
        )

        #expect(WaitForMatcher.matches(
            node,
            role: "button",
            label: "dep",
            valueContains: nil
        ))
        #expect(!WaitForMatcher.matches(
            node,
            role: "text field",
            label: "dep",
            valueContains: nil
        ))
    }

    @Test
    func textChunkerReportsBoundedSlices() throws {
        let chunk = try TextChunker.chunk("abcdef", offset: 2, length: 3)

        #expect(chunk.text == "cde")
        #expect(chunk.totalLength == 6)
        #expect(chunk.rangeStart == 2)
        #expect(chunk.rangeEnd == 5)
        #expect(chunk.truncated)
    }

    @Test
    func textSelectionPlannerFindsRequestedOccurrence() throws {
        let range = try TextSelectionPlanner.range(
            in: "alpha beta alpha",
            query: "alpha",
            occurrence: 2,
            position: .select
        )

        #expect(range.location == 11)
        #expect(range.length == 5)
    }

    @Test
    func debugArtifactRecorderWritesRequestAndResponseMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-debug-artifact-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = DebugArtifactRecorder(
            rootDirectory: directory,
            enabled: true
        )
        let artifact = try recorder.record(
            requestID: "req-1",
            routeID: "click",
            requestBody: Data(#"{"window":"w1"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )

        #expect(FileManager.default.fileExists(atPath: artifact.requestPath.path))
        #expect(FileManager.default.fileExists(atPath: artifact.responsePath.path))
    }

    @Test
    func ocrAnchorSummaryKeepsHighConfidenceUsefulAnchors() {
        let summary = OCRAnchorSummaryBuilder.summary(
            lines: [
                .init(text: "Deploy", confidence: 0.97, box: .init(x: 10, y: 20, width: 60, height: 20)),
                .init(text: "x", confidence: 0.99, box: .init(x: 1, y: 1, width: 5, height: 5)),
                .init(text: "Logs", confidence: 0.93, box: .init(x: 90, y: 20, width: 40, height: 20)),
            ],
            maxAnchors: 2
        )

        #expect(summary?.anchors.map(\.text) == ["Deploy", "Logs"])
        #expect(summary?.promptHint.contains(#""Deploy" at (40, 30)"#) == true)
    }

    @Test
    func sessionLimiterRejectsConcurrentSessionAndThrottlesRapidCalls() {
        let limiter = RuntimeSessionLimiter()

        #expect(limiter.acquire(sessionID: "a", now: 0).allowed)
        #expect(!limiter.acquire(sessionID: "b", now: 0.1).allowed)
        limiter.release(sessionID: "a")
        #expect(limiter.acquire(sessionID: "b", now: 0.2).allowed)

        limiter.configure(maxActionsPerSecond: 1)
        #expect(limiter.beforeAction(now: 1.0).allowed)
        #expect(!limiter.beforeAction(now: 1.1).allowed)
        #expect(limiter.beforeAction(now: 2.1).allowed)
    }

    @Test
    func routeRegistryDocumentsNewRoutes() {
        let ids = Set(RouteRegistry.publicRoutes().map(\.id))

        #expect(ids.contains(RouteID.waitFor.rawValue))
        #expect(ids.contains(RouteID.readText.rawValue))
        #expect(ids.contains(RouteID.selectText.rawValue))
    }
}

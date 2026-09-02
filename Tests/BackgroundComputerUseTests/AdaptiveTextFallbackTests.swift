@testable import BackgroundComputerUse
import Testing

struct AdaptiveTextFallbackTests {
    @Test
    func unchangedIgnoredAXWriteFallsBackOnce() {
        #expect(
            AdaptiveTextFallback.decide(
                baseline: "",
                expected: "hello",
                observed: "",
                axStatus: .success,
                fallbackEligible: true
            ) == .fallbackUnicode
        )
    }

    @Test
    func partialAXWriteNeverFallsBack() {
        #expect(
            AdaptiveTextFallback.decide(
                baseline: "",
                expected: "hello",
                observed: "hel",
                axStatus: .success,
                fallbackEligible: true
            ) == .failClosed(reason: .partialMutation)
        )
    }

    @Test
    func exactAXWriteNeedsNoFallback() {
        #expect(
            AdaptiveTextFallback.decide(
                baseline: "",
                expected: "hello",
                observed: "hello",
                axStatus: .success,
                fallbackEligible: true
            ) == .acceptAX
        )
    }

    @Test
    func missingCompleteValueEvidenceFailsClosed() {
        #expect(
            AdaptiveTextFallback.decide(
                baseline: "",
                expected: "hello",
                observed: nil,
                axStatus: .success,
                fallbackEligible: true
            ) == .failClosed(reason: .missingEvidence)
        )
    }

    @Test
    func unchangedValueWithoutFallbackEligibilityFailsClosed() {
        #expect(
            AdaptiveTextFallback.decide(
                baseline: "",
                expected: "hello",
                observed: "",
                axStatus: .failure,
                fallbackEligible: false
            ) == .failClosed(reason: .fallbackNotEligible)
        )
    }

    @Test
    func acceptedAXWriteWaitsForAsyncRendererBeforeEscalating() {
        // Chromium/Electron answer AX reads from a browser-side cache that lags the renderer's
        // handling of an AXValue set. The first reads still show the baseline.
        nonisolated(unsafe) var reads = ["old", "old", "old", "new"]
        nonisolated(unsafe) var unicodePosted = false
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "old",
            expected: "new",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { reads.isEmpty ? "new" : reads.removeFirst() },
            settle: AdaptiveTextSettle(maxReads: 10, wait: {}),
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: { unicodePosted = true; return true }
        )
        #expect(result.decision == .acceptAX)
        #expect(result.strategiesAttempted == [.axValue])
        #expect(result.fallbackReason == nil)
        #expect(unicodePosted == false)
    }

    @Test
    func acceptedAXWriteThatNeverLandsStillFallsBackOnce() {
        nonisolated(unsafe) var readCount = 0
        nonisolated(unsafe) var unicodePosted = false
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "old",
            expected: "new",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { readCount += 1; return unicodePosted ? "new" : "old" },
            settle: AdaptiveTextSettle(maxReads: 5, wait: {}),
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: { unicodePosted = true; return true }
        )
        #expect(result.strategiesAttempted == [.axValue, .pidUnicode])
        #expect(result.fallbackReason == .unchangedAXNoOp)
        #expect(readCount >= 5)
    }

    @Test
    func rejectedAXWriteDoesNotWaitForSettle() {
        nonisolated(unsafe) var readCount = 0
        _ = AdaptiveTextDispatcher.dispatch(
            baseline: "old",
            expected: "new",
            fallbackEligible: true,
            writeAX: { .failure },
            readValue: { readCount += 1; return "old" },
            settle: AdaptiveTextSettle(maxReads: 10, wait: {}),
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { false },
            postUnicode: { true }
        )
        #expect(readCount == 1)
    }
}

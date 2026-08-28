@testable import BackgroundComputerUse
import Testing

struct AdaptiveTypeTextRouteTests {
    @Test
    func ignoredAXWriteUsesOneUnicodeFallback() {
        var trace: [String] = []
        var observedValues = ["", "", "hello"]

        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: {
                trace.append("ax_write")
                return .success
            },
            readValue: {
                trace.append("reread")
                return observedValues.removeFirst()
            },
            performTargetBoundFallback: {
                trace.append("target_bound")
                return .unavailable
            },
            prepareUnicodeFallback: {
                trace.append("prepare")
                return true
            },
            postUnicode: {
                trace.append("unicode")
                return true
            }
        )

        #expect(trace == ["ax_write", "reread", "target_bound", "prepare", "reread", "unicode", "reread"])
        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axValue, .pidUnicode])
        #expect(result.fallbackReason == .unchangedAXNoOp)
        #expect(result.finalObservedValue == "hello")
    }

    @Test
    func partialAXMutationNeverPostsUnicode() {
        var unicodeCalls = 0
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { "hel" },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { false },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(result.strategiesAttempted == [.axValue])
        #expect(result.decision == .failClosed(reason: .partialMutation))
    }

    @Test
    func exactAXMutationStaysOnFastPath() {
        var unicodeCalls = 0
        var unicodePreparationCalls = 0
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { "hello" },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: {
                unicodePreparationCalls += 1
                return false
            },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(unicodePreparationCalls == 0)
        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axValue])
        #expect(result.decision == .acceptAX)
    }

    @Test
    func unicodeFallbackPostsAtMostOnce() {
        var unicodeCalls = 0
        var observedValues = ["", "", "hello"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 1)
        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axValue, .pidUnicode])
    }

    @Test
    func failedUnicodeTransportIsReported() {
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { "" },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: { false }
        )

        #expect(result.transportSucceeded == false)
        #expect(result.strategiesAttempted == [.axValue, .pidUnicode])
        #expect(result.finalObservedValue == nil)
    }

    @Test
    func failedFallbackPreparationPreservesBaselineAndBlocksUnicode() {
        var unicodeCalls = 0
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { "" },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { false },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(result.transportSucceeded == false)
        #expect(result.strategiesAttempted == [.axValue])
        #expect(result.finalObservedValue == "")
    }

    @Test
    func targetBoundTextOperationCanCompleteBeforeUnicodeFallback() {
        var unicodeCalls = 0
        var unicodePreparationCalls = 0
        var observedValues = ["", "hello"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .attempted(succeeded: true) },
            prepareUnicodeFallback: {
                unicodePreparationCalls += 1
                return false
            },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(unicodePreparationCalls == 0)
        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axValue, .axTextOperation])
        #expect(result.finalObservedValue == "hello")
    }

    @Test
    func targetBoundPartialMutationFailsBeforeUnicodePreparation() {
        var unicodePreparationCalls = 0
        var observedValues = ["", "hel"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .attempted(succeeded: true) },
            prepareUnicodeFallback: {
                unicodePreparationCalls += 1
                return true
            },
            postUnicode: { true }
        )

        #expect(unicodePreparationCalls == 0)
        #expect(result.decision == .failClosed(reason: .partialMutation))
        #expect(result.strategiesAttempted == [.axValue, .axTextOperation])
    }

    @Test
    func failedTargetBoundAttemptRemainsVisibleBeforeUnicode() {
        var observedValues = ["", "", "", "hello"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .attempted(succeeded: false) },
            prepareUnicodeFallback: { true },
            postUnicode: { true }
        )

        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axValue, .axTextOperation, .pidUnicode])
        #expect(result.finalObservedValue == "hello")
    }

    @Test
    func focusInducedPartialMutationBlocksUnicode() {
        var unicodeCalls = 0
        var observedValues = ["", "hel"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(result.decision == .failClosed(reason: .partialMutation))
        #expect(result.finalObservedValue == "hel")
    }

    @Test
    func focusInducedExactValueSkipsUnicode() {
        var unicodeCalls = 0
        var observedValues = ["", "hello"]
        let result = AdaptiveTextDispatcher.dispatch(
            baseline: "",
            expected: "hello",
            fallbackEligible: true,
            writeAX: { .success },
            readValue: { observedValues.removeFirst() },
            performTargetBoundFallback: { .unavailable },
            prepareUnicodeFallback: { true },
            postUnicode: {
                unicodeCalls += 1
                return true
            }
        )

        #expect(unicodeCalls == 0)
        #expect(result.transportSucceeded)
        #expect(result.decision == .acceptAX)
        #expect(result.finalObservedValue == "hello")
    }
}

@testable import BackgroundComputerUse
import Testing

struct AdaptivePasteDispatcherTests {
    @Test
    func exactTargetBoundOperationSkipsClipboard() {
        var clipboardCalls = 0
        var observed = ["Paste ok"]

        let result = AdaptivePasteDispatcher.dispatch(
            baseline: "",
            expected: "Paste ok",
            targetBoundEligible: true,
            performTargetBoundOperation: { true },
            readValue: { observed.removeFirst() },
            performClipboardPaste: {
                clipboardCalls += 1
                return true
            }
        )

        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axTextOperation])
        #expect(result.observedValue == "Paste ok")
        #expect(clipboardCalls == 0)
    }

    @Test
    func ignoredTargetBoundOperationFallsBackToClipboardOnce() {
        var clipboardCalls = 0

        let result = AdaptivePasteDispatcher.dispatch(
            baseline: "",
            expected: "Paste ok",
            targetBoundEligible: true,
            performTargetBoundOperation: { true },
            readValue: { "" },
            performClipboardPaste: {
                clipboardCalls += 1
                return true
            }
        )

        #expect(result.transportSucceeded)
        #expect(result.strategiesAttempted == [.axTextOperation, .temporaryClipboardCommandV])
        #expect(clipboardCalls == 1)
    }

    @Test
    func partialTargetBoundMutationFailsClosedWithoutClipboard() {
        var clipboardCalls = 0

        let result = AdaptivePasteDispatcher.dispatch(
            baseline: "",
            expected: "Paste ok",
            targetBoundEligible: true,
            performTargetBoundOperation: { true },
            readValue: { "Paste" },
            performClipboardPaste: {
                clipboardCalls += 1
                return true
            }
        )

        #expect(result.transportSucceeded == false)
        #expect(result.strategiesAttempted == [.axTextOperation])
        #expect(clipboardCalls == 0)
    }
}

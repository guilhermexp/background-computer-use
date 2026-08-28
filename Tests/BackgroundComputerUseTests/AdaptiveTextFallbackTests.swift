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
}

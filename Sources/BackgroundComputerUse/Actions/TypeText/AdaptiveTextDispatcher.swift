import Foundation

enum AdaptiveTextStrategy: String, Codable, Equatable, Sendable {
    case axValue = "ax_value"
    case axTextOperation = "ax_text_operation"
    case pidUnicode = "pid_unicode"
}

enum AdaptiveTextDispatchFallbackReason: String, Codable, Equatable, Sendable {
    case unchangedAXNoOp = "unchanged_ax_noop"
}

enum AdaptiveTextTargetBoundAttempt: Equatable, Sendable {
    case unavailable
    case attempted(succeeded: Bool)

    var strategies: [AdaptiveTextStrategy] {
        self == .unavailable ? [] : [.axTextOperation]
    }

    var wasAttempted: Bool {
        self != .unavailable
    }

    var transportSucceeded: Bool {
        self == .attempted(succeeded: true)
    }
}

struct AdaptiveTextDispatchResult: Equatable, Sendable {
    let transportSucceeded: Bool
    let strategiesAttempted: [AdaptiveTextStrategy]
    let fallbackReason: AdaptiveTextDispatchFallbackReason?
    let decision: AdaptiveTextFallbackDecision
    let immediateObservedValue: String?
    let finalObservedValue: String?
}

enum AdaptiveTextDispatcher {
    static func dispatch(
        baseline: String?,
        expected: String?,
        fallbackEligible: Bool,
        writeAX: () -> AdaptiveTextAXStatus,
        readValue: () -> String?,
        performTargetBoundFallback: () -> AdaptiveTextTargetBoundAttempt,
        prepareUnicodeFallback: () -> Bool,
        postUnicode: () -> Bool
    ) -> AdaptiveTextDispatchResult {
        let axStatus = writeAX()
        let immediateObservedValue = readValue()
        let decision = AdaptiveTextFallback.decide(
            baseline: baseline,
            expected: expected,
            observed: immediateObservedValue,
            axStatus: axStatus,
            fallbackEligible: fallbackEligible
        )

        switch decision {
        case .acceptAX:
            return AdaptiveTextDispatchResult(
                transportSucceeded: true,
                strategiesAttempted: [.axValue],
                fallbackReason: nil,
                decision: decision,
                immediateObservedValue: immediateObservedValue,
                finalObservedValue: immediateObservedValue
            )

        case .fallbackUnicode:
            let targetBoundAttempt = performTargetBoundFallback()
            let strategies = [.axValue] + targetBoundAttempt.strategies
            let selectedTextObservedValue = targetBoundAttempt.wasAttempted
                ? readValue()
                : immediateObservedValue
            let selectedTextDecision = AdaptiveTextFallback.decide(
                baseline: baseline,
                expected: expected,
                observed: selectedTextObservedValue,
                axStatus: .success,
                fallbackEligible: true
            )
            switch selectedTextDecision {
            case .acceptAX:
                return AdaptiveTextDispatchResult(
                    transportSucceeded: true,
                    strategiesAttempted: strategies,
                    fallbackReason: .unchangedAXNoOp,
                    decision: selectedTextDecision,
                    immediateObservedValue: immediateObservedValue,
                    finalObservedValue: selectedTextObservedValue
                )
            case .failClosed:
                return AdaptiveTextDispatchResult(
                    transportSucceeded: targetBoundAttempt.transportSucceeded,
                    strategiesAttempted: strategies,
                    fallbackReason: .unchangedAXNoOp,
                    decision: selectedTextDecision,
                    immediateObservedValue: immediateObservedValue,
                    finalObservedValue: selectedTextObservedValue
                )
            case .fallbackUnicode:
                break
            }
            guard prepareUnicodeFallback() else {
                return AdaptiveTextDispatchResult(
                    transportSucceeded: targetBoundAttempt.transportSucceeded,
                    strategiesAttempted: strategies,
                    fallbackReason: .unchangedAXNoOp,
                    decision: decision,
                    immediateObservedValue: immediateObservedValue,
                    finalObservedValue: selectedTextObservedValue
                )
            }
            let preparedUnicodeObservedValue = readValue()
            let preparedUnicodeDecision = AdaptiveTextFallback.decide(
                baseline: baseline,
                expected: expected,
                observed: preparedUnicodeObservedValue,
                axStatus: .success,
                fallbackEligible: true
            )
            switch preparedUnicodeDecision {
            case .acceptAX:
                return AdaptiveTextDispatchResult(
                    transportSucceeded: axStatus == .success || targetBoundAttempt.transportSucceeded,
                    strategiesAttempted: strategies,
                    fallbackReason: .unchangedAXNoOp,
                    decision: preparedUnicodeDecision,
                    immediateObservedValue: immediateObservedValue,
                    finalObservedValue: preparedUnicodeObservedValue
                )
            case .failClosed:
                return AdaptiveTextDispatchResult(
                    transportSucceeded: axStatus == .success || targetBoundAttempt.transportSucceeded,
                    strategiesAttempted: strategies,
                    fallbackReason: .unchangedAXNoOp,
                    decision: preparedUnicodeDecision,
                    immediateObservedValue: immediateObservedValue,
                    finalObservedValue: preparedUnicodeObservedValue
                )
            case .fallbackUnicode:
                break
            }
            let unicodeSucceeded = postUnicode()
            let finalObservedValue = unicodeSucceeded ? readValue() : nil
            return AdaptiveTextDispatchResult(
                transportSucceeded: targetBoundAttempt.transportSucceeded || unicodeSucceeded,
                strategiesAttempted: strategies + [.pidUnicode],
                fallbackReason: .unchangedAXNoOp,
                decision: decision,
                immediateObservedValue: immediateObservedValue,
                finalObservedValue: finalObservedValue
            )

        case .failClosed:
            return AdaptiveTextDispatchResult(
                transportSucceeded: axStatus == .success,
                strategiesAttempted: [.axValue],
                fallbackReason: nil,
                decision: decision,
                immediateObservedValue: immediateObservedValue,
                finalObservedValue: immediateObservedValue
            )
        }
    }
}

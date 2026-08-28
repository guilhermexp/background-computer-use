import Foundation

enum AdaptiveTextAXStatus: Equatable, Sendable {
    case success
    case failure
}

enum AdaptiveTextFallbackFailureReason: Equatable, Sendable {
    case missingEvidence
    case partialMutation
    case fallbackNotEligible
}

enum AdaptiveTextFallbackDecision: Equatable, Sendable {
    case acceptAX
    case fallbackUnicode
    case failClosed(reason: AdaptiveTextFallbackFailureReason)
}

enum AdaptiveTextFallback {
    static func decide(
        baseline: String?,
        expected: String?,
        observed: String?,
        axStatus _: AdaptiveTextAXStatus,
        fallbackEligible: Bool
    ) -> AdaptiveTextFallbackDecision {
        guard let baseline, let expected, let observed else {
            return .failClosed(reason: .missingEvidence)
        }
        if observed == expected {
            return .acceptAX
        }
        guard observed == baseline else {
            return .failClosed(reason: .partialMutation)
        }
        guard fallbackEligible else {
            return .failClosed(reason: .fallbackNotEligible)
        }
        return .fallbackUnicode
    }
}

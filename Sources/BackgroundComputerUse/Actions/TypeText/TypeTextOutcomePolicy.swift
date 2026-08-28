import Foundation

struct TypeTextOutcomeDecision: Sendable {
    let classification: ActionClassificationDTO
    let failureDomain: ActionFailureDomainDTO?
    let summary: String
}

enum TypeTextOutcomePolicy {
    static func canRestoreForeground(
        attempt: TypeTextAttemptTelemetry,
        verificationCompleted: Bool
    ) -> Bool {
        attempt.strategiesAttempted.isEmpty || verificationCompleted
    }

    static func classifyOpaqueDispatch(
        attempt: TypeTextAttemptTelemetry,
        foregroundPreserved _: Bool
    ) -> TypeTextOutcomeDecision {
        guard attempt.dispatchSucceeded == true else {
            return TypeTextOutcomeDecision(
                classification: .effectNotVerified,
                failureDomain: .transport,
                summary: "PID-scoped Unicode posting did not report success; reread before continuing and do not retry blindly."
            )
        }

        return TypeTextOutcomeDecision(
            classification: .verifierAmbiguous,
            failureDomain: .verification,
            summary: "Text was dispatched; reread before continuing and do not retry blindly."
        )
    }

    static func classifySemanticDispatch(
        exactValueMatch: Bool,
        exactSelectionMatch: Bool?,
        targetRelocated: Bool,
        postStateTokenAvailable: Bool,
        foregroundPreserved _: Bool
    ) -> TypeTextOutcomeDecision {
        if exactValueMatch {
            if exactSelectionMatch == false {
                return TypeTextOutcomeDecision(
                    classification: .effectNotVerified,
                    failureDomain: .verification,
                    summary: "The text inserted exactly, but the expected caret or selection state did not verify."
                )
            }

            return TypeTextOutcomeDecision(
                classification: .success,
                failureDomain: nil,
                summary: "The targeted text dispatch matched the expected inserted value after reread."
            )
        }

        if targetRelocated == false || postStateTokenAvailable == false {
            return TypeTextOutcomeDecision(
                classification: .verifierAmbiguous,
                failureDomain: .verification,
                summary: "The text dispatch was attempted, but the route could not confidently relocate the target on reread."
            )
        }

        return TypeTextOutcomeDecision(
            classification: .effectNotVerified,
            failureDomain: .verification,
            summary: "The text dispatch was attempted, but the refreshed target state did not match the expected inserted text."
        )
    }
}

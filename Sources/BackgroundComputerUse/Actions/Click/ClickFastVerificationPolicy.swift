import Foundation

enum ClickFastVerificationPolicy {
    static func canReuseCallerSample(
        suppliedStateToken: String?,
        liveStateToken: String
    ) -> Bool {
        guard let suppliedStateToken, suppliedStateToken.isEmpty == false else { return false }
        return suppliedStateToken == liveStateToken
    }

    static func requiresPixelEvidence(
        imageMode: ImageMode,
        projectionProfile: String?
    ) -> Bool {
        imageMode != .omit || projectionProfile != AXProjectionProfile.richWeb.rawValue
    }

    static func shouldContinueWaiting(
        preStateToken: String,
        postStateToken: String?,
        dispatchSucceeded: Bool
    ) -> Bool {
        dispatchSucceeded && postStateToken == preStateToken
    }

    static func postDispatchEvidenceChanged(
        baselineStateToken _: String,
        observedStateToken _: String?,
        targetRegionChangeRatio: Double?,
        targetRegionThreshold: Double
    ) -> Bool {
        guard let targetRegionChangeRatio, targetRegionChangeRatio.isFinite else { return false }
        return targetRegionChangeRatio >= targetRegionThreshold
    }
}

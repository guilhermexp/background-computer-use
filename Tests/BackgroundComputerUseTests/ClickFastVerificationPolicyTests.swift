@testable import BackgroundComputerUse
import Testing

struct ClickFastVerificationPolicyTests {
    @Test
    func matchingCallerTokenIsAStablePreDispatchSample() {
        #expect(ClickFastVerificationPolicy.canReuseCallerSample(
            suppliedStateToken: "state-1",
            liveStateToken: "state-1"
        ))
        #expect(ClickFastVerificationPolicy.canReuseCallerSample(
            suppliedStateToken: "state-0",
            liveStateToken: "state-1"
        ) == false)
    }

    @Test
    func semanticWebClickCanSkipPixelsWhenNoImageWasRequested() {
        #expect(ClickFastVerificationPolicy.requiresPixelEvidence(
            imageMode: .omit,
            projectionProfile: AXProjectionProfile.richWeb.rawValue
        ) == false)
        #expect(ClickFastVerificationPolicy.requiresPixelEvidence(
            imageMode: .path,
            projectionProfile: AXProjectionProfile.richWeb.rawValue
        ))
        #expect(ClickFastVerificationPolicy.requiresPixelEvidence(
            imageMode: .omit,
            projectionProfile: AXProjectionProfile.compactNative.rawValue
        ))
    }

    @Test
    func unchangedImmediateCaptureUsesBoundedWait() {
        #expect(ClickFastVerificationPolicy.shouldContinueWaiting(
            preStateToken: "same",
            postStateToken: "same",
            dispatchSucceeded: true
        ))
        #expect(ClickFastVerificationPolicy.shouldContinueWaiting(
            preStateToken: "before",
            postStateToken: "after",
            dispatchSucceeded: true
        ) == false)
    }

    @Test
    func coordinateWaitStopsOnlyForTargetLocalEvidence() {
        #expect(ClickFastVerificationPolicy.postDispatchEvidenceChanged(
            baselineStateToken: "before",
            observedStateToken: "after",
            targetRegionChangeRatio: nil,
            targetRegionThreshold: 0.02
        ) == false)
        #expect(ClickFastVerificationPolicy.postDispatchEvidenceChanged(
            baselineStateToken: "same",
            observedStateToken: "same",
            targetRegionChangeRatio: 0.03,
            targetRegionThreshold: 0.02
        ))
        #expect(ClickFastVerificationPolicy.postDispatchEvidenceChanged(
            baselineStateToken: "same",
            observedStateToken: "same",
            targetRegionChangeRatio: 0.01,
            targetRegionThreshold: 0.02
        ) == false)
    }
}

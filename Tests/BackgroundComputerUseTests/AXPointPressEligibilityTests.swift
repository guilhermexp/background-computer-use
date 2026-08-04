import ApplicationServices
import CoreGraphics
import Testing
@testable import BackgroundComputerUse

/// A coordinate click that proved no effect may escalate to the accessibility
/// element under the same point — but only to an element a human could have hit.
@Suite
struct AXPointPressEligibilityTests {
    private let press = [kAXPressAction as String]
    private let point = CGPoint(x: 120, y: 400)

    @Test
    func pressableElementUnderThePointIsEligible() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 380, width: 177, height: 41),
                pointTopLeft: point
            )
        )
    }

    @Test
    func elementWithoutPressActionIsRejected() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: ["AXShowMenu", "AXScrollToVisible"],
                frame: CGRect(x: 32, y: 380, width: 177, height: 41),
                pointTopLeft: point
            ) == false
        )
    }

    @Test
    func scrolledOutControlWithCollapsedFrameIsRejected() {
        // Chromium reports a scrolled-away web control at its layout position with a
        // collapsed frame; pressing it would act on something nobody can see.
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 400, width: 177, height: 1),
                pointTopLeft: point
            ) == false
        )
    }

    @Test
    func elementNotCoveringThePointIsRejected() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 700, width: 177, height: 41),
                pointTopLeft: point
            ) == false
        )
    }

    @Test
    func missingFrameIsRejected() {
        #expect(AXPointPressEligibility.isEligible(actions: press, frame: nil, pointTopLeft: point) == false)
    }

    @Test
    func pointOnTheFrameEdgeStaysEligible() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 120, y: 400, width: 60, height: 20),
                pointTopLeft: point
            )
        )
    }
}

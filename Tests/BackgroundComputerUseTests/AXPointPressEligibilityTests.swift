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
                pointTopLeft: point,
                enabled: true
            )
        )
    }

    @Test
    func elementWithoutPressActionIsRejected() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: ["AXShowMenu", "AXScrollToVisible"],
                frame: CGRect(x: 32, y: 380, width: 177, height: 41),
                pointTopLeft: point,
                enabled: true
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
                pointTopLeft: point,
                enabled: true
            ) == false
        )
    }

    @Test
    func elementNotCoveringThePointIsRejected() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 700, width: 177, height: 41),
                pointTopLeft: point,
                enabled: true
            ) == false
        )
    }

    @Test
    func missingFrameIsRejected() {
        #expect(AXPointPressEligibility.isEligible(actions: press, frame: nil, pointTopLeft: point, enabled: true) == false)
    }

    @Test
    func pointOnTheFrameEdgeStaysEligible() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 120, y: 400, width: 60, height: 20),
                pointTopLeft: point,
                enabled: true
            )
        )
    }

    @Test
    func disabledControlIsRejected() {
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 380, width: 177, height: 41),
                pointTopLeft: point,
                enabled: false
            ) == false
        )
    }

    @Test
    func unknownEnabledStateStaysEligible() {
        // Web surfaces often omit the attribute; absence must not block the press.
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 32, y: 380, width: 177, height: 41),
                pointTopLeft: point,
                enabled: nil
            )
        )
    }

    @Test
    func oversizedAncestorContainerIsRejected() {
        // Ancestors always cover the point; without a ceiling the walk would press a
        // group spanning half the window instead of the control.
        #expect(
            AXPointPressEligibility.isEligible(
                actions: press,
                frame: CGRect(x: 0, y: 0, width: 1_600, height: 900),
                pointTopLeft: point,
                enabled: true
            ) == false
        )
    }
}

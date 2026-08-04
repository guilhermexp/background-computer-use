import ApplicationServices
import CoreGraphics
import Foundation

/// Decides whether the accessibility element under a click point may be pressed as
/// a stand-in for a coordinate click that dispatched without proving an effect.
///
/// The guard matters because an accessibility tree keeps nodes a human cannot see:
/// Chromium reports scrolled-out web controls at their layout position with a
/// collapsed frame (observed: a 177x1 button while the document was scrolled away).
/// Pressing one of those would act on something the caller never pointed at.
enum AXPointPressEligibility {
    /// Slack around the frame edge, so a click on the boundary still counts.
    static let frameTolerance: CGFloat = 1
    /// Smallest frame side that can still be the control the caller pointed at.
    static let minimumDimension: CGFloat = 2

    static func isEligible(actions: [String], frame: CGRect?, pointTopLeft: CGPoint) -> Bool {
        guard actions.contains(kAXPressAction as String) else {
            return false
        }
        guard let frame = frame?.standardized,
              frame.isNull == false,
              frame.width >= minimumDimension,
              frame.height >= minimumDimension else {
            return false
        }
        return frame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(pointTopLeft)
    }
}

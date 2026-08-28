import ApplicationServices
import CoreGraphics
import Foundation

/// Decides whether the accessibility element under a click point may be pressed as
/// a stand-in for a coordinate click that dispatched without proving an effect.
///
/// The guard matters because an accessibility tree keeps nodes a human cannot see:
/// Chromium reports scrolled-out web controls at their layout position with a
/// collapsed frame (observed: a 177x1 button while the document was scrolled away).
enum AXPointPressEligibility {
    /// Slack around the frame edge, so a click on the boundary still counts.
    static let frameTolerance: CGFloat = 1
    /// Smallest frame side that can still be the control the caller pointed at.
    static let minimumDimension: CGFloat = 2
    /// Largest frame the escalation treats as "the control under the point".
    ///
    /// Ancestors are always larger than the point, so without a ceiling the walk
    /// would happily press a group spanning half the window. Mirrors the bound the
    /// repo already uses for safe descendant retargeting.
    static let maximumWidth: CGFloat = 1200
    static let maximumHeight: CGFloat = 320

    static func isEligible(
        actions: [String],
        frame: CGRect?,
        pointTopLeft: CGPoint,
        enabled: Bool?
    ) -> Bool {
        guard actions.contains(kAXPressAction as String) else {
            return false
        }
        // A disabled control cannot be what the caller meant to activate.
        guard enabled != false else {
            return false
        }
        guard let frame = frame?.standardized,
              frame.isNull == false,
              frame.width >= minimumDimension,
              frame.height >= minimumDimension,
              frame.width <= maximumWidth,
              frame.height <= maximumHeight
        else {
            return false
        }
        return frame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(pointTopLeft)
    }
}

import AppKit
import CoreGraphics
import Foundation

/// Live geometry of the window a cursor session is pinned to.
struct CursorWindowAnchor: Equatable {
    let windowNumber: Int
    let frameAppKit: CGRect
    let levelRawValue: Int
    let isOnScreen: Bool

    init(
        windowNumber: Int,
        frameAppKit: CGRect,
        levelRawValue: Int = NSWindow.Level.normal.rawValue,
        isOnScreen: Bool = true
    ) {
        self.windowNumber = windowNumber
        self.frameAppKit = frameAppKit.standardized
        self.levelRawValue = levelRawValue
        self.isOnScreen = isOnScreen
    }
}

/// Resolves the live geometry of the window a cursor session is attached to.
///
/// Production reads the window server. Cursor tests install a deterministic
/// table so window pinning can be exercised without real windows.
@MainActor
enum CursorWindowAnchorResolver {
    private static var overrides: [Int: CursorWindowAnchor]?

    static func anchor(forWindowNumber windowNumber: Int) -> CursorWindowAnchor? {
        if let overrides {
            return overrides[windowNumber]
        }
        return systemAnchor(forWindowNumber: windowNumber)
    }

    /// Installs a deterministic anchor table. `nil` restores the window server.
    static func setOverrides(_ anchors: [Int: CursorWindowAnchor]?) {
        overrides = anchors
    }

    private static func systemAnchor(forWindowNumber windowNumber: Int) -> CursorWindowAnchor? {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowNumber)
        ) as? [[String: Any]],
            let info = infoList.first else {
            return nil
        }

        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let quartzFrame = CGRect(dictionaryRepresentation: bounds) else {
            return nil
        }

        let frame = DesktopGeometry.appKitRect(fromQuartz: quartzFrame)
        let reportedOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        return CursorWindowAnchor(
            windowNumber: windowNumber,
            frameAppKit: frame,
            levelRawValue: info[kCGWindowLayer as String] as? Int ?? NSWindow.Level.normal.rawValue,
            isOnScreen: reportedOnScreen && DesktopGeometry.isOnScreen(frame)
        )
    }
}

/// Geometry that keeps the visual cursor pinned to the window it acts on.
///
/// Every clamp goes window first, then the display that holds that window —
/// never `NSScreen.main` and never the display a stray point happened to land
/// on, which is how the cursor used to jump across a multi-display setup.
enum CursorWindowPinning {
    /// Slack before a point counts as outside the window frame.
    private static let windowTolerance: CGFloat = 2
    /// Slack before a point counts as outside the screen frame.
    private static let screenTolerance: CGFloat = 1
    /// Inset applied when a point has to be pulled back inside a rect.
    private static let clampInset: CGFloat = 1

    static let outsideWindowWarning =
        "Cursor point was outside the attached window frame and was clamped into the window."
    static let outsideWindowScreenWarning =
        "Cursor point was outside the attached window's screen and was clamped into that screen."
    static let noWindowScreenWarning =
        "No screen geometry contained the attached window; the cursor point was clamped to the window frame only."

    /// Display holding the largest share of `windowFrame`; `nil` when the window
    /// overlaps no display at all (closed, minimized, or fully off-screen).
    static func screen(forWindowFrame windowFrame: CGRect) -> NSScreen? {
        let frame = windowFrame.standardized
        guard frame.isNull == false else { return nil }

        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(frame)
            guard intersection.isNull == false else { continue }
            let area = max(intersection.width, 0) * max(intersection.height, 0)
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (screen, area)
            }
        }
        return best?.screen
    }

    /// Clamps `point` into `windowFrame` and then into that window's display.
    static func pin(
        _ point: CGPoint,
        toWindowFrame windowFrame: CGRect,
        warnings: inout [String]
    ) -> CGPoint {
        var pinned = point
        let frame = windowFrame.standardized
        let hasUsableFrame = frame.isNull == false && frame.width > 0 && frame.height > 0

        if hasUsableFrame,
           frame.insetBy(dx: -windowTolerance, dy: -windowTolerance).contains(pinned) == false {
            warnings.append(outsideWindowWarning)
            pinned = clamp(pinned, to: frame.insetBy(dx: clampInset, dy: clampInset))
        }

        guard hasUsableFrame else {
            return pinned
        }

        guard let screenFrame = screen(forWindowFrame: frame)?.frame.standardized else {
            warnings.append(noWindowScreenWarning)
            return pinned
        }

        if screenFrame.insetBy(dx: -screenTolerance, dy: -screenTolerance).contains(pinned) == false {
            warnings.append(outsideWindowScreenWarning)
            pinned = clamp(pinned, to: screenFrame.insetBy(dx: clampInset, dy: clampInset))
        }
        return pinned
    }

    /// Keeps a point at the same relative spot inside a window that moved or resized.
    static func reanchor(_ point: CGPoint, from previous: CGRect, to current: CGRect) -> CGPoint {
        let from = previous.standardized
        let to = current.standardized
        guard from.width > 0, from.height > 0, to.width > 0, to.height > 0 else {
            return point
        }
        let relativeX = (point.x - from.minX) / from.width
        let relativeY = (point.y - from.minY) / from.height
        return CGPoint(
            x: to.minX + relativeX * to.width,
            y: to.minY + relativeY * to.height
        )
    }

    static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        let standardized = rect.standardized
        return CGPoint(
            x: min(max(point.x, standardized.minX), standardized.maxX),
            y: min(max(point.y, standardized.minY), standardized.maxY)
        )
    }
}

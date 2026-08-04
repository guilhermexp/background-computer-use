import AppKit
import CoreGraphics
import Testing
@testable import BackgroundComputerUse

/// The visual cursor belongs to the window it drives. It must never be painted
/// over an application it is not acting on — which is what happened while the
/// overlay was ordered against another process's window number.
@Suite(.serialized)
struct CursorExposureTests {
    private let runtime = CursorRuntimeTestScope()
    private static let windowNumber = 8801
    private static let windowFrame = CGRect(x: 120, y: 120, width: 400, height: 300)
    private static let point = CGPoint(x: 200, y: 200)

    @Test @MainActor
    func exposureIsFalseWhenAnotherAppCoversTheDrivenWindow() {
        CursorWindowExposure.setOverrides(nil)
        CursorWindowExposure.setRecordProviderForTesting {
            [
                record(pid: 501, windowNumber: 9002, frame: Self.windowFrame, orderIndex: 0),
                record(pid: 502, windowNumber: Self.windowNumber, frame: Self.windowFrame, orderIndex: 1),
            ]
        }
        defer { CursorWindowExposure.setRecordProviderForTesting(nil) }

        #expect(CursorWindowExposure.isExposed(windowNumber: Self.windowNumber, at: Self.point) == false)
        #expect(CursorWindowExposure.isExposed(windowNumber: 9002, at: Self.point))
    }

    @Test @MainActor
    func exposureIgnoresOverlayWindowsOwnedByThisProcess() {
        CursorWindowExposure.setOverrides(nil)
        CursorWindowExposure.setRecordProviderForTesting {
            [
                record(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    windowNumber: 1,
                    frame: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                    orderIndex: 0
                ),
                record(pid: 502, windowNumber: Self.windowNumber, frame: Self.windowFrame, orderIndex: 1),
            ]
        }
        defer { CursorWindowExposure.setRecordProviderForTesting(nil) }

        #expect(CursorWindowExposure.isExposed(windowNumber: Self.windowNumber, at: Self.point))
    }

    @Test @MainActor
    func exposureIsFalseOutsideEveryWindow() {
        CursorWindowExposure.setOverrides(nil)
        CursorWindowExposure.setRecordProviderForTesting {
            [record(pid: 502, windowNumber: Self.windowNumber, frame: Self.windowFrame, orderIndex: 0)]
        }
        defer { CursorWindowExposure.setRecordProviderForTesting(nil) }

        #expect(
            CursorWindowExposure.isExposed(
                windowNumber: Self.windowNumber,
                at: CGPoint(x: 5_000, y: 5_000)
            ) == false
        )
    }

    @Test
    func overlayIsNotDrawnWhileTheDrivenWindowIsCovered() {
        let cursorID = "exposure-covered-window"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: anchor()])
        defer { CursorRuntime.resetForTesting() }

        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )
        #expect(CursorRuntime.drawsOverlayForTesting(cursorID: cursorID))

        CursorRuntime.setWindowExposureForTesting([Self.windowNumber: false])
        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX + 4, y: Self.windowFrame.midY + 4),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )

        #expect(CursorRuntime.drawsOverlayForTesting(cursorID: cursorID) == false)

        CursorRuntime.setWindowExposureForTesting([Self.windowNumber: true])
        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )
        #expect(CursorRuntime.drawsOverlayForTesting(cursorID: cursorID))
    }

    @Test
    func coveredWindowStillCompositesTheCursorIntoItsOwnScreenshot() {
        let cursorID = "exposure-screenshot-composite"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: anchor()])
        defer { CursorRuntime.resetForTesting() }

        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )
        CursorRuntime.setWindowExposureForTesting([Self.windowNumber: false])

        // The window's own screenshot is the agent's view of that window, so the
        // cursor stays in it even while the screen shows another app on top.
        let snapshots = CursorRuntime.snapshots(forWindowNumber: Self.windowNumber)
        #expect(snapshots.contains { $0.cursorID == cursorID })
    }

    private func anchor(isOnScreen: Bool = true) -> CursorWindowAnchor {
        CursorWindowAnchor(
            windowNumber: Self.windowNumber,
            frameAppKit: Self.windowFrame,
            levelRawValue: NSWindow.Level.normal.rawValue,
            isOnScreen: isOnScreen
        )
    }

    private func record(
        pid: pid_t,
        windowNumber: Int,
        frame: CGRect,
        orderIndex: Int
    ) -> CGWindowRecord {
        CGWindowRecord(
            ownerPID: pid,
            windowNumber: windowNumber,
            title: "w\(windowNumber)",
            frameAppKit: frame,
            orderIndex: orderIndex,
            isOnScreen: true
        )
    }
}

import AppKit
import CoreGraphics
import QuartzCore
import Testing
@testable import BackgroundComputerUse

/// The visual cursor must land exactly where the action is dispatched, stay
/// inside the window it is driving, remain visible while that window is alive,
/// and never move on its own.
@Suite(.serialized)
struct CursorPinningTests {
    private let runtime = CursorRuntimeTestScope()
    private static let windowNumber = 7701
    /// Long enough for the presence lifecycle to have hidden an unpinned cursor.
    private static let presenceObservationDelay =
        CursorPresenceTiming.idleHideDelay + CursorPresenceTiming.fadeOutDuration + 0.4
    private static let windowFrame = CGRect(x: 80, y: 80, width: 400, height: 300)

    @Test
    func visualCursorPointEqualsDispatchedActionPoint() throws {
        let cursorID = "pinning-visual-point-equals-action"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        let window = resolvedWindow()
        let target = largeTarget(interactionPoint: PointDTO(x: 250, y: 200))
        let actionPoint = AXCursorTargeting.targetPoint(for: target, window: window)

        // Seed a previous cursor position far from the target: the removed
        // "visual interest" offset only kicked in when a previous point existed.
        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.minX + 5, y: Self.windowFrame.minY + 5),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )

        let cursor = AXCursorTargeting.prepareClick(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#20C46B"),
            target: target,
            window: window,
            options: .visualCursorEnabled
        )
        AXCursorTargeting.finishClick(cursor: cursor)
        let expectedPoint = try #require(actionPoint.point)
        #expect(cursor.moved)
        #expect(cursor.targetPointAppKit?.x == Double(expectedPoint.x))
        #expect(cursor.targetPointAppKit?.y == Double(expectedPoint.y))
        #expect(cursor.targetPointSource == "suggested_interaction_point")
        #expect(cursor.targetPointSource?.contains("visual_interest_offset") == false)
    }

    @Test
    func visualCursorPointIsNotRandomized() throws {
        let cursorID = "pinning-visual-point-is-stable"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        let window = resolvedWindow()
        let target = largeTarget(interactionPoint: PointDTO(x: 250, y: 200))
        var points: [PointDTO] = []

        for _ in 0..<3 {
            CursorRuntime.snap(
                to: CGPoint(x: Self.windowFrame.minX + 5, y: Self.windowFrame.minY + 5),
                attachedWindowNumber: Self.windowNumber,
                cursorID: cursorID
            )
            let cursor = AXCursorTargeting.prepareClick(
                requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#20C46B"),
                target: target,
                window: window,
                options: .visualCursorEnabled
            )
            AXCursorTargeting.finishClick(cursor: cursor)
            points.append(try #require(cursor.targetPointAppKit))
        }

        #expect(points.allSatisfy { $0.x == points[0].x && $0.y == points[0].y })
    }

    @Test
    func cursorPointStaysInsideTheAttachedWindowInsteadOfJumpingToAnotherScreen() throws {
        // A window parked off every display: the old clamp resolved a screen from
        // the stray point (or `NSScreen.main`) and dragged the cursor out of the
        // window. The pinned clamp keeps it inside the window it acts on.
        let offDisplayFrame = CGRect(x: 100_000, y: 100_000, width: 400, height: 300)
        let window = resolvedWindow(frame: offDisplayFrame)
        let target = largeTarget(
            interactionPoint: PointDTO(x: offDisplayFrame.midX + 5_000, y: offDisplayFrame.midY + 5_000),
            frame: RectDTO(
                x: offDisplayFrame.minX + 20,
                y: offDisplayFrame.minY + 20,
                width: 300,
                height: 200
            )
        )

        let resolved = AXCursorTargeting.targetPoint(for: target, window: window)
        let point = try #require(resolved.point)

        #expect(offDisplayFrame.contains(point))
        #expect(resolved.warnings.contains(CursorWindowPinning.outsideWindowWarning))
        #expect(CursorWindowPinning.screen(forWindowFrame: offDisplayFrame) == nil)
    }

    @Test
    func attachedCursorStaysVisibleAfterIdleHideDelay() {
        let cursorID = "pinning-presence-attached"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )

        sleepRunLoop(Self.presenceObservationDelay)

        // On-screen presence is what the pinning requirement is about.
        #expect(CursorRuntime.drawsOverlayForTesting(cursorID: cursorID))
    }

    @Test
    func idleCursorStopsBeingCompositedIntoTheWindowScreenshot() {
        let cursorID = "pinning-presence-screenshot"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )
        #expect(
            CursorRuntime.snapshots(forWindowNumber: Self.windowNumber)
                .contains { $0.cursorID == cursorID }
        )

        sleepRunLoop(Self.presenceObservationDelay)

        // The screenshot is evidence the click verifier reads: a cursor parked on the
        // last click point would occlude the anchor and manufacture its own proof.
        #expect(
            CursorRuntime.snapshots(forWindowNumber: Self.windowNumber)
                .contains { $0.cursorID == cursorID } == false
        )
        #expect(CursorRuntime.drawsOverlayForTesting(cursorID: cursorID))
    }

    @Test
    func cursorFadesOutWhenTheAttachedWindowLeavesTheScreen() {
        let cursorID = "pinning-presence-detached"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        CursorRuntime.snap(
            to: CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY),
            attachedWindowNumber: Self.windowNumber,
            cursorID: cursorID
        )
        CursorRuntime.setWindowAnchorsForTesting([Self.windowNumber: liveAnchor(isOnScreen: false)])

        sleepRunLoop(Self.presenceObservationDelay)

        #expect(CursorRuntime.snapshots(forWindowNumber: Self.windowNumber).isEmpty)
    }

    @Test
    func cursorFollowsTheAttachedWindowWhenItsFrameChanges() throws {
        let cursorID = "pinning-follows-window-frame"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        let start = CGPoint(x: Self.windowFrame.minX + 100, y: Self.windowFrame.minY + 75)
        CursorRuntime.snap(to: start, attachedWindowNumber: Self.windowNumber, cursorID: cursorID)

        let movedFrame = Self.windowFrame.offsetBy(dx: 220, dy: 140)
        CursorRuntime.setWindowAnchorsForTesting([
            Self.windowNumber: liveAnchor(frame: movedFrame),
        ])
        CursorRuntime.tickForTesting(cursorID: cursorID, now: CACurrentMediaTime() + 0.3)

        let expected = CursorWindowPinning.reanchor(start, from: Self.windowFrame, to: movedFrame)
        let position = try #require(CursorRuntime.currentPosition(cursorID: cursorID))
        #expect(abs(position.x - expected.x) <= 0.001)
        #expect(abs(position.y - expected.y) <= 0.001)
    }

    @Test
    func restingCursorDoesNotDrift() throws {
        let cursorID = "pinning-no-idle-drift"
        CursorRuntime.resetForTesting(windowAnchors: [Self.windowNumber: liveAnchor()])
        defer { CursorRuntime.resetForTesting() }

        let start = CGPoint(x: Self.windowFrame.midX, y: Self.windowFrame.midY)
        CursorRuntime.snap(to: start, attachedWindowNumber: Self.windowNumber, cursorID: cursorID)

        let base = CACurrentMediaTime()
        for frame in 1...30 {
            CursorRuntime.tickForTesting(cursorID: cursorID, now: base + Double(frame) / 60.0)
        }

        let position = try #require(CursorRuntime.currentPosition(cursorID: cursorID))
        #expect(position == start)
    }

    private func liveAnchor(
        frame: CGRect = CursorPinningTests.windowFrame,
        isOnScreen: Bool = true
    ) -> CursorWindowAnchor {
        CursorWindowAnchor(
            windowNumber: Self.windowNumber,
            frameAppKit: frame,
            levelRawValue: NSWindow.Level.normal.rawValue,
            isOnScreen: isOnScreen
        )
    }

    private func resolvedWindow(frame: CGRect = CursorPinningTests.windowFrame) -> ResolvedWindowDTO {
        ResolvedWindowDTO(
            windowID: "window-\(Self.windowNumber)",
            title: "Window",
            bundleID: "com.example.Test",
            pid: 123,
            launchDate: nil,
            windowNumber: Self.windowNumber,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            resolutionStrategy: "test"
        )
    }

    private func largeTarget(
        interactionPoint: PointDTO,
        frame: RectDTO = RectDTO(x: 100, y: 100, width: 300, height: 200)
    ) -> AXActionTargetSnapshot {
        AXActionTargetSnapshot(
            displayIndex: 3,
            projectedIndex: 3,
            primaryCanonicalIndex: 3,
            canonicalIndices: [3],
            displayRole: "button",
            rawRole: "AXButton",
            rawSubrole: nil,
            title: "Target",
            description: nil,
            identifier: nil,
            placeholder: nil,
            url: nil,
            nodeID: "node-3",
            refetchFingerprint: "fingerprint-3",
            refetchLocator: nil,
            projectedValueKind: nil,
            projectedValuePreview: nil,
            projectedValueLength: nil,
            projectedValueTruncated: false,
            isValueSettable: false,
            supportsValueSet: false,
            isTextEntry: false,
            isFocused: false,
            isSelected: false,
            parameterizedAttributes: [],
            frameAppKit: frame,
            activationPointAppKit: nil,
            suggestedInteractionPointAppKit: interactionPoint
        )
    }
}

import ApplicationServices
@testable import BackgroundComputerUse
import CoreGraphics
import Foundation
import Testing

/// A coordinate click that proved no effect may escalate to the accessibility
/// element under the same point — but only to an element a human could have hit.
struct AXPointPressEligibilityTests {
    @Test
    func hitTestRetryStopsAtFirstAvailableResult() {
        var attempts = 0
        let result: String? = ClickHitTestRetry.firstAvailable(
            maximumAttempts: 3,
            sleep: {},
            action: {
                attempts += 1
                return attempts == 3 ? "button" : nil
            }
        )
        #expect(result == "button")
        #expect(attempts == 3)
    }

    @Test
    func rendererBootstrapUsesBothChromiumAccessibilitySwitchesWithoutDuplicates() {
        #expect(RendererAccessibilityBootstrap.attributeNames == [
            "AXManualAccessibility",
            "AXEnhancedUserInterface",
        ])
        #expect(Set(RendererAccessibilityBootstrap.attributeNames).count == 2)
        #expect(RendererAccessibilityBootstrap.shouldTryEnhanced(after: .attributeUnsupported))
        #expect(RendererAccessibilityBootstrap.shouldTryEnhanced(after: .success) == false)
        #expect(RendererAccessibilityBootstrap.isLikelyRenderer(
            bundleID: "com.google.Chrome",
            frameworkNames: []
        ))
        #expect(RendererAccessibilityBootstrap.isLikelyRenderer(
            bundleID: "com.example.Editor",
            frameworkNames: ["Electron Framework.framework"]
        ))
        #expect(RendererAccessibilityBootstrap.isLikelyRenderer(
            bundleID: "com.apple.TextEdit",
            frameworkNames: []
        ) == false)
        #expect(RendererAccessibilityWorkerMain.pid(from: ["1234"]) == 1234)
        #expect(RendererAccessibilityWorkerMain.pid(from: ["0"]) == nil)
    }

    @Test
    func rendererBootstrapWorkerDispatchDoesNotBlockTheCaller() {
        let probe = WorkerDispatchProbe()

        RendererAccessibilityBootstrap.dispatchWorker(
            { probe.markRan() },
            enqueue: { work in probe.capture(work) }
        )

        #expect(probe.hasCapturedWork)
        #expect(probe.hasRun == false)
        probe.runCaptured()
        #expect(probe.hasRun)
    }

    @Test
    func ocrSemanticPromotionRequiresTheSameNormalizedLabel() {
        #expect(OCRSemanticPromotionPolicy.labelsMatch(
            anchor: "BCU Smoke Button",
            candidate: "  bcu smoke button  "
        ))
        #expect(OCRSemanticPromotionPolicy.labelsMatch(
            anchor: "Delete",
            candidate: "Download"
        ) == false)
    }

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
                frame: CGRect(x: 0, y: 0, width: 1600, height: 900),
                pointTopLeft: point,
                enabled: true
            ) == false
        )
    }
}

private final class WorkerDispatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedWork: (@Sendable () -> Void)?
    private var ran = false

    var hasCapturedWork: Bool {
        lock.withLock { capturedWork != nil }
    }

    var hasRun: Bool {
        lock.withLock { ran }
    }

    func capture(_ work: @escaping @Sendable () -> Void) {
        lock.withLock {
            capturedWork = work
        }
    }

    func markRan() {
        lock.withLock {
            ran = true
        }
    }

    func runCaptured() {
        let work = lock.withLock { capturedWork }
        work?()
    }
}

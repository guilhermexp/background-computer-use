import ApplicationServices
import Darwin
import Testing
@testable import BackgroundComputerUse

@Suite
struct ClickFocusEvidenceTests {
    @Test
    func transportSamplesFocusAfterPreparationAndBeforeMouseEvents() throws {
        var trace: [String] = []
        let transport = NativeBackgroundClickTransport(
            prepareTarget: { _ in
                trace.append("focus")
                return (focusStatus: 0, notes: [])
            },
            postEvent: { _, _ in trace.append("event") },
            wait: { _ in }
        )
        let target = RoutedClickTarget(
            pid: getpid(),
            bundleID: "com.example.focus-test",
            windowNumber: 1,
            title: "Focus test",
            frameAppKit: CGRect(x: 0, y: 0, width: 320, height: 240),
            ownerConnection: 0,
            processSerialNumberHigh: 0,
            processSerialNumberLow: 0,
            processSerialNumberPacked: 0,
            cgBoundsTopLeft: nil
        )

        let result = try transport.dispatch(
            NativeBackgroundClickDispatchRequest(
                target: target,
                eventTapPointTopLeft: CGPoint(x: 20, y: 20),
                appKitPoint: CGPoint(x: 20, y: 220),
                clickCount: 1,
                mouseButton: .left
            ),
            afterTargetFocus: { trace.append("baseline") }
        )

        #expect(result.dispatchSuccess)
        #expect(trace.first == "focus")
        #expect(trace.dropFirst().first == "baseline")
        #expect(trace.filter { $0 == "event" }.count == result.eventsPrepared)
    }

    @Test
    func treeReorderingDoesNotChangeStableFocusedElementIdentity() {
        let focusedBeforeReordering = ClickFocusVerifier.focusedElement(
            focusedCanonicalIndex: 1,
            liveElementsByCanonicalIndex: [1: AXUIElementCreateApplication(getpid())]
        )
        let focusedAfterReordering = ClickFocusVerifier.focusedElement(
            focusedCanonicalIndex: 8,
            liveElementsByCanonicalIndex: [8: AXUIElementCreateApplication(getpid())]
        )

        let evidence = ClickFocusVerifier.evidence(
            baselineAfterTransport: focusedBeforeReordering,
            afterClick: focusedAfterReordering
        )

        #expect(evidence.changed == false)
        #expect(evidence.diagnostic == nil)
    }

    @Test
    func realFocusMoveStillCountsAsIntentEvidence() {
        let focusedBeforeClick = AXUIElementCreateApplication(getpid())
        let focusedAfterClick = AXUIElementCreateSystemWide()

        let evidence = ClickFocusVerifier.evidence(
            baselineAfterTransport: focusedBeforeClick,
            afterClick: focusedAfterClick
        )

        #expect(evidence.changed == true)
        #expect(evidence.diagnostic == nil)
    }

    @Test
    func unreadableFocusFailsClosedWithDiagnostic() {
        let evidence = ClickFocusVerifier.evidence(
            baselineAfterTransport: nil,
            afterClick: AXUIElementCreateApplication(getpid())
        )

        #expect(evidence.changed == nil)
        #expect(evidence.diagnostic == ClickFocusVerifier.unavailableDiagnostic)
    }
}

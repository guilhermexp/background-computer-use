import CoreGraphics
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct VerificationHonestyTests {

    // MARK: - Honest success gate

    @Test
    func ambientOnlyEvidenceIsNotSuccess() {
        let evidence = makeEvidence(
            renderedTextChanged: true,
            selectionSummaryChanged: true,
            targetRegionChangeRatio: 0
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(evidence.ambientOnlySignals == ["rendered_text_changed", "selection_summary_changed"])
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: true, verification: evidence)
                == .effectNotVerified
        )
        #expect(evidence.verificationNotes.contains(ClickIntentVerifier.ambientOnlyNote))
    }

    @Test
    func targetLocalPixelChangeIsSuccess() {
        let evidence = makeEvidence(
            renderedTextChanged: true,
            selectionSummaryChanged: true,
            targetRegionChangeRatio: ClickIntentVerifier.targetRegionChangeThreshold
        )

        #expect(evidence.intentSignals == ["target_region_changed"])
        #expect(evidence.ambientOnlySignals.isEmpty)
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: true, verification: evidence) == .success
        )
    }

    @Test
    func targetLocalRatioBelowThresholdIsNotSuccess() {
        let evidence = makeEvidence(
            renderedTextChanged: true,
            targetRegionChangeRatio: ClickIntentVerifier.targetRegionChangeThreshold - 0.001
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: true, verification: evidence)
                == .effectNotVerified
        )
    }

    @Test
    func structuralSignalsAreAccepted() {
        let anchorGone = makeEvidence(ocrAnchorDisappeared: true, targetRegionChangeRatio: 0)
        let focusMoved = makeEvidence(focusedElementChanged: true, targetRegionChangeRatio: 0)
        let modalOpened = makeEvidence(modalDialogOpened: true, targetRegionChangeRatio: 0)
        let targetChanged = makeEvidence(targetStateChanged: true, targetRegionChangeRatio: 0)

        #expect(anchorGone.intentSignals == ["ocr_anchor_disappeared"])
        #expect(focusMoved.intentSignals == ["focused_element_changed"])
        #expect(modalOpened.intentSignals == ["modal_dialog_opened"])
        #expect(targetChanged.intentSignals == ["target_state_changed"])
    }

    @Test
    func dispatchFailureIsNeverSuccess() {
        let evidence = makeEvidence(targetRegionChangeRatio: 1)

        #expect(evidence.intentSignals == ["target_region_changed"])
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: false, verification: evidence)
                == .effectNotVerified
        )
    }

    @Test
    func missingVerificationIsNeverSuccess() {
        #expect(ClickIntentVerifier.verified(nil) == false)
        #expect(ClickIntentVerifier.classification(dispatchSuccess: true, verification: nil) == .effectNotVerified)
    }

    @Test
    func stableWebAreaTextChangeIsSuccess() {
        let evidence = makeEvidence(
            webRendererSurface: true,
            dispatchSuccess: true,
            webAreaBaselineStable: true,
            webAreaTextBefore: "Submit\nNOT CLICKED",
            webAreaTextAfter: "Submit\nCLICKED 1"
        )

        #expect(evidence.intentSignals == ["web_area_text_changed"])
        #expect(evidence.ambientOnlySignals.isEmpty)
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: true, verification: evidence) == .success
        )
    }

    @Test
    func unstableWebAreaTextChangeIsAmbientOnly() {
        let evidence = makeEvidence(
            webRendererSurface: true,
            dispatchSuccess: true,
            webAreaBaselineStable: false,
            webAreaTextBefore: "Submit\nCOUNT 2",
            webAreaTextAfter: "Submit\nCOUNT 3"
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(evidence.ambientOnlySignals == ["web_area_text_changed"])
        #expect(
            ClickIntentVerifier.classification(dispatchSuccess: true, verification: evidence)
                == .effectNotVerified
        )
        #expect(evidence.verificationNotes.contains(ClickIntentVerifier.unstableWebAreaBaselineNote))
    }

    @Test
    func missingWebAreaBaselineFailsClosedWithDiagnostic() {
        let evidence = makeEvidence(
            webRendererSurface: true,
            dispatchSuccess: true,
            webAreaBaselineStable: nil,
            webAreaTextBefore: nil,
            webAreaTextAfter: "CLICKED 1"
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(evidence.verificationNotes.contains(ClickIntentVerifier.missingWebAreaBaselineNote))
    }

    @Test
    func missingPostSettleWebAreaSampleFailsClosedWithDiagnostic() {
        let evidence = makeEvidence(
            webRendererSurface: true,
            dispatchSuccess: true,
            webAreaBaselineStable: true,
            webAreaTextBefore: "NOT CLICKED",
            webAreaTextAfter: nil
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(evidence.verificationNotes.contains(ClickIntentVerifier.missingPostWebAreaSampleNote))
    }

    @Test
    func nativeSurfaceNeverAwardsWebAreaTextChange() {
        let evidence = makeEvidence(
            renderedTextChanged: true,
            webRendererSurface: false,
            dispatchSuccess: true,
            webAreaBaselineStable: true,
            webAreaTextBefore: "Before",
            webAreaTextAfter: "After"
        )

        #expect(evidence.intentSignals.isEmpty)
        #expect(evidence.ambientOnlySignals == ["rendered_text_changed"])
    }

    // MARK: - Target-local evidence is always computed or diagnosed

    @Test
    func targetRegionRatioIsComputedWhenARegionExists() throws {
        let window = RectDTO(x: 0, y: 0, width: 200, height: 200)
        let region = try #require(
            ClickTargetRegion.normalizedRegion(
                targetFrameAppKit: RectDTO(x: 20, y: 120, width: 60, height: 60),
                pointAppKit: nil,
                windowFrameAppKit: window
            )
        )
        #expect(region == CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.3))

        let before = try makeImage(changedRect: nil)
        // CGContext fills bottom-left-origin: normalized y 0.6...0.9 is pixel rows 60...90 here.
        let after = try makeImage(changedRect: CGRect(x: 12, y: 62, width: 24, height: 24))

        let evidence = ClickTargetRegion.evidence(region: region, before: before, after: after)
        let ratio = try #require(evidence.targetRegionChangeRatio)
        #expect(ratio > 0)
        #expect(evidence.fullImageChangeRatio != nil)
        #expect(evidence.diagnostic == nil)
    }

    @Test
    func coordinateOnlyClickStillResolvesAProbeRegion() throws {
        let window = RectDTO(x: 100, y: 100, width: 400, height: 400)
        let region = try #require(
            ClickTargetRegion.normalizedRegion(
                targetFrameAppKit: nil,
                pointAppKit: CGPoint(x: 300, y: 300),
                windowFrameAppKit: window
            )
        )
        let expectedSide = ClickTargetRegion.coordinateProbeSizeAppKit / 400
        #expect(abs(region.width - expectedSide) < 0.0001)
        #expect(abs(region.midX - 0.5) < 0.0001)
        #expect(abs(region.midY - 0.5) < 0.0001)
    }

    @Test
    func missingPixelEvidenceIsDiagnosedNotSilent() throws {
        let region = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let image = try makeImage(changedRect: nil)

        let noRegion = ClickTargetRegion.evidence(region: nil, before: image, after: image)
        #expect(noRegion.targetRegionChangeRatio == nil)
        #expect(noRegion.diagnostic == ClickTargetRegion.unresolvedRegionDiagnostic)

        let noBefore = ClickTargetRegion.evidence(region: region, before: nil, after: image)
        #expect(noBefore.targetRegionChangeRatio == nil)
        #expect(noBefore.diagnostic == ClickTargetRegion.missingBeforeImageDiagnostic)

        let noAfter = ClickTargetRegion.evidence(region: region, before: image, after: nil)
        #expect(noAfter.targetRegionChangeRatio == nil)
        #expect(noAfter.diagnostic == ClickTargetRegion.missingAfterImageDiagnostic)
    }

    @Test
    func uncomputedRegionNeverCountsAsAnIntentSignal() {
        let assessment = ClickIntentVerifier.assess(
            focusedElementChanged: false,
            modalDialogOpened: false,
            windowTitleChanged: false,
            targetStateChanged: false,
            ocrAnchorDisappeared: nil,
            targetRegionChangeRatio: nil,
            renderedTextChanged: true,
            selectionSummaryChanged: true
        )

        #expect(assessment.verified == false)
        #expect(assessment.intentSignals.isEmpty)
    }

    // MARK: - OCR timing and deadline

    @Test
    func ocrRecognitionReportsItsOwnDuration() throws {
        let image = try makeImage(changedRect: nil, width: 64, height: 64)
        let outcome = OCRRecognitionService.measure(cgImage: image, interactionToken: "it_test")

        #expect(outcome.durationMs > 0)
        #expect(outcome.summary.status == .success || outcome.summary.status == .noText)
    }

    @Test
    func ocrRecognitionFailsClosedOnDeadline() throws {
        let image = try makeImage(changedRect: nil, width: 512, height: 512)
        let outcome = OCRRecognitionService.measure(
            cgImage: image,
            interactionToken: "it_test",
            deadline: 0
        )

        #expect(outcome.summary.status == .recognitionFailed)
        let diagnostic = try #require(outcome.summary.diagnostic)
        #expect(diagnostic.lowercased().contains("deadline"))
        #expect(outcome.summary.anchors.isEmpty)
    }

    @Test
    func readPerformanceEncodesOCRTimeOnlyWhenMeasured() throws {
        let encoder = JSONEncoder()

        let withOCR = try encoder.encode(
            ReadPerformanceDTO(resolveMs: 1, captureMs: 2, projectionMs: 0, screenshotMs: 3, totalMs: 40, ocrMs: 34)
        )
        let withOCRObject = try #require(
            try JSONSerialization.jsonObject(with: withOCR) as? [String: Any]
        )
        #expect(withOCRObject["ocrMs"] as? Double == 34)

        let withoutOCR = try encoder.encode(
            ReadPerformanceDTO(resolveMs: 1, captureMs: 2, projectionMs: 0, screenshotMs: 3, totalMs: 6)
        )
        let withoutOCRObject = try #require(
            try JSONSerialization.jsonObject(with: withoutOCR) as? [String: Any]
        )
        #expect(withoutOCRObject["ocrMs"] == nil)
    }

    // MARK: - Helpers

    private func makeEvidence(
        renderedTextChanged: Bool? = nil,
        selectionSummaryChanged: Bool? = nil,
        focusedElementChanged: Bool? = nil,
        windowTitleChanged: Bool? = nil,
        modalDialogOpened: Bool? = nil,
        targetStateChanged: Bool? = nil,
        ocrAnchorDisappeared: Bool? = nil,
        targetRegionChangeRatio: Double? = nil,
        webRendererSurface: Bool = false,
        dispatchSuccess: Bool = true,
        webAreaBaselineStable: Bool? = nil,
        webAreaTextBefore: String? = nil,
        webAreaTextAfter: String? = nil
    ) -> ClickVerificationEvidenceDTO {
        let assessment = ClickIntentVerifier.assess(
            focusedElementChanged: focusedElementChanged,
            modalDialogOpened: modalDialogOpened,
            windowTitleChanged: windowTitleChanged,
            targetStateChanged: targetStateChanged,
            ocrAnchorDisappeared: ocrAnchorDisappeared,
            targetRegionChangeRatio: targetRegionChangeRatio,
            renderedTextChanged: renderedTextChanged,
            selectionSummaryChanged: selectionSummaryChanged,
            webRendererSurface: webRendererSurface,
            dispatchSuccess: dispatchSuccess,
            webAreaBaselineStable: webAreaBaselineStable,
            webAreaTextBefore: webAreaTextBefore,
            webAreaTextAfter: webAreaTextAfter
        )
        return ClickVerificationEvidenceDTO(
            preStateToken: "pre",
            postStateToken: "post",
            targetRelocated: false,
            refreshedTargetMatchStrategy: nil,
            beforeTargetSelected: nil,
            afterTargetSelected: nil,
            beforeTargetFocused: nil,
            afterTargetFocused: nil,
            beforeTargetValuePreview: nil,
            afterTargetValuePreview: nil,
            beforeFocusedNodeID: nil,
            afterFocusedNodeID: nil,
            renderedTextChanged: renderedTextChanged,
            selectionSummaryChanged: selectionSummaryChanged,
            focusedElementChanged: focusedElementChanged,
            windowTitleChanged: windowTitleChanged,
            modalDialogOpened: modalDialogOpened,
            targetStateChanged: targetStateChanged,
            webAreaTextChanged: webAreaTextBefore.flatMap { before in
                webAreaTextAfter.map { before != $0 }
            },
            webAreaBaselineStable: webAreaBaselineStable,
            webAreaBaselineDiagnostic: webAreaBaselineStable == false
                ? ClickIntentVerifier.unstableWebAreaBaselineNote
                : nil,
            ocrAnchorMatched: ocrAnchorDisappeared == nil ? nil : true,
            ocrAnchorRelocated: nil,
            ocrAnchorDisappeared: ocrAnchorDisappeared,
            targetRegionChangeRatio: targetRegionChangeRatio,
            fullImageChangeRatio: nil,
            foregroundPreserved: nil,
            targetRegionChangeThreshold: ClickIntentVerifier.targetRegionChangeThreshold,
            targetRegionDiagnostic: nil,
            ocrAnchorDiagnostic: nil,
            intentSignals: assessment.intentSignals,
            ambientOnlySignals: assessment.ambientOnlySignals,
            verificationNotes: assessment.notes
        )
    }

    private func makeImage(
        changedRect: CGRect?,
        width: Int = 100,
        height: Int = 100
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let changedRect {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(changedRect)
        }
        return try #require(context.makeImage())
    }
}

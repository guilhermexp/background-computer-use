import CoreGraphics
import Foundation

/// Declares which post-click observations are allowed to prove that a click did what it was asked to do.
///
/// Every click route funnels through this type, so `coordinate_xy`, `ocr_anchor_xy`, `semantic_ax`, and
/// `ax_element_pointer_xy` cannot drift into different levels of permissiveness.
enum ClickIntentVerifier {
    /// Fraction of changed samples inside the resolved target region that counts as a target-local effect.
    static let targetRegionChangeThreshold = 0.018

    enum IntentSignal: String {
        case targetRegionChanged = "target_region_changed"
        case ocrAnchorDisappeared = "ocr_anchor_disappeared"
        case focusedElementChanged = "focused_element_changed"
        case modalDialogOpened = "modal_dialog_opened"
        case windowTitleChanged = "window_title_changed"
        case targetStateChanged = "target_state_changed"
        case webAreaTextChanged = "web_area_text_changed"
    }

    enum AmbientSignal: String {
        case renderedTextChanged = "rendered_text_changed"
        case selectionSummaryChanged = "selection_summary_changed"
        case windowTitleChanged = "window_title_changed"
        case webAreaTextChanged = "web_area_text_changed"
    }

    static let ambientOnlyNote = "Ambient window changes only (rendered text and/or selection summary). A live window changes those without the click landing, so they do not prove the requested effect."

    static let noSignalNote = "No target-local or structural post-click evidence was observed."

    static let unstableWebAreaBaselineNote = "Web-area text changed after click, but the two pre-dispatch samples differed; the web-area baseline was unstable, so the change is ambient only."

    static let missingWebAreaBaselineNote = "The web-area text baseline could not be established before dispatch, so web-area text cannot count as intent evidence."

    static let missingPostWebAreaSampleNote = "The post-settle web-area text sample was unavailable, so web-area text change could not be computed as intent evidence."

    struct Assessment: Equatable {
        let intentSignals: [String]
        let ambientOnlySignals: [String]
        let notes: [String]

        var verified: Bool { intentSignals.isEmpty == false }
    }

    static func assess(
        focusedElementChanged: Bool?,
        modalDialogOpened: Bool?,
        windowTitleChanged: Bool?,
        targetStateChanged: Bool?,
        ocrAnchorDisappeared: Bool?,
        targetRegionChangeRatio: Double?
    ) -> Assessment {
        assess(
            focusedElementChanged: focusedElementChanged,
            modalDialogOpened: modalDialogOpened,
            windowTitleChanged: windowTitleChanged,
            targetStateChanged: targetStateChanged,
            ocrAnchorDisappeared: ocrAnchorDisappeared,
            targetRegionChangeRatio: targetRegionChangeRatio,
            renderedTextChanged: nil,
            selectionSummaryChanged: nil
        )
    }

    static func assess(
        focusedElementChanged: Bool?,
        modalDialogOpened: Bool?,
        windowTitleChanged: Bool?,
        targetStateChanged: Bool?,
        ocrAnchorDisappeared: Bool?,
        targetRegionChangeRatio: Double?,
        renderedTextChanged: Bool?,
        selectionSummaryChanged: Bool?,
        webRendererSurface: Bool = false,
        dispatchSuccess: Bool = true,
        webAreaBaselineStable: Bool? = nil,
        webAreaTextBefore: String? = nil,
        webAreaTextAfter: String? = nil,
        webAreaTextChanged: Bool? = nil
    ) -> Assessment {
        var intent: [String] = []
        if let ratio = targetRegionChangeRatio, ratio >= targetRegionChangeThreshold {
            intent.append(IntentSignal.targetRegionChanged.rawValue)
        }
        if ocrAnchorDisappeared == true {
            intent.append(IntentSignal.ocrAnchorDisappeared.rawValue)
        }
        if focusedElementChanged == true {
            intent.append(IntentSignal.focusedElementChanged.rawValue)
        }
        if modalDialogOpened == true {
            intent.append(IntentSignal.modalDialogOpened.rawValue)
        }
        // A browser window title is the page title, which a live page rewrites on its
        // own (unread counters, SPA routes, "Loading…"). Structural only off the web.
        if windowTitleChanged == true, webRendererSurface == false {
            intent.append(IntentSignal.windowTitleChanged.rawValue)
        }
        if targetStateChanged == true {
            intent.append(IntentSignal.targetStateChanged.rawValue)
        }
        let observedWebAreaTextChanged = webAreaTextChanged ?? webAreaTextBefore.flatMap { before in
            webAreaTextAfter.map { before != $0 }
        }
        if webRendererSurface,
           dispatchSuccess,
           webAreaBaselineStable == true,
           observedWebAreaTextChanged == true {
            intent.append(IntentSignal.webAreaTextChanged.rawValue)
        }

        var ambient: [String] = []
        if webRendererSurface,
           webAreaBaselineStable != true,
           observedWebAreaTextChanged == true {
            ambient.append(AmbientSignal.webAreaTextChanged.rawValue)
        }
        if intent.isEmpty {
            if renderedTextChanged == true {
                ambient.append(AmbientSignal.renderedTextChanged.rawValue)
            }
            if selectionSummaryChanged == true {
                ambient.append(AmbientSignal.selectionSummaryChanged.rawValue)
            }
            if windowTitleChanged == true, webRendererSurface {
                ambient.append(AmbientSignal.windowTitleChanged.rawValue)
            }
        }

        var notes: [String] = []
        if webRendererSurface, webAreaBaselineStable == false, observedWebAreaTextChanged == true {
            notes.append(unstableWebAreaBaselineNote)
        } else if webRendererSurface, webAreaBaselineStable == nil {
            notes.append(missingWebAreaBaselineNote)
        } else if webRendererSurface,
                  webAreaBaselineStable == true,
                  webAreaTextBefore != nil,
                  observedWebAreaTextChanged == nil {
            notes.append(missingPostWebAreaSampleNote)
        }
        if intent.isEmpty {
            notes.append(ambient.isEmpty ? noSignalNote : ambientOnlyNote)
        }
        return Assessment(intentSignals: intent, ambientOnlySignals: ambient, notes: notes)
    }

    /// True for notes this verifier itself appends, so a re-assessment can replace them instead of stacking.
    static func isAssessmentNote(_ note: String) -> Bool {
        note == ambientOnlyNote ||
            note == noSignalNote ||
            note == unstableWebAreaBaselineNote ||
            note == missingWebAreaBaselineNote ||
            note == missingPostWebAreaSampleNote
    }

    static func verified(_ verification: ClickVerificationEvidenceDTO?) -> Bool {
        verification?.intentSignals.isEmpty == false
    }

    static func classification(
        dispatchSuccess: Bool,
        verification: ClickVerificationEvidenceDTO?
    ) -> ActionClassificationDTO {
        dispatchSuccess && verified(verification) ? .success : .effectNotVerified
    }
}

/// Resolves the region of the window that a click was aimed at, and turns before/after window images
/// into target-local pixel evidence. A missing ratio always carries a diagnostic, never silence.
enum ClickTargetRegion {
    /// Side, in AppKit points, of the probe box used when a click has a dispatch point but no target frame.
    static let coordinateProbeSizeAppKit: Double = 48

    struct Evidence: Equatable {
        let targetRegionChangeRatio: Double?
        let fullImageChangeRatio: Double?
        let diagnostic: String?
    }

    static let unresolvedRegionDiagnostic = "No target region could be resolved for this click, so target-local pixel evidence was not computed."
    static let missingBeforeImageDiagnostic = "The window image captured before dispatch was unavailable, so target-local pixel evidence was not computed."
    static let missingAfterImageDiagnostic = "The window image captured after the settle delay was unavailable, so target-local pixel evidence was not computed."
    static let comparisonFailedDiagnostic = "Target-local pixel comparison failed for the resolved target region."

    /// Normalized, bottom-left-origin region of the window frame that the click targeted.
    static func normalizedRegion(
        targetFrameAppKit: RectDTO?,
        pointAppKit: CGPoint?,
        windowFrameAppKit: RectDTO
    ) -> CGRect? {
        let window = CGRect(
            x: windowFrameAppKit.x,
            y: windowFrameAppKit.y,
            width: windowFrameAppKit.width,
            height: windowFrameAppKit.height
        ).standardized
        guard window.width > 0, window.height > 0 else {
            return nil
        }

        let region: CGRect
        if let frame = targetFrameAppKit, frame.width > 0, frame.height > 0 {
            region = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height).standardized
        } else if let point = pointAppKit, point.x.isFinite, point.y.isFinite {
            region = CGRect(
                x: point.x - coordinateProbeSizeAppKit / 2,
                y: point.y - coordinateProbeSizeAppKit / 2,
                width: coordinateProbeSizeAppKit,
                height: coordinateProbeSizeAppKit
            )
        } else {
            return nil
        }

        let clipped = region.intersection(window)
        guard clipped.isNull == false, clipped.width > 0, clipped.height > 0 else {
            return nil
        }
        return CGRect(
            x: (clipped.minX - window.minX) / window.width,
            y: (clipped.minY - window.minY) / window.height,
            width: clipped.width / window.width,
            height: clipped.height / window.height
        )
    }

    static func evidence(
        region: CGRect?,
        before: CGImage?,
        after: CGImage?
    ) -> Evidence {
        guard let region else {
            return Evidence(
                targetRegionChangeRatio: nil,
                fullImageChangeRatio: nil,
                diagnostic: unresolvedRegionDiagnostic
            )
        }
        guard let before else {
            return Evidence(
                targetRegionChangeRatio: nil,
                fullImageChangeRatio: nil,
                diagnostic: missingBeforeImageDiagnostic
            )
        }
        guard let after else {
            return Evidence(
                targetRegionChangeRatio: nil,
                fullImageChangeRatio: nil,
                diagnostic: missingAfterImageDiagnostic
            )
        }
        guard let result = VisualChangeAnalyzer.compare(
            before: before,
            after: after,
            normalizedRegion: region
        ) else {
            return Evidence(
                targetRegionChangeRatio: nil,
                fullImageChangeRatio: nil,
                diagnostic: comparisonFailedDiagnostic
            )
        }
        return Evidence(
            targetRegionChangeRatio: result.targetRegionRatio,
            fullImageChangeRatio: result.fullImageRatio,
            diagnostic: nil
        )
    }
}

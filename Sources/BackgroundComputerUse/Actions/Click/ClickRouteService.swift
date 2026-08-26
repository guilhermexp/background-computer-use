import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private struct ClickCoordinatePlan {
    let mapping: ClickCoordinateMappingDTO
    let appKitPoint: CGPoint
    let eventTapPointTopLeft: CGPoint
}

private struct ClickCoordinateOutcome {
    let classification: ActionClassificationDTO
    let failureDomain: ActionFailureDomainDTO?
    let summary: String
    let finalRoute: ClickFinalRouteDTO
    let fallbackReason: ClickFallbackReasonDTO
    let coordinate: ClickCoordinateMappingDTO?
    let transports: [ClickTransportAttemptDTO]
    let routeSteps: [ClickRouteStepDTO]
    let postCapture: AXActionStateCapture?
    let cursor: ActionCursorTargetResponseDTO
    let frontmostBundleBeforeDispatch: String?
    let frontmostBundleAfter: String?
    let warnings: [String]
    let notes: [String]
    let verification: ClickVerificationEvidenceDTO?
}

private struct ClickSemanticOutcome {
    let classification: ActionClassificationDTO
    let failureDomain: ActionFailureDomainDTO?
    let summary: String
    let axAttempt: ClickAXAttemptDTO
    let dispatchSuccess: Bool
    let verificationSuccess: Bool
    let intentSuccess: Bool
    let coordinateFallbackAllowed: Bool
    let transport: ClickTransportAttemptDTO?
    let postCapture: AXActionStateCapture?
    let refreshedTarget: AXActionTargetSnapshot?
    let refreshedTargetStrategy: String?
    let cursor: ActionCursorTargetResponseDTO
    let frontmostBundleBeforeDispatch: String?
    let frontmostBundleAfter: String?
    let warnings: [String]
    let notes: [String]
    let verification: ClickVerificationEvidenceDTO?
}

struct ClickRouteService {
    private let executionOptions: ActionExecutionOptions
    private let targetResolver: AXActionTargetResolver
    private let settleDelay: TimeInterval = 0.35
    private let coordinateTransport = NativeBackgroundClickTransport()

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        self.executionOptions = executionOptions
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
    }

    func click(request: ClickRequest) throws -> ClickResponse {
        let requestedTarget = requestedTargetDTO(request)
        let mouseButton = request.mouseButton ?? .left
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let notes = [
            "click uses the production waterfall: semantic AX for eligible targets, then target-derived or direct coordinate dispatch through native target-only SLPS/SLEvent background click transport.",
            "perform_secondary_action remains a separate semantic route; click does not hide secondary/default-action fallbacks as pointer clicks."
        ]

        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500,
            imageMode: request.target?.kind == .ocrAnchor
                ? Self.ocrCaptureImageMode(requested: request.imageMode ?? .omit)
                : (request.imageMode ?? .omit)
        )
        let warnings = targetResolver.stateTokenWarnings(
            suppliedStateToken: request.stateToken,
            liveStateToken: capture.envelope.response.stateToken
        )

        guard mouseButton == .left else {
            return response(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: "Only left-button background click is currently implemented. Use perform_secondary_action for exposed semantic secondary actions.",
                window: capture.envelope.response.window,
                requestedTarget: requestedTarget,
                target: nil,
                clickCount: request.clickCount,
                mouseButton: mouseButton,
                finalRoute: .rejected,
                fallbackReason: .unsupportedMouseButton,
                axAttempt: nil,
                coordinate: nil,
                transports: [],
                routeSteps: [rejectedStep("mouseButton \(mouseButton.rawValue) is unsupported by the production background click transport.")],
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the requested mouse button is unsupported.",
                    options: executionOptions
                ),
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let hasTarget = request.target != nil
        let hasCompleteCoordinate = request.x != nil && request.y != nil
        let hasPartialCoordinate = (request.x != nil) != (request.y != nil)
        guard hasPartialCoordinate == false, hasTarget != hasCompleteCoordinate else {
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: "Supply exactly one target form: target or both x and y.",
                window: capture.envelope.response.window,
                requestedTarget: requestedTarget,
                target: nil,
                clickCount: request.clickCount,
                mouseButton: mouseButton,
                finalRoute: .rejected,
                fallbackReason: .invalidTarget,
                axAttempt: nil,
                coordinate: nil,
                transports: [],
                routeSteps: [rejectedStep("The request target was ambiguous or incomplete.")],
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the click target was ambiguous or incomplete.",
                    options: executionOptions
                ),
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        if let target = request.target {
            guard let clickCount = normalizedTargetClickCount(request) else {
                return invalidClickCountResponse(
                    request: request,
                    capture: capture,
                    requestedTarget: requestedTarget,
                    mouseButton: mouseButton,
                    frontmostBefore: frontmostBefore,
                    warnings: warnings,
                    notes: notes,
                    summary: "Target clickCount must be 1 or 2."
                )
            }
            if target.kind == .ocrAnchor {
                return clickOCRTarget(
                    request: request,
                    capture: capture,
                    requestedActionTarget: target,
                    clickCount: clickCount,
                    mouseButton: mouseButton,
                    frontmostBefore: frontmostBefore,
                    warnings: warnings,
                    notes: notes
                )
            }
            return try clickTarget(
                request: request,
                capture: capture,
                requestedActionTarget: target,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes
            )
        }

        guard let x = request.x, let y = request.y else {
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: "No click target was supplied.",
                window: capture.envelope.response.window,
                requestedTarget: requestedTarget,
                target: nil,
                clickCount: request.clickCount,
                mouseButton: mouseButton,
                finalRoute: .rejected,
                fallbackReason: .invalidTarget,
                axAttempt: nil,
                coordinate: nil,
                transports: [],
                routeSteps: [rejectedStep("No target or x/y coordinate was supplied.")],
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because no click target was supplied.",
                    options: executionOptions
                ),
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let clickCount: Int
        do {
            clickCount = try normalizedClickCount(request)
        } catch {
            return invalidClickCountResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedTarget,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: String(describing: error)
            )
        }

        let outcome = executeCoordinateClick(
            request: request,
            capture: capture,
            target: nil,
            x: x,
            y: y,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: .coordinateXY,
            fallbackReason: .none,
            source: "direct_model_facing_coordinate",
            inheritedTransports: [],
            inheritedSteps: [],
            warnings: warnings,
            notes: notes
        )

        return response(
            classification: outcome.classification,
            failureDomain: outcome.failureDomain,
            summary: outcome.summary,
            window: outcome.postCapture?.envelope.response.window ?? capture.envelope.response.window,
            requestedTarget: requestedTarget,
            target: nil,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: outcome.finalRoute,
            fallbackReason: outcome.fallbackReason,
            axAttempt: nil,
            coordinate: outcome.coordinate,
            transports: outcome.transports,
            routeSteps: outcome.routeSteps,
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: outcome.postCapture?.envelope.response.stateToken,
            cursor: outcome.cursor,
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: outcome.frontmostBundleBeforeDispatch,
            frontmostBundleAfter: outcome.frontmostBundleAfter,
            warnings: outcome.warnings,
            notes: outcome.notes,
            verification: outcome.verification,
            postScreenshot: postScreenshot(from: outcome.postCapture)
        )
    }

    private func clickOCRTarget(
        request: ClickRequest,
        capture: AXActionStateCapture,
        requestedActionTarget: ActionTargetRequestDTO,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?,
        warnings: [String],
        notes: [String]
    ) -> ClickResponse {
        guard clickCount == 1 else {
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: "OCR anchor clicks support a single click only.",
                fallbackReason: .invalidClickCount
            )
        }
        guard let imagePath = capture.envelope.response.screenshot.image?.imagePath else {
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: "OCR anchor resolution requires a captured screenshot image.",
                fallbackReason: .invalidTarget
            )
        }

        let liveInteractionToken = capture.envelope.response.interactionToken
        let ocr = OCRRecognitionService.recognize(
            imagePath: imagePath,
            interactionToken: liveInteractionToken
        )
        if ocr.status != .success, ocr.status != .noText {
            let diagnostic = ocr.diagnostic ?? "OCR recognition failed for the captured screenshot."
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings + [diagnostic],
                notes: notes + [diagnostic],
                summary: diagnostic,
                fallbackReason: .ocrUnavailable,
                failureDomain: .verification
            )
        }
        let resolution = OCRClickTargetResolver.resolve(
            requestedID: requestedActionTarget.value,
            suppliedInteractionToken: request.interactionToken,
            liveInteractionToken: liveInteractionToken,
            anchors: ocr.anchors
        )
        let anchor: OCRAnchorDTO
        let relocated: Bool
        switch resolution {
        case let .matched(resolvedAnchor, wasRelocated):
            anchor = resolvedAnchor
            relocated = wasRelocated
        case .staleInteractionToken:
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: "The supplied interactionToken is missing or stale; refresh get_window_state before clicking this OCR anchor.",
                fallbackReason: .staleCoordinateGuard
            )
        case .ambiguous:
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: "The OCR anchor matched multiple nearby text regions; refresh state and choose a current target.",
                fallbackReason: .invalidTarget
            )
        case .missing:
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: "The OCR anchor no longer resolves in the current screenshot.",
                fallbackReason: .invalidTarget
            )
        }

        let safetyDecision = RuntimeSafetyPolicy.evaluateLabel(anchor.text, confirmed: request.confirm == true)
        guard safetyDecision.blocked == false else {
            return ocrFailureResponse(
                request: request,
                capture: capture,
                requestedTarget: requestedActionTarget,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore,
                warnings: warnings,
                notes: notes,
                summary: safetyDecision.reason ?? "OCR click target requires explicit confirmation.",
                fallbackReason: .invalidTarget
            )
        }

        let window = capture.envelope.response.window
        let modelSize = modelPixelSize(for: capture.envelope.response)
        let anchorRegion = modelSize.width > 0 && modelSize.height > 0
            ? Self.normalizedOCRVerificationRegion(
                box: anchor.box,
                modelWidth: Double(modelSize.width),
                modelHeight: Double(modelSize.height)
            )
            : nil
        let outcome = executeCoordinateClick(
            request: request,
            capture: capture,
            target: nil,
            x: Double(anchor.x),
            y: Double(anchor.y),
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: .ocrAnchorXY,
            fallbackReason: .none,
            source: "ocr_anchor_center",
            inheritedTransports: [],
            inheritedSteps: [],
            warnings: warnings,
            notes: notes + (relocated ? ["OCR anchor was safely relocated by text, occurrence, and bounded geometry."] : []),
            verificationRegion: anchorRegion,
            postImageMode: Self.ocrCaptureImageMode(requested: request.imageMode ?? .omit)
        )
        let afterImage = outcome.postCapture.flatMap(modelFacingImage)
        let postOCR = afterImage.map {
            OCRRecognitionService.recognize(
                cgImage: $0,
                interactionToken: outcome.postCapture?.envelope.response.interactionToken ?? liveInteractionToken
            )
        }
        let anchorDisappeared: Bool?
        let anchorDiagnostic: String?
        if let postOCR {
            if postOCR.status == .success || postOCR.status == .noText {
                anchorDisappeared = OCRClickTargetResolver.isAnchorPresent(anchor, in: postOCR.anchors) == false
                anchorDiagnostic = nil
            } else {
                anchorDisappeared = nil
                anchorDiagnostic = "Anchor disappearance was not computed because post-click OCR returned status \(postOCR.status.rawValue): \(postOCR.diagnostic ?? "no diagnostic")."
            }
        } else {
            anchorDisappeared = nil
            anchorDiagnostic = "Anchor disappearance was not computed because the post-click screenshot was unavailable for OCR."
        }
        let dispatched = outcome.transports.contains { $0.didDispatch && $0.transportSuccess }
        let verification = ocrVerification(
            base: outcome.verification,
            before: capture,
            after: outcome.postCapture,
            dispatchSuccess: dispatched,
            relocated: relocated,
            anchorDisappeared: anchorDisappeared,
            anchorDiagnostic: anchorDiagnostic
        )
        let verified = dispatched && effectVerified(verification)
        var routeSteps = outcome.routeSteps
        // Rewrite the OCR pointer step, not the last one: after an accessibility
        // escalation the last step is the AXPress and its note must survive.
        if let ocrIndex = routeSteps.lastIndex(where: { $0.route == .ocrAnchorXY || $0.route == .coordinateXY }) {
            let prior = routeSteps[ocrIndex]
            let pointerVerified = verified && outcome.finalRoute != .coordinateThenAXHitTest
            routeSteps[ocrIndex] = ClickRouteStepDTO(
                route: prior.route,
                dispatchSuccess: prior.dispatchSuccess,
                verificationSuccess: pointerVerified,
                intentSuccess: pointerVerified,
                note: pointerVerified
                    ? "OCR click produced a target-local, anchor, or structural post-state effect."
                    : "OCR click dispatched, but target-local and structural verification found no effect."
            )
        }

        var responseWarnings = outcome.warnings
        if verified {
            responseWarnings.removeAll {
                $0.hasPrefix("coordinate_dispatch_effect_unconfirmed:") ||
                    $0.hasPrefix("renderer_ignores_coordinate_injection:") ||
                    $0.hasPrefix("opaque_renderer_focus_unconfirmed:") ||
                    $0.hasPrefix("This window is a web renderer surface.")
            }
        }

        return response(
            classification: verified ? .success : .effectNotVerified,
            failureDomain: verified ? nil : (dispatched ? (outcome.failureDomain ?? .verification) : (outcome.failureDomain ?? .transport)),
            summary: verified
                ? "The OCR anchor click produced a verified target-local or structural effect."
                : "The OCR anchor click dispatched, but its requested effect was not verified.",
            window: outcome.postCapture?.envelope.response.window ?? window,
            requestedTarget: requestedTargetDTO(request),
            target: nil,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: outcome.finalRoute == .coordinateThenAXHitTest ? .coordinateThenAXHitTest : .ocrAnchorXY,
            fallbackReason: outcome.fallbackReason,
            axAttempt: nil,
            coordinate: outcome.coordinate,
            transports: outcome.transports,
            routeSteps: routeSteps,
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: outcome.postCapture?.envelope.response.stateToken,
            cursor: outcome.cursor,
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: outcome.frontmostBundleBeforeDispatch,
            frontmostBundleAfter: outcome.frontmostBundleAfter,
            warnings: responseWarnings,
            notes: outcome.notes,
            verification: verification,
            postScreenshot: postScreenshot(from: outcome.postCapture)
        )
    }

    private func ocrFailureResponse(
        request: ClickRequest,
        capture: AXActionStateCapture,
        requestedTarget: ActionTargetRequestDTO,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?,
        warnings: [String],
        notes: [String],
        summary: String,
        fallbackReason: ClickFallbackReasonDTO,
        failureDomain: ActionFailureDomainDTO = .targeting
    ) -> ClickResponse {
        response(
            classification: .verifierAmbiguous,
            failureDomain: failureDomain,
            summary: summary,
            window: capture.envelope.response.window,
            requestedTarget: ClickRequestedTargetDTO(
                kind: .ocrAnchor,
                target: requestedTarget,
                x: nil,
                y: nil,
                coordinateSpace: nil
            ),
            target: nil,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: .rejected,
            fallbackReason: fallbackReason,
            axAttempt: nil,
            coordinate: nil,
            transports: [],
            routeSteps: [rejectedStep(summary)],
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: nil,
            cursor: AXCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: summary,
                options: executionOptions
            ),
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: nil,
            frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            warnings: warnings,
            notes: notes,
            verification: nil
        )
    }

    private func ocrVerification(
        base: ClickVerificationEvidenceDTO?,
        before: AXActionStateCapture,
        after: AXActionStateCapture?,
        dispatchSuccess: Bool,
        relocated: Bool,
        anchorDisappeared: Bool?,
        anchorDiagnostic: String?
    ) -> ClickVerificationEvidenceDTO {
        let assessment = ClickIntentVerifier.assess(
            focusedElementChanged: base?.focusedElementChanged,
            modalDialogOpened: base?.modalDialogOpened,
            windowTitleChanged: base?.windowTitleChanged,
            targetStateChanged: base?.targetStateChanged,
            ocrAnchorDisappeared: anchorDisappeared,
            targetRegionChangeRatio: base?.targetRegionChangeRatio,
            renderedTextChanged: base?.renderedTextChanged,
            selectionSummaryChanged: base?.selectionSummaryChanged,
            webRendererSurface: before.envelope.response.tree.profile == AXProjectionProfile.richWeb.rawValue,
            dispatchSuccess: dispatchSuccess,
            webAreaBaselineStable: base?.webAreaBaselineStable,
            webAreaTextChanged: base?.webAreaTextChanged
        )
        var notes = (base?.verificationNotes ?? []).filter { ClickIntentVerifier.isAssessmentNote($0) == false }
        notes.append("OCR verification requires anchor disappearance, target-local pixels, or structural AX evidence; unrelated full-window changes are ignored.")
        if let anchorDiagnostic {
            notes.append(anchorDiagnostic)
        }
        notes.append(contentsOf: assessment.notes)

        return ClickVerificationEvidenceDTO(
            preStateToken: before.envelope.response.stateToken,
            postStateToken: after?.envelope.response.stateToken,
            targetRelocated: relocated,
            refreshedTargetMatchStrategy: relocated ? "ocr_text_occurrence_bounded_geometry" : "ocr_anchor_id",
            beforeTargetSelected: base?.beforeTargetSelected,
            afterTargetSelected: base?.afterTargetSelected,
            beforeTargetFocused: base?.beforeTargetFocused,
            afterTargetFocused: base?.afterTargetFocused,
            beforeTargetValuePreview: base?.beforeTargetValuePreview,
            afterTargetValuePreview: base?.afterTargetValuePreview,
            beforeFocusedNodeID: base?.beforeFocusedNodeID,
            afterFocusedNodeID: base?.afterFocusedNodeID,
            renderedTextChanged: base?.renderedTextChanged,
            selectionSummaryChanged: base?.selectionSummaryChanged,
            focusedElementChanged: base?.focusedElementChanged,
            windowTitleChanged: base?.windowTitleChanged,
            modalDialogOpened: base?.modalDialogOpened,
            targetStateChanged: base?.targetStateChanged,
            webAreaTextChanged: base?.webAreaTextChanged,
            webAreaBaselineStable: base?.webAreaBaselineStable,
            webAreaBaselineDiagnostic: base?.webAreaBaselineDiagnostic,
            ocrAnchorMatched: true,
            ocrAnchorRelocated: relocated,
            ocrAnchorDisappeared: anchorDisappeared,
            targetRegionChangeRatio: base?.targetRegionChangeRatio,
            fullImageChangeRatio: base?.fullImageChangeRatio,
            foregroundPreserved: base?.foregroundPreserved,
            targetRegionChangeThreshold: ClickIntentVerifier.targetRegionChangeThreshold,
            targetRegionDiagnostic: base?.targetRegionDiagnostic,
            ocrAnchorDiagnostic: anchorDiagnostic,
            intentSignals: assessment.intentSignals,
            ambientOnlySignals: assessment.ambientOnlySignals,
            verificationNotes: notes
        )
    }

    private func clickTarget(
        request: ClickRequest,
        capture: AXActionStateCapture,
        requestedActionTarget: ActionTargetRequestDTO,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?,
        warnings: [String],
        notes: [String]
    ) throws -> ClickResponse {
        guard let candidate = targetResolver.resolveTarget(
            requestedActionTarget,
            in: capture,
            kind: .click
        ) else {
            let failureSummary = targetResolver.targetResolutionFailureDescription(
                for: requestedActionTarget,
                in: capture
            )
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: failureSummary,
                window: capture.envelope.response.window,
                requestedTarget: ClickRequestedTargetDTO(
                    kind: .semanticTarget,
                    target: requestedActionTarget,
                    x: nil,
                    y: nil,
                    coordinateSpace: nil
                ),
                target: nil,
                clickCount: clickCount,
                mouseButton: mouseButton,
                finalRoute: .rejected,
                fallbackReason: .invalidTarget,
                axAttempt: nil,
                coordinate: nil,
                transports: [],
                routeSteps: [rejectedStep(failureSummary)],
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the semantic target was not resolved.",
                    options: executionOptions
                ),
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let target = candidate.target
        let safetyDecision = RuntimeSafetyPolicy.evaluateLabel(
            [target.title, target.description, target.displayRole].compactMap { $0 }.joined(separator: " "),
            confirmed: request.confirm == true
        )
        if safetyDecision.blocked {
            return response(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: safetyDecision.reason ?? "Click target requires explicit confirmation.",
                window: capture.envelope.response.window,
                requestedTarget: ClickRequestedTargetDTO(
                    kind: .semanticTarget,
                    target: requestedActionTarget,
                    x: nil,
                    y: nil,
                    coordinateSpace: nil
                ),
                target: target,
                clickCount: clickCount,
                mouseButton: mouseButton,
                finalRoute: .rejected,
                fallbackReason: .invalidTarget,
                axAttempt: nil,
                coordinate: nil,
                transports: [],
                routeSteps: [rejectedStep(safetyDecision.reason ?? "Runtime safety policy blocked the click target.")],
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because runtime safety policy blocked the click.",
                    options: executionOptions
                ),
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }
        if clickCount > 1 {
            let outcome = executeExplicitElementPointerClick(
                request: request,
                capture: capture,
                target: target,
                clickCount: clickCount,
                mouseButton: mouseButton,
                warnings: warnings,
                notes: notes
            )
            return response(
                classification: outcome.classification,
                failureDomain: outcome.failureDomain,
                summary: outcome.summary,
                window: outcome.postCapture?.envelope.response.window ?? capture.envelope.response.window,
                requestedTarget: ClickRequestedTargetDTO(
                    kind: .semanticTarget,
                    target: requestedActionTarget,
                    x: nil,
                    y: nil,
                    coordinateSpace: nil
                ),
                target: target,
                clickCount: clickCount,
                mouseButton: mouseButton,
                finalRoute: outcome.finalRoute,
                fallbackReason: outcome.fallbackReason,
                axAttempt: .coordinateRequired,
                coordinate: outcome.coordinate,
                transports: outcome.transports,
                routeSteps: outcome.routeSteps,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: outcome.postCapture?.envelope.response.stateToken,
                cursor: outcome.cursor,
                frontmostBundleBefore: frontmostBefore,
                frontmostBundleBeforeDispatch: outcome.frontmostBundleBeforeDispatch,
                frontmostBundleAfter: outcome.frontmostBundleAfter,
                warnings: outcome.warnings,
                notes: outcome.notes,
                verification: outcome.verification,
                postScreenshot: postScreenshot(from: outcome.postCapture)
            )
        }

        let semantic = attemptSemanticAX(
            request: request,
            capture: capture,
            target: target,
            clickCount: clickCount,
            mouseButton: mouseButton,
            warnings: warnings,
            notes: notes
        )

        if clickCount == 1 {
            if semantic.intentSuccess {
                return semanticResponse(
                    semantic,
                    request: request,
                    capture: capture,
                    target: target,
                    clickCount: clickCount,
                    mouseButton: mouseButton,
                    frontmostBefore: frontmostBefore
                )
            }

            if semantic.coordinateFallbackAllowed {
                let fallback = executeElementPointerFallback(
                    request: request,
                    capture: capture,
                    target: semantic.refreshedTarget ?? target,
                    clickCount: 1,
                    mouseButton: mouseButton,
                    finalRoute: .axElementPointerXY,
                    fallbackReason: .axCoordinateRequired,
                    semantic: semantic,
                    warnings: semantic.warnings,
                    notes: semantic.notes
                )
                return coordinateFallbackResponse(
                    fallback,
                    semantic: semantic,
                    request: request,
                    capture: capture,
                    target: target,
                    clickCount: clickCount,
                    mouseButton: mouseButton,
                    frontmostBefore: frontmostBefore
                )
            }

            return semanticResponse(
                semantic,
                request: request,
                capture: capture,
                target: target,
                clickCount: clickCount,
                mouseButton: mouseButton,
                frontmostBefore: frontmostBefore
            )
        }

        preconditionFailure("normalized single/double click count escaped click routing")
    }

    private func attemptSemanticAX(
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        warnings: [String],
        notes: [String]
    ) -> ClickSemanticOutcome {
        var warnings = warnings
        var notes = notes
        notes.append("Semantic target click attempted the AX lane before pointer fallback.")

        let liveElement: AXActionResolvedLiveElement
        do {
            liveElement = try targetResolver.resolveLiveElement(for: target, in: capture)
        } catch {
            return ClickSemanticOutcome(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: String(describing: error),
                axAttempt: .unsupportedPrimaryClick,
                dispatchSuccess: false,
                verificationSuccess: false,
                intentSuccess: false,
                coordinateFallbackAllowed: targetHasUsablePoint(target, window: capture.envelope.response.window),
                transport: nil,
                postCapture: nil,
                refreshedTarget: nil,
                refreshedTargetStrategy: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the live AX click target could not be resolved.",
                    options: executionOptions
                ),
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let plan = planSemanticAXClick(target: target, liveElement: liveElement.element)
        guard plan.dispatches else {
            let summary: String
            switch plan.attempt {
            case .coordinateRequired:
                summary = "The target requires a target-derived pointer click; no exact semantic AX primary-click strategy applied."
            case .ambiguousDescendantClick:
                summary = "The element contained multiple possible primary-click descendants, so semantic AX retargeting was rejected."
            default:
                summary = "No generic semantic AX primary-click strategy applied to the target."
            }
            return ClickSemanticOutcome(
                classification: .effectNotVerified,
                failureDomain: .unsupported,
                summary: summary,
                axAttempt: plan.attempt,
                dispatchSuccess: false,
                verificationSuccess: false,
                intentSuccess: false,
                coordinateFallbackAllowed: targetHasUsablePoint(target, window: capture.envelope.response.window),
                transport: nil,
                postCapture: nil,
                refreshedTarget: nil,
                refreshedTargetStrategy: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was deferred to the pointer fallback because the semantic AX lane did not dispatch.",
                    options: executionOptions
                ),
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes + plan.notes,
                verification: nil
            )
        }

        let cursor = AXCursorTargeting.prepareClick(
            requested: request.cursor,
            target: target,
            window: capture.envelope.response.window,
            options: executionOptions
        )
        warnings.append(contentsOf: cursor.warnings)
        let region = ClickTargetRegion.normalizedRegion(
            targetFrameAppKit: target.frameAppKit,
            pointAppKit: AXCursorTargeting.targetPoint(for: target, window: capture.envelope.response.window).point,
            windowFrameAppKit: capture.envelope.response.window.frameAppKit
        )
        let beforeWindowImage = CGWindowCaptureService.captureImage(
            window: capture.envelope.response.window,
            attachedSurfaces: capture.envelope.response.attachedSurfaces
        )
        let webAreaBaseline = sampleWebAreaTextBaseline(before: capture)
        let frontmostBeforeDispatch = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let dispatch = dispatchSemanticPlan(plan)
        let rawStatus = dispatch.rawStatus
        AXCursorTargeting.finishClick(cursor: cursor)
        sleepRunLoop(settleDelay)

        let postCapture: AXActionStateCapture?
        do {
            postCapture = try targetResolver.reread(after: capture, imageMode: request.imageMode ?? .omit)
        } catch {
            postCapture = nil
            warnings.append("Post-click reread failed after semantic AX dispatch: \(error).")
        }
        let refreshed = postCapture.flatMap {
            targetResolver.locateRefreshedTarget(in: $0, prior: target, kind: .click)
        }
        let afterWindowImage = CGWindowCaptureService.captureImage(
            window: postCapture?.envelope.response.window ?? capture.envelope.response.window,
            attachedSurfaces: postCapture?.envelope.response.attachedSurfaces ?? capture.envelope.response.attachedSurfaces
        )
        let verification = verifyClick(
            before: capture,
            after: postCapture,
            target: target,
            refreshedTarget: refreshed?.target,
            refreshedTargetStrategy: refreshed?.strategy,
            foregroundBeforeDispatch: frontmostBeforeDispatch,
            foregroundAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            dispatchSuccess: dispatch.success,
            webAreaBaseline: webAreaBaseline,
            region: ClickTargetRegion.evidence(
                region: region,
                before: beforeWindowImage,
                after: afterWindowImage
            ),
            extraNotes: dispatch.notes + plan.notes
        )
        let verified = semanticVerified(plan: plan, dispatchSuccess: dispatch.success, verification: verification)
        let classification: ActionClassificationDTO = verified ? .success : .effectNotVerified
        let failureDomain: ActionFailureDomainDTO? = verified ? nil : (dispatch.success ? .verification : .transport)
        let transport = ClickTransportAttemptDTO(
            route: plan.transportRoute,
            axAttempt: plan.attempt,
            dispatchPrimitive: plan.dispatchPrimitive,
            rawStatus: rawStatus,
            transportSuccess: dispatch.success,
            didDispatch: true,
            clickCount: min(clickCount, 1),
            mouseButton: mouseButton,
            targetPointAppKit: cursor.targetPointAppKit,
            eventTapPointTopLeft: cursor.targetPointAppKit.map { PointDTO(x: $0.x, y: DesktopGeometry.desktopTop() - $0.y) },
            eventsPrepared: nil,
            targetPID: capture.envelope.response.window.pid,
            targetWindowNumber: capture.envelope.response.window.windowNumber,
            liveElementResolution: liveElement.resolution,
            notes: dispatch.notes + plan.notes
        )

        return ClickSemanticOutcome(
            classification: classification,
            failureDomain: failureDomain,
            summary: verified
                ? "The semantic AX click lane produced a verified primary-click effect using \(plan.attempt.rawValue)."
                : "The semantic AX click lane dispatched \(plan.attempt.rawValue), but the requested effect was not verified.",
            axAttempt: plan.attempt,
            dispatchSuccess: dispatch.success,
            verificationSuccess: verified,
            intentSuccess: verified,
            coordinateFallbackAllowed: plan.attempt == .exactPrimaryAXAction
                ? dispatch.success == false && targetHasUsablePoint(target, window: capture.envelope.response.window)
                : targetHasUsablePoint(target, window: capture.envelope.response.window),
            transport: transport,
            postCapture: postCapture,
            refreshedTarget: refreshed?.target,
            refreshedTargetStrategy: refreshed?.strategy,
            cursor: cursor,
            frontmostBundleBeforeDispatch: frontmostBeforeDispatch,
            frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            warnings: warnings,
            notes: notes,
            verification: verification
        )
    }

    private func executeElementPointerFallback(
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        finalRoute: ClickFinalRouteDTO,
        fallbackReason: ClickFallbackReasonDTO,
        semantic: ClickSemanticOutcome,
        warnings: [String],
        notes: [String]
    ) -> ClickCoordinateOutcome {
        guard let plan = coordinatePlan(for: target, window: capture.envelope.response.window) else {
            let cursor = AXCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because the target had no stable element-derived coordinate.",
                    options: executionOptions
            )
            return ClickCoordinateOutcome(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: "The AX target did not include a stable visible frame or activation point for element-derived pointer fallback.",
                finalRoute: .rejected,
                fallbackReason: .missingStableAXCoordinate,
                coordinate: nil,
                transports: semantic.transport.map { [$0] } ?? [],
                routeSteps: semanticStep(semantic) + [rejectedStep("Missing stable AX coordinate for pointer fallback.")],
                postCapture: nil,
                cursor: cursor,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings + cursor.warnings,
                notes: notes,
                verification: semantic.verification
            )
        }

        return executeCoordinateClick(
            request: request,
            capture: capture,
            target: target,
            plan: plan,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: finalRoute,
            fallbackReason: fallbackReason,
            source: "element_derived_pointer_coordinate",
            inheritedTransports: semantic.transport.map { [$0] } ?? [],
            inheritedSteps: semanticStep(semantic),
            warnings: warnings,
            notes: notes
        )
    }

    private func executeCoordinateClick(
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot?,
        x: Double,
        y: Double,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        finalRoute: ClickFinalRouteDTO,
        fallbackReason: ClickFallbackReasonDTO,
        source: String,
        inheritedTransports: [ClickTransportAttemptDTO],
        inheritedSteps: [ClickRouteStepDTO],
        warnings: [String],
        notes: [String],
        verificationRegion: CGRect? = nil,
        postImageMode: ImageMode? = nil
    ) -> ClickCoordinateOutcome {
        let modelSize = modelPixelSize(for: capture.envelope.response)
        guard let plan = coordinatePlan(
            x: x,
            y: y,
            modelSize: modelSize,
            window: capture.envelope.response.window,
            source: source
        ) else {
            let cursor = AXCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because the model-facing coordinate was invalid or outside the current window screenshot bounds.",
                    options: executionOptions
            )
            return ClickCoordinateOutcome(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: "The model-facing coordinate was invalid or outside the current window screenshot bounds.",
                finalRoute: .rejected,
                fallbackReason: .invalidTarget,
                coordinate: nil,
                transports: inheritedTransports,
                routeSteps: inheritedSteps + [rejectedStep("Invalid model-facing x/y coordinate.")],
                postCapture: nil,
                cursor: cursor,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings + cursor.warnings,
                notes: notes,
                verification: nil
            )
        }
        return executeCoordinateClick(
            request: request,
            capture: capture,
            target: target,
            plan: plan,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: finalRoute,
            fallbackReason: fallbackReason,
            source: source,
            inheritedTransports: inheritedTransports,
            inheritedSteps: inheritedSteps,
            warnings: warnings,
            notes: notes,
            verificationRegion: verificationRegion,
            postImageMode: postImageMode
        )
    }

    private func executeCoordinateClick(
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot?,
        plan: ClickCoordinatePlan,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        finalRoute: ClickFinalRouteDTO,
        fallbackReason: ClickFallbackReasonDTO,
        source: String,
        inheritedTransports: [ClickTransportAttemptDTO],
        inheritedSteps: [ClickRouteStepDTO],
        warnings: [String],
        notes: [String],
        verificationRegion: CGRect? = nil,
        postImageMode: ImageMode? = nil
    ) -> ClickCoordinateOutcome {
        var warnings = warnings + plan.mapping.warnings
        var notes = notes
        let cursor = AXCursorTargeting.prepareClick(
            requested: request.cursor,
            pointAppKit: plan.appKitPoint,
            targetPointSource: plan.mapping.targetPointSource,
            window: capture.envelope.response.window,
            options: executionOptions
        )
        warnings.append(contentsOf: cursor.warnings)

        let region = verificationRegion ?? ClickTargetRegion.normalizedRegion(
            targetFrameAppKit: target?.frameAppKit,
            pointAppKit: plan.appKitPoint,
            windowFrameAppKit: capture.envelope.response.window.frameAppKit
        )
        let beforeWindowImage = CGWindowCaptureService.captureImage(
            window: capture.envelope.response.window,
            attachedSurfaces: capture.envelope.response.attachedSurfaces
        )
        let webAreaBaseline = sampleWebAreaTextBaseline(before: capture)

        let frontmostBeforeDispatch = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let transportResult: NativeBackgroundClickTransportResult
        do {
            let routing = try NativeWindowServerRoutingResolver().resolve(windowNumber: capture.envelope.response.window.windowNumber)
            notes.append(contentsOf: routing.notes)
            transportResult = try coordinateTransport.dispatch(
                NativeBackgroundClickDispatchRequest(
                    target: RoutedClickTarget(window: capture.envelope.response.window, routing: routing),
                    eventTapPointTopLeft: plan.eventTapPointTopLeft,
                    appKitPoint: plan.appKitPoint,
                    clickCount: clickCount,
                    mouseButton: mouseButton
                )
            )
        } catch {
            AXCursorTargeting.finishClick(cursor: cursor)
            let transport = ClickTransportAttemptDTO(
                route: .nativeBackgroundCoordinate,
                axAttempt: nil,
                dispatchPrimitive: "SLPSPostEventRecordTo target-only focus + SLEventPostToPid mouse sequence",
                rawStatus: String(describing: error),
                transportSuccess: false,
                didDispatch: false,
                clickCount: clickCount,
                mouseButton: mouseButton,
                targetPointAppKit: plan.mapping.targetPointAppKit,
                eventTapPointTopLeft: plan.mapping.eventTapPointTopLeft,
                eventsPrepared: nil,
                targetPID: capture.envelope.response.window.pid,
                targetWindowNumber: capture.envelope.response.window.windowNumber,
                liveElementResolution: nil,
                notes: ["Coordinate click transport failed before dispatch: \(error)."]
            )
            return ClickCoordinateOutcome(
                classification: .effectNotVerified,
                failureDomain: .transport,
                summary: "The coordinate click transport failed before it could dispatch.",
                finalRoute: finalRoute,
                fallbackReason: .transportFailed,
                coordinate: plan.mapping,
                transports: inheritedTransports + [transport],
                routeSteps: inheritedSteps + [
                    ClickRouteStepDTO(
                        route: finalRoute,
                        dispatchSuccess: false,
                        verificationSuccess: false,
                        intentSuccess: false,
                        note: "Coordinate transport failed before dispatch."
                    )
                ],
                postCapture: nil,
                cursor: cursor,
                frontmostBundleBeforeDispatch: frontmostBeforeDispatch,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        AXCursorTargeting.finishClick(cursor: cursor)
        sleepRunLoop(settleDelay)
        var postCapture: AXActionStateCapture?
        do {
            postCapture = try targetResolver.reread(after: capture, imageMode: postImageMode ?? request.imageMode ?? .omit)
        } catch {
            postCapture = nil
            warnings.append("Post-click reread failed after coordinate dispatch: \(error).")
        }
        let refreshed = target.flatMap { prior in
            postCapture.flatMap {
                targetResolver.locateRefreshedTarget(in: $0, prior: prior, kind: .click)
            }
        }
        let frontmostAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let afterWindowImage = CGWindowCaptureService.captureImage(
            window: postCapture?.envelope.response.window ?? capture.envelope.response.window,
            attachedSurfaces: postCapture?.envelope.response.attachedSurfaces ?? capture.envelope.response.attachedSurfaces
        )
        let regionEvidence = ClickTargetRegion.evidence(
            region: region,
            before: beforeWindowImage,
            after: afterWindowImage
        )
        var verification = verifyClick(
            before: capture,
            after: postCapture,
            target: target,
            refreshedTarget: refreshed?.target,
            refreshedTargetStrategy: refreshed?.strategy,
            foregroundBeforeDispatch: frontmostBeforeDispatch,
            foregroundAfter: frontmostAfter,
            dispatchSuccess: transportResult.dispatchSuccess,
            webAreaBaseline: webAreaBaseline,
            region: regionEvidence,
            extraNotes: transportResult.notes
        )
        var verified = transportResult.dispatchSuccess && effectVerified(verification)
        var finalRoute = finalRoute
        var fallbackReason = fallbackReason
        var escalationTransport: ClickTransportAttemptDTO?
        var escalationStep: ClickRouteStepDTO?

        // Escalate only when the click provably did nothing. A slow but real effect
        // (form submit, navigation, network round trip) is not visible inside the
        // settle delay, and pressing again there would actuate a second time.
        let windowStillSettling = verification.ambientOnlySignals.isEmpty == false
            || (regionEvidence.fullImageChangeRatio ?? 0) > 0
        let escalation = transportResult.dispatchSuccess && verified == false && windowStillSettling == false
            ? pressAXElement(
                underPointTopLeft: plan.eventTapPointTopLeft,
                pid: Int32(capture.envelope.response.window.pid),
                confirmed: request.confirm == true
            )
            : .none

        if case let .requiresConfirmation(reason) = escalation {
            warnings.append(
                "The coordinate dispatch proved no effect and the accessibility element under the point was not pressed: \(reason)"
            )
        }

        if case let .pressed(press) = escalation {
            sleepRunLoop(settleDelay)
            let escalatedCapture = try? targetResolver.reread(
                after: capture,
                imageMode: postImageMode ?? request.imageMode ?? .omit
            )
            let escalatedWindow = escalatedCapture?.envelope.response.window ?? capture.envelope.response.window
            let escalatedRegion = ClickTargetRegion.evidence(
                region: region,
                before: beforeWindowImage,
                after: CGWindowCaptureService.captureImage(
                    window: escalatedWindow,
                    attachedSurfaces: escalatedCapture?.envelope.response.attachedSurfaces
                        ?? capture.envelope.response.attachedSurfaces
                )
            )
            let escalatedRefreshed = target.flatMap { prior in
                escalatedCapture.flatMap {
                    targetResolver.locateRefreshedTarget(in: $0, prior: prior, kind: .click)
                }
            }
            let escalatedVerification = verifyClick(
                before: capture,
                after: escalatedCapture,
                target: target,
                refreshedTarget: escalatedRefreshed?.target,
                refreshedTargetStrategy: escalatedRefreshed?.strategy,
                foregroundBeforeDispatch: frontmostBeforeDispatch,
                foregroundAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                dispatchSuccess: press.succeeded,
                webAreaBaseline: webAreaBaseline,
                region: escalatedRegion,
                extraNotes: [
                    "Coordinate dispatch proved no effect; pressed the accessibility element under the same point (role=\(press.role ?? "unknown"), label=\(press.label.isEmpty ? "none" : press.label), AXPress status=\(press.status.rawValue))."
                ]
            )
            let escalationVerified = press.succeeded && effectVerified(escalatedVerification)
            escalationTransport = ClickTransportAttemptDTO(
                route: .axPerformAction,
                axAttempt: .exactPrimaryAXAction,
                dispatchPrimitive: "AXUIElementCopyElementAtPosition + AXPress",
                rawStatus: press.succeeded ? "performed" : "ax_error_\(press.status.rawValue)",
                transportSuccess: press.succeeded,
                didDispatch: press.succeeded,
                clickCount: 1,
                mouseButton: mouseButton,
                targetPointAppKit: plan.mapping.targetPointAppKit,
                eventTapPointTopLeft: plan.mapping.eventTapPointTopLeft,
                eventsPrepared: nil,
                targetPID: capture.envelope.response.window.pid,
                targetWindowNumber: capture.envelope.response.window.windowNumber,
                liveElementResolution: "ax_hit_test_at_click_point",
                notes: [
                    "Hit-tested element role=\(press.role ?? "unknown") label=\(press.label.isEmpty ? "none" : press.label) frame=\(press.frameTopLeft).",
                    "Coordinate injection is not honored by every renderer; the accessibility action addresses the same point."
                ]
            )
            escalationStep = ClickRouteStepDTO(
                route: .coordinateThenAXHitTest,
                dispatchSuccess: press.succeeded,
                verificationSuccess: escalationVerified,
                intentSuccess: escalationVerified,
                note: escalationVerified
                    ? "Accessibility press at the click point produced a verified effect after the coordinate dispatch proved none."
                    : "Accessibility press at the click point also failed to prove an effect."
            )
            // The press already mutated the app, so the caller must receive the state
            // that followed it — never a snapshot that predates an action this
            // runtime performed. Escalation only runs on an unverified click, so
            // adopting the escalated verification can never downgrade a verdict.
            verification = escalatedVerification
            postCapture = escalatedCapture ?? postCapture
            if escalationVerified {
                verified = true
                finalRoute = .coordinateThenAXHitTest
                fallbackReason = .coordinateUnverifiedUsingAXHitTest
            }
        }

        let classification: ActionClassificationDTO = verified ? .success : .effectNotVerified
        let failureDomain: ActionFailureDomainDTO? = verified
            ? nil
            : (transportResult.dispatchSuccess ? .appSpecificSemantics : .transport)
        if transportResult.dispatchSuccess && verified == false {
            let diagnostic = capture.envelope.response.tree.profile == AXProjectionProfile.richWeb.rawValue
                ? "renderer_ignores_coordinate_injection"
                : "coordinate_dispatch_effect_unconfirmed"
            warnings.append(
                "\(diagnostic): native coordinate events were posted, but no target-local or structural post-state effect was observed."
            )
            if diagnostic == "renderer_ignores_coordinate_injection" {
                warnings.append(
                    "This window is a web renderer surface. Measured 2026-08-04: Chromium discards the pid-directed synthetic mouse events this route posts, and no accessibility element under the point accepted a press either. Use target.kind=display_index or node_id for a control the accessibility tree exposes."
                )
            }
        }
        let transport = ClickTransportAttemptDTO(
            route: .nativeBackgroundCoordinate,
            axAttempt: nil,
            dispatchPrimitive: "SLPSPostEventRecordTo target-only focus + SLEventPostToPid mouse sequence",
            rawStatus: transportResult.dispatchSuccess ? "posted" : "not_posted",
            transportSuccess: transportResult.dispatchSuccess,
            didDispatch: transportResult.dispatchSuccess,
            clickCount: clickCount,
            mouseButton: mouseButton,
            targetPointAppKit: plan.mapping.targetPointAppKit,
            eventTapPointTopLeft: plan.mapping.eventTapPointTopLeft,
            eventsPrepared: transportResult.eventsPrepared,
            targetPID: transportResult.targetPID,
            targetWindowNumber: transportResult.targetWindowNumber,
            liveElementResolution: nil,
            notes: transportResult.notes
        )
        // The coordinate step records what the coordinate injection itself achieved.
        // Labelling it with the post-escalation verdict would claim the injection
        // worked on renderers where it provably does not.
        let coordinateVerified = verified && finalRoute != .coordinateThenAXHitTest
        let step = ClickRouteStepDTO(
            route: finalRoute == .coordinateThenAXHitTest ? .coordinateXY : finalRoute,
            dispatchSuccess: transportResult.dispatchSuccess,
            verificationSuccess: coordinateVerified,
            intentSuccess: coordinateVerified,
            note: coordinateVerified
                ? "Coordinate click produced a verified post-state effect."
                : "Coordinate click dispatched, but post-state verification did not prove an effect."
        )

        return ClickCoordinateOutcome(
            classification: classification,
            failureDomain: failureDomain,
            summary: verified
                ? (finalRoute == .coordinateThenAXHitTest
                    ? "The coordinate dispatch proved no effect, so the accessibility element under the same point was pressed and that produced a verified effect."
                    : "The coordinate click produced a verified post-state effect.")
                : "The coordinate click dispatched through the native background click transport, but the requested effect was not verified.",
            finalRoute: finalRoute,
            fallbackReason: fallbackReason,
            coordinate: plan.mapping,
            transports: inheritedTransports + [transport] + (escalationTransport.map { [$0] } ?? []),
            routeSteps: inheritedSteps + [step] + (escalationStep.map { [$0] } ?? []),
            postCapture: postCapture,
            cursor: cursor,
            frontmostBundleBeforeDispatch: frontmostBeforeDispatch,
            frontmostBundleAfter: frontmostAfter,
            warnings: warnings,
            notes: notes,
            verification: verification
        )
    }

    private func executeExplicitElementPointerClick(
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        warnings: [String],
        notes: [String]
    ) -> ClickCoordinateOutcome {
        var notes = notes
        notes.append("Explicit target multi-click bypassed semantic AX so native pointer events can dispatch back-to-back with no verification gap.")
        guard let plan = coordinatePlan(for: target, window: capture.envelope.response.window) else {
            let cursor = AXCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because the target had no stable element-derived coordinate.",
                    options: executionOptions
            )
            return ClickCoordinateOutcome(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: "The AX target did not include a stable visible frame or activation point for explicit element multi-click.",
                finalRoute: .rejected,
                fallbackReason: .missingStableAXCoordinate,
                coordinate: nil,
                transports: [],
                routeSteps: [
                    ClickRouteStepDTO(
                        route: .axElementPointerXY,
                        dispatchSuccess: false,
                        verificationSuccess: false,
                        intentSuccess: false,
                        note: "Explicit element multi-click could not resolve a stable pointer coordinate."
                    )
                ],
                postCapture: nil,
                cursor: cursor,
                frontmostBundleBeforeDispatch: nil,
                frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                warnings: warnings + cursor.warnings,
                notes: notes,
                verification: nil
            )
        }

        return executeCoordinateClick(
            request: request,
            capture: capture,
            target: target,
            plan: plan,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: .axElementPointerXY,
            fallbackReason: .axMultiClickRequiresXY,
            source: "element_derived_pointer_coordinate_explicit_multi_click",
            inheritedTransports: [],
            inheritedSteps: [],
            warnings: warnings,
            notes: notes
        )
    }

    private struct SemanticPlan {
        let attempt: ClickAXAttemptDTO
        let dispatches: Bool
        let dispatchElement: AXUIElement?
        let containerElement: AXUIElement?
        let actionName: String?
        let transportRoute: ClickTransportRouteDTO
        let dispatchPrimitive: String
        let notes: [String]
    }

    private func planSemanticAXClick(
        target: AXActionTargetSnapshot,
        liveElement: AXUIElement
    ) -> SemanticPlan {
        if let action = exactPrimaryAction(for: liveElement) {
            return SemanticPlan(
                attempt: .exactPrimaryAXAction,
                dispatches: true,
                dispatchElement: liveElement,
                containerElement: nil,
                actionName: action,
                transportRoute: .axPerformAction,
                dispatchPrimitive: "AXUIElementPerformAction(\(action))",
                notes: ["Target itself exposes eligible primary AX action \(action)."]
            )
        }

        if let row = rowElement(startingAt: liveElement),
           isInsideWebArea(row) == false {
            if let container = selectableRowsContainer(for: row) {
                return SemanticPlan(
                    attempt: .setContainerSelectedRows,
                    dispatches: true,
                    dispatchElement: row,
                    containerElement: container,
                    actionName: nil,
                    transportRoute: .axSetSelectedRows,
                    dispatchPrimitive: "AXUIElementSetAttributeValue(AXSelectedRows)",
                    notes: ["Using native collection selection through AXSelectedRows on the row container."]
                )
            }
            if AXActionRuntimeSupport.isAttributeSettable(row, attribute: kAXSelectedAttribute as CFString) {
                return SemanticPlan(
                    attempt: .setRowSelectedTrue,
                    dispatches: true,
                    dispatchElement: row,
                    containerElement: nil,
                    actionName: nil,
                    transportRoute: .axSetSelected,
                    dispatchPrimitive: "AXUIElementSetAttributeValue(kAXSelectedAttribute)",
                    notes: ["Using row AXSelected=true because no AXSelectedRows container was available."]
                )
            }
        }

        let descendant = safeUniqueDescendantRetarget(target: target, liveElement: liveElement)
        if let descendant {
            return SemanticPlan(
                attempt: .safeUniqueDescendantRetarget,
                dispatches: true,
                dispatchElement: descendant,
                containerElement: nil,
                actionName: kAXPressAction as String,
                transportRoute: .axPerformAction,
                dispatchPrimitive: "AXUIElementPerformAction(kAXPressAction)",
                notes: ["Retargeted wrapper to one safe actionable descendant."]
            )
        }

        if ambiguousActionableDescendantCount(liveElement) > 1 {
            return SemanticPlan(
                attempt: .ambiguousDescendantClick,
                dispatches: false,
                dispatchElement: nil,
                containerElement: nil,
                actionName: nil,
                transportRoute: .axPerformAction,
                dispatchPrimitive: "none",
                notes: ["Rejected semantic descendant retargeting because multiple actionable descendants were present."]
            )
        }

        if targetHasUsablePoint(target, window: nil) {
            return SemanticPlan(
                attempt: .coordinateRequired,
                dispatches: false,
                dispatchElement: nil,
                containerElement: nil,
                actionName: nil,
                transportRoute: .nativeBackgroundCoordinate,
                dispatchPrimitive: "none",
                notes: ["Returning coordinate_required rather than using app-specific, secondary, menu, or default-action fallback."]
            )
        }

        return SemanticPlan(
            attempt: .unsupportedPrimaryClick,
            dispatches: false,
            dispatchElement: nil,
            containerElement: nil,
            actionName: nil,
            transportRoute: .axPerformAction,
            dispatchPrimitive: "none",
            notes: ["No generic primary AX click strategy applies."]
        )
    }

    private func dispatchSemanticPlan(_ plan: SemanticPlan) -> (success: Bool, rawStatus: String, notes: [String]) {
        switch plan.attempt {
        case .exactPrimaryAXAction, .safeUniqueDescendantRetarget:
            guard let actionName = plan.actionName, let element = plan.dispatchElement else {
                return (false, "missing_dispatch_target", ["Missing AX action or dispatch element."])
            }
            let result = AXActionRuntimeSupport.performAction(actionName, on: element)
            return (
                result == .success,
                AXActionRuntimeSupport.rawStatusString(for: result),
                ["AXUIElementPerformAction(\(actionName)) returned \(AXActionRuntimeSupport.rawStatusString(for: result))."]
            )

        case .setContainerSelectedRows:
            guard let row = plan.dispatchElement, let container = plan.containerElement else {
                return (false, "missing_dispatch_target", ["Missing row/container for AXSelectedRows."])
            }
            let rows = [row] as CFArray
            let result = AXUIElementSetAttributeValue(container, "AXSelectedRows" as CFString, rows)
            return (
                result == .success,
                AXActionRuntimeSupport.rawStatusString(for: result),
                ["AXUIElementSetAttributeValue(container, AXSelectedRows=[targetRow]) returned \(AXActionRuntimeSupport.rawStatusString(for: result))."]
            )

        case .setRowSelectedTrue:
            guard let row = plan.dispatchElement else {
                return (false, "missing_dispatch_target", ["Missing row for AXSelected=true."])
            }
            let result = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            return (
                result == .success,
                AXActionRuntimeSupport.rawStatusString(for: result),
                ["AXUIElementSetAttributeValue(row, AXSelected=true) returned \(AXActionRuntimeSupport.rawStatusString(for: result))."]
            )

        case .ambiguousDescendantClick, .coordinateRequired, .unsupportedPrimaryClick, .none:
            return (false, "not_dispatched", ["Semantic AX planner produced \(plan.attempt.rawValue); no AX mutation was sent."])
        }
    }

    private func exactPrimaryAction(for element: AXUIElement) -> String? {
        let actions = Set(AXActionRuntimeSupport.actionNames(element))
        let role = AXActionRuntimeSupport.stringAttribute(element, attribute: kAXRoleAttribute as CFString)
        let enabled = AXActionRuntimeSupport.boolAttribute(element, attribute: kAXEnabledAttribute as CFString)
        if enabled == false {
            return nil
        }
        if actions.contains(kAXPressAction as String), isExactPressRole(role) {
            return kAXPressAction as String
        }
        if actions.contains(kAXPickAction as String), ["AXPopUpButton", "AXMenuButton"].contains(role ?? "") {
            return kAXPickAction as String
        }
        return nil
    }

    private func isExactPressRole(_ role: String?) -> Bool {
        [
            "AXButton",
            "AXLink",
            "AXCheckBox",
            "AXRadioButton",
            "AXPopUpButton",
            "AXDisclosureTriangle",
            "AXSlider",
            "AXSwitch",
        ].contains(role ?? "")
    }

    private func rowElement(startingAt element: AXUIElement) -> AXUIElement? {
        for candidate in AXActionRuntimeSupport.walkAncestors(startingAt: element, maxDepth: 8) {
            let role = AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString)
            let subrole = AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXSubroleAttribute as CFString)
            if ["AXRow", "AXOutlineRow", "AXTableRow"].contains(role ?? "") ||
                ["AXOutlineRow", "AXTableRow"].contains(subrole ?? "") {
                return candidate
            }
        }
        return nil
    }

    private func isInsideWebArea(_ element: AXUIElement) -> Bool {
        AXActionRuntimeSupport.walkAncestors(startingAt: element, maxDepth: 12).contains { candidate in
            AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString) == "AXWebArea"
        }
    }

    private func selectableRowsContainer(for row: AXUIElement) -> AXUIElement? {
        for candidate in AXActionRuntimeSupport.walkAncestors(startingAt: row, maxDepth: 10).dropFirst() {
            let role = AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString)
            if ["AXOutline", "AXTable", "AXList", "AXBrowser"].contains(role ?? ""),
               AXActionRuntimeSupport.isAttributeSettable(candidate, attribute: "AXSelectedRows" as CFString) {
                return candidate
            }
        }
        return nil
    }

    private func safeUniqueDescendantRetarget(
        target: AXActionTargetSnapshot,
        liveElement: AXUIElement
    ) -> AXUIElement? {
        guard isSafeDescendantRetargetContainer(liveElement) else {
            return nil
        }
        let actionable = actionableDescendants(liveElement)
        guard actionable.isEmpty == false else {
            return nil
        }

        let targetLabels = [
            target.title,
            target.description,
            target.projectedValuePreview,
            target.url,
        ]
        .compactMap { normalizeText($0) }
        .filter { $0.isEmpty == false }

        let matching = actionable.filter { element in
            let label = normalizeText(label(for: element))
            guard label.isEmpty == false else {
                return false
            }
            return targetLabels.contains { targetLabel in
                targetLabel.contains(label) || label.contains(targetLabel)
            }
        }
        if matching.count == 1 {
            return matching[0]
        }
        if actionable.count == 1, matching.isEmpty, targetLabels.isEmpty == false {
            return nil
        }
        return actionable.count == 1 ? actionable[0] : nil
    }

    private func ambiguousActionableDescendantCount(_ element: AXUIElement) -> Int {
        actionableDescendants(element).count
    }

    private func actionableDescendants(_ element: AXUIElement) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var queue = AXActionRuntimeSupport.childElements(element).map { ($0, 1) }
        while queue.isEmpty == false {
            let (candidate, depth) = queue.removeFirst()
            let role = AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString)
            let actions = AXActionRuntimeSupport.actionNames(candidate)
            let enabled = AXActionRuntimeSupport.boolAttribute(candidate, attribute: kAXEnabledAttribute as CFString)
            if actions.contains(kAXPressAction as String),
               ["AXLink", "AXButton", "AXCheckBox", "AXRadioButton", "AXGroup"].contains(role ?? ""),
               enabled != false {
                results.append(candidate)
            }
            if depth < 5 {
                queue.append(contentsOf: AXActionRuntimeSupport.childElements(candidate).map { ($0, depth + 1) })
            }
        }
        return results
    }

    /// Result of pressing the accessibility element that sits under a screen point.
    private struct AXPointPressResult {
        let role: String?
        let label: String
        let frameTopLeft: CGRect
        let status: AXError

        var succeeded: Bool { status == .success }
    }

    /// What the escalation did, or why it refused to act.
    private enum AXPointPressOutcome {
        case pressed(AXPointPressResult)
        /// A pressable element under the point carries destructive wording.
        case requiresConfirmation(String)
        case none
    }

    /// Presses the accessibility element under `pointTopLeft`.
    ///
    /// Measured on 2026-08-04: Chromium ignores the pid-directed synthetic mouse
    /// events this transport posts (`SLEventPostToPid`) — the same events posted to
    /// the global HID tap do click, and AX targeting on the same control works. So
    /// when a coordinate or OCR-anchor click dispatches without proving an effect,
    /// the point itself is still the best description of intent: hit-test it and use
    /// the accessibility action, instead of leaving the caller with a silent no-op.
    ///
    /// The escalation performs the same primitive as the semantic route, so it is
    /// held to the same rules: it never leaves the process the caller named, and it
    /// never presses destructive wording without `confirm=true`.
    private func pressAXElement(
        underPointTopLeft pointTopLeft: CGPoint,
        pid: Int32,
        confirmed: Bool
    ) -> AXPointPressOutcome {
        let appElement = AXHelpers.applicationElement(pid: pid)
        guard let hit = AXActionRuntimeSupport.hitTest(appElement, point: pointTopLeft)
            ?? AXActionRuntimeSupport.hitTest(AXUIElementCreateSystemWide(), point: pointTopLeft) else {
            return .none
        }

        // The system-wide fallback hit-tests every on-screen window, so it can return
        // an element of another process (an open menu, a notification banner, another
        // app's window over the same point). Acting on it would silently break the
        // "act on the window I named" contract.
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success, hitPID == pid else {
            return .none
        }
        AXHelpers.setMessagingTimeout(hit, seconds: 1.0)

        for candidate in AXActionRuntimeSupport.walkAncestors(startingAt: hit, maxDepth: 4) {
            let frame = AXActionRuntimeSupport.rectAttribute(candidate, attribute: "AXFrame" as CFString)
            guard AXPointPressEligibility.isEligible(
                actions: AXActionRuntimeSupport.actionNames(candidate),
                frame: frame,
                pointTopLeft: pointTopLeft,
                enabled: AXActionRuntimeSupport.boolAttribute(candidate, attribute: kAXEnabledAttribute as CFString)
            ), let frame else {
                continue
            }
            let candidateLabel = label(for: candidate)
            let safety = RuntimeSafetyPolicy.evaluateLabel(candidateLabel, confirmed: confirmed)
            if safety.blocked {
                return .requiresConfirmation(
                    safety.reason ?? "The element under the click point requires explicit confirmation."
                )
            }
            return .pressed(
                AXPointPressResult(
                    role: AXActionRuntimeSupport.stringAttribute(candidate, attribute: kAXRoleAttribute as CFString),
                    label: candidateLabel,
                    frameTopLeft: frame,
                    status: AXActionRuntimeSupport.performAction(kAXPressAction as String, on: candidate)
                )
            )
        }
        return .none
    }

    private func isSafeDescendantRetargetContainer(_ element: AXUIElement) -> Bool {
        let role = AXActionRuntimeSupport.stringAttribute(element, attribute: kAXRoleAttribute as CFString)
        guard ["AXGroup", "AXRow", "AXOutlineRow", "AXTableRow"].contains(role ?? "") else {
            return false
        }
        guard let frame = AXActionRuntimeSupport.rectAttribute(element, attribute: "AXFrame" as CFString) else {
            return false
        }
        let area = max(frame.width, 0) * max(frame.height, 0)
        return frame.width > 1 && frame.height > 1 && area <= 500_000 && frame.width <= 1_200 && frame.height <= 320
    }

    private func label(for element: AXUIElement) -> String {
        [
            AXActionRuntimeSupport.stringAttribute(element, attribute: kAXTitleAttribute as CFString),
            AXActionRuntimeSupport.stringAttribute(element, attribute: kAXValueAttribute as CFString),
            AXActionRuntimeSupport.stringAttribute(element, attribute: kAXDescriptionAttribute as CFString),
            AXActionRuntimeSupport.stringAttribute(element, attribute: kAXHelpAttribute as CFString),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func verifyClick(
        before: AXActionStateCapture,
        after: AXActionStateCapture?,
        target: AXActionTargetSnapshot?,
        refreshedTarget: AXActionTargetSnapshot?,
        refreshedTargetStrategy: String?,
        foregroundBeforeDispatch: String?,
        foregroundAfter: String?,
        dispatchSuccess: Bool,
        webAreaBaseline: WebAreaTextBaseline,
        region: ClickTargetRegion.Evidence,
        extraNotes: [String]
    ) -> ClickVerificationEvidenceDTO {
        let renderedTextChanged: Bool?
        let selectionSummaryChanged: Bool?
        let focusedElementChanged: Bool?
        let windowTitleChanged: Bool?
        let modalDialogOpened: Bool?
        if let after {
            renderedTextChanged = self.renderedTextChanged(before: before, after: after)
            selectionSummaryChanged = self.selectionSummaryChanged(before: before, after: after)
            focusedElementChanged = self.focusedElementChanged(before: before, after: after)
            windowTitleChanged = before.envelope.response.window.title != after.envelope.response.window.title
            modalDialogOpened = ClickDialogEffectVerifier.modalDialogOpened(
                before: before.envelope.response.tree.nodes,
                after: after.envelope.response.tree.nodes
            )
        } else {
            renderedTextChanged = nil
            selectionSummaryChanged = nil
            focusedElementChanged = nil
            windowTitleChanged = nil
            modalDialogOpened = nil
        }
        let beforeSelected = target?.isSelected
        let afterSelected = refreshedTarget?.isSelected
        let beforeFocused = target?.isFocused
        let afterFocused = refreshedTarget?.isFocused
        let beforeValue = target?.projectedValuePreview
        let afterValue = refreshedTarget?.projectedValuePreview
        let targetStateChanged =
            target == nil ? nil :
            beforeSelected != afterSelected ||
            beforeFocused != afterFocused ||
            beforeValue != afterValue
        var verificationNotes = extraNotes
        if after == nil {
            verificationNotes.append("No post-click state was available for verification.")
        }
        if renderedTextChanged == true {
            verificationNotes.append("Rendered text changed after click.")
        }
        if selectionSummaryChanged == true {
            verificationNotes.append("Selection summary changed after click.")
        }
        if focusedElementChanged == true {
            verificationNotes.append("Focused element changed after click.")
        }
        if targetStateChanged == true {
            verificationNotes.append("Target selected/focused/value evidence changed after click.")
        }
        if modalDialogOpened == true {
            verificationNotes.append(ClickDialogEffectVerifier.verificationNote)
        }
        if foregroundBeforeDispatch != foregroundAfter {
            verificationNotes.append("Foreground changed from \(foregroundBeforeDispatch ?? "nil") to \(foregroundAfter ?? "nil").")
        }
        if let diagnostic = region.diagnostic {
            verificationNotes.append(diagnostic)
        }
        if let diagnostic = webAreaBaseline.diagnostic {
            verificationNotes.append(diagnostic)
        }
        let webAreaTextAfter = after.flatMap {
            WebAreaTextSnapshot.canonicalText(in: $0.envelope.response.tree.nodes)
        }
        let webAreaTextChanged = webAreaBaseline.textBefore.flatMap { beforeText in
            webAreaTextAfter.map { beforeText != $0 }
        }

        let assessment = ClickIntentVerifier.assess(
            focusedElementChanged: focusedElementChanged,
            modalDialogOpened: modalDialogOpened,
            windowTitleChanged: windowTitleChanged,
            targetStateChanged: targetStateChanged,
            ocrAnchorDisappeared: nil,
            targetRegionChangeRatio: region.targetRegionChangeRatio,
            renderedTextChanged: renderedTextChanged,
            selectionSummaryChanged: selectionSummaryChanged,
            webRendererSurface: before.envelope.response.tree.profile == AXProjectionProfile.richWeb.rawValue,
            dispatchSuccess: dispatchSuccess,
            webAreaBaselineStable: webAreaBaseline.baselineStable,
            webAreaTextBefore: webAreaBaseline.textBefore,
            webAreaTextAfter: webAreaTextAfter
        )
        verificationNotes.append(contentsOf: assessment.notes)

        return ClickVerificationEvidenceDTO(
            preStateToken: before.envelope.response.stateToken,
            postStateToken: after?.envelope.response.stateToken,
            targetRelocated: refreshedTarget != nil,
            refreshedTargetMatchStrategy: refreshedTargetStrategy,
            beforeTargetSelected: beforeSelected,
            afterTargetSelected: afterSelected,
            beforeTargetFocused: beforeFocused,
            afterTargetFocused: afterFocused,
            beforeTargetValuePreview: beforeValue,
            afterTargetValuePreview: afterValue,
            beforeFocusedNodeID: before.envelope.response.selectionSummary?.focusedNodeID,
            afterFocusedNodeID: after?.envelope.response.selectionSummary?.focusedNodeID,
            renderedTextChanged: renderedTextChanged,
            selectionSummaryChanged: selectionSummaryChanged,
            focusedElementChanged: focusedElementChanged,
            windowTitleChanged: windowTitleChanged,
            modalDialogOpened: modalDialogOpened,
            targetStateChanged: targetStateChanged,
            webAreaTextChanged: webAreaTextChanged,
            webAreaBaselineStable: webAreaBaseline.baselineStable,
            webAreaBaselineDiagnostic: webAreaBaseline.diagnostic ?? (
                webAreaBaseline.baselineStable == false
                    ? ClickIntentVerifier.unstableWebAreaBaselineNote
                    : (
                        before.envelope.response.tree.profile == AXProjectionProfile.richWeb.rawValue &&
                            webAreaBaseline.baselineStable == true &&
                            webAreaTextAfter == nil
                            ? ClickIntentVerifier.missingPostWebAreaSampleNote
                            : nil
                    )
            ),
            ocrAnchorMatched: nil,
            ocrAnchorRelocated: nil,
            ocrAnchorDisappeared: nil,
            targetRegionChangeRatio: region.targetRegionChangeRatio,
            fullImageChangeRatio: region.fullImageChangeRatio,
            foregroundPreserved: foregroundBeforeDispatch == nil || foregroundAfter == nil
                ? nil
                : foregroundBeforeDispatch == foregroundAfter,
            targetRegionChangeThreshold: ClickIntentVerifier.targetRegionChangeThreshold,
            targetRegionDiagnostic: region.diagnostic,
            ocrAnchorDiagnostic: nil,
            intentSignals: assessment.intentSignals,
            ambientOnlySignals: assessment.ambientOnlySignals,
            verificationNotes: verificationNotes
        )
    }

    private func semanticVerified(
        plan: SemanticPlan,
        dispatchSuccess: Bool,
        verification: ClickVerificationEvidenceDTO
    ) -> Bool {
        guard dispatchSuccess else {
            return false
        }
        switch plan.attempt {
        case .setContainerSelectedRows, .setRowSelectedTrue, .exactPrimaryAXAction, .safeUniqueDescendantRetarget:
            return effectVerified(verification)
        case .ambiguousDescendantClick, .coordinateRequired, .unsupportedPrimaryClick, .none:
            return false
        }
    }

    private func effectVerified(_ verification: ClickVerificationEvidenceDTO?) -> Bool {
        ClickIntentVerifier.verified(verification)
    }

    private func coordinatePlan(
        for target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO
    ) -> ClickCoordinatePlan? {
        let resolved = AXCursorTargeting.targetPoint(for: target, window: window)
        guard let point = resolved.point else {
            return nil
        }
        return coordinatePlan(
            appKitPoint: point,
            window: window,
            source: resolved.source ?? "element_target_point",
            warnings: resolved.warnings
        )
    }

    private func coordinatePlan(
        x: Double,
        y: Double,
        modelSize: PixelSize,
        window: ResolvedWindowDTO,
        source: String
    ) -> ClickCoordinatePlan? {
        guard x.isFinite, y.isFinite,
              modelSize.width > 0, modelSize.height > 0,
              x >= -0.5, y >= -0.5,
              x <= Double(modelSize.width) + 0.5,
              y <= Double(modelSize.height) + 0.5 else {
            return nil
        }
        let frame = rect(from: window.frameAppKit).standardized
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        let scaleX = Double(modelSize.width) / frame.width
        let scaleY = Double(modelSize.height) / frame.height
        let appKitPoint = CGPoint(
            x: frame.minX + (x / scaleX),
            y: frame.maxY - (y / scaleY)
        )
        return coordinatePlan(
            appKitPoint: appKitPoint,
            window: window,
            source: source,
            warnings: []
        )
    }

    private func coordinatePlan(
        appKitPoint: CGPoint,
        window: ResolvedWindowDTO,
        source: String,
        warnings: [String]
    ) -> ClickCoordinatePlan? {
        let frame = rect(from: window.frameAppKit).standardized
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        let modelSize = modelPixelSize(for: window)
        let scale = Scale2D(
            x: Double(modelSize.width) / frame.width,
            y: Double(modelSize.height) / frame.height
        )
        let modelPoint = CGPoint(
            x: (appKitPoint.x - frame.minX) * scale.x,
            y: (frame.maxY - appKitPoint.y) * scale.y
        )
        let eventTapPoint = CGPoint(
            x: appKitPoint.x,
            y: DesktopGeometry.desktopTop() - appKitPoint.y
        )
        let mapping = ClickCoordinateMappingDTO(
            inputPoint: PointDTO(x: modelPoint.x, y: modelPoint.y),
            inputCoordinateSpace: .modelFacingScreenshot,
            modelPixelSize: modelSize,
            scaleToWindowLogical: scale,
            targetPointAppKit: PointDTO(x: appKitPoint.x, y: appKitPoint.y),
            eventTapPointTopLeft: PointDTO(x: eventTapPoint.x, y: eventTapPoint.y),
            targetPointSource: source,
            warnings: warnings
        )
        return ClickCoordinatePlan(
            mapping: mapping,
            appKitPoint: appKitPoint,
            eventTapPointTopLeft: eventTapPoint
        )
    }

    private func targetHasUsablePoint(_ target: AXActionTargetSnapshot, window: ResolvedWindowDTO?) -> Bool {
        guard let window else {
            return target.suggestedInteractionPointAppKit != nil ||
                target.activationPointAppKit != nil ||
                target.frameAppKit != nil
        }
        return AXCursorTargeting.targetPoint(for: target, window: window).point != nil
    }


    private func modelFacingImage(from capture: AXActionStateCapture) -> CGImage? {
        guard let path = capture.envelope.response.screenshot.image?.imagePath,
              let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func modelPixelSize(for response: AXPipelineV2Response) -> PixelSize {
        if let size = response.screenshot.coordinateContract?.modelFacingScreenshot.pixelSize {
            return size
        }
        return modelPixelSize(for: response.window)
    }

    private func modelPixelSize(for window: ResolvedWindowDTO) -> PixelSize {
        let fitRule = ScreenshotFitRule()
        return fitRule.predictedModelSize(
            for: GlobalEventTapTopLeftRect(
                x: window.frameAppKit.x,
                y: window.frameAppKit.y,
                width: window.frameAppKit.width,
                height: window.frameAppKit.height
            )
        )
    }

    private func normalizedTargetClickCount(_ request: ClickRequest) -> Int? {
        try? normalizedClickCount(request)
    }

    private func normalizedClickCount(_ request: ClickRequest) throws -> Int {
        let modeCount = explicitClickCount(from: request.mode)
        if let clickCount = request.clickCount {
            guard clickCount == 1 || clickCount == 2 else {
                throw ClickClickCountError.invalid("clickCount must be 1 or 2.")
            }
            if let modeCount, modeCount != clickCount {
                throw ClickClickCountError.invalid("mode and clickCount disagree; supply one explicit click-count control.")
            }
            return clickCount
        }
        if let modeCount {
            return modeCount
        }
        return 1
    }

    private func explicitClickCount(from mode: ClickModeDTO?) -> Int? {
        switch mode {
        case .single:
            return 1
        case .double:
            return 2
        case nil:
            return nil
        }
    }

    private func invalidClickCountResponse(
        request: ClickRequest,
        capture: AXActionStateCapture,
        requestedTarget: ClickRequestedTargetDTO,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?,
        warnings: [String],
        notes: [String],
        summary: String
    ) -> ClickResponse {
        response(
            classification: .unsupported,
            failureDomain: .unsupported,
            summary: summary,
            window: capture.envelope.response.window,
            requestedTarget: requestedTarget,
            target: nil,
            clickCount: request.clickCount,
            mouseButton: mouseButton,
            finalRoute: .rejected,
            fallbackReason: .invalidClickCount,
            axAttempt: nil,
            coordinate: nil,
            transports: [],
            routeSteps: [rejectedStep(summary)],
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: nil,
            cursor: AXCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because the request click count was invalid.",
                    options: executionOptions
            ),
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: nil,
            frontmostBundleAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            warnings: warnings,
            notes: notes,
            verification: nil
        )
    }

    private func requestedTargetDTO(_ request: ClickRequest) -> ClickRequestedTargetDTO {
        if let target = request.target {
            return ClickRequestedTargetDTO(
                kind: target.kind == .ocrAnchor ? .ocrAnchor : .semanticTarget,
                target: target,
                x: nil,
                y: nil,
                coordinateSpace: nil
            )
        }
        return ClickRequestedTargetDTO(
            kind: .coordinate,
            target: nil,
            x: request.x.map(sanitizedJSONDouble),
            y: request.y.map(sanitizedJSONDouble),
            coordinateSpace: request.x != nil || request.y != nil ? .modelFacingScreenshot : nil
        )
    }

    private func semanticResponse(
        _ semantic: ClickSemanticOutcome,
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?
    ) -> ClickResponse {
        response(
            classification: semantic.classification,
            failureDomain: semantic.failureDomain,
            summary: semantic.summary,
            window: semantic.postCapture?.envelope.response.window ?? capture.envelope.response.window,
            requestedTarget: requestedTargetDTO(request),
            target: target,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: .semanticAX,
            fallbackReason: .none,
            axAttempt: semantic.axAttempt,
            coordinate: nil,
            transports: semantic.transport.map { [$0] } ?? [],
            routeSteps: semanticStep(semantic),
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: semantic.postCapture?.envelope.response.stateToken,
            cursor: semantic.cursor,
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: semantic.frontmostBundleBeforeDispatch,
            frontmostBundleAfter: semantic.frontmostBundleAfter,
            warnings: semantic.warnings,
            notes: semantic.notes,
            verification: semantic.verification,
            postScreenshot: postScreenshot(from: semantic.postCapture)
        )
    }

    private func coordinateFallbackResponse(
        _ fallback: ClickCoordinateOutcome,
        semantic: ClickSemanticOutcome,
        request: ClickRequest,
        capture: AXActionStateCapture,
        target: AXActionTargetSnapshot,
        clickCount: Int,
        mouseButton: MouseButtonDTO,
        frontmostBefore: String?
    ) -> ClickResponse {
        response(
            classification: fallback.classification,
            failureDomain: fallback.failureDomain,
            summary: fallback.summary,
            window: fallback.postCapture?.envelope.response.window ??
                semantic.postCapture?.envelope.response.window ??
                capture.envelope.response.window,
            requestedTarget: requestedTargetDTO(request),
            target: target,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: fallback.finalRoute,
            fallbackReason: fallback.fallbackReason,
            axAttempt: semantic.axAttempt,
            coordinate: fallback.coordinate,
            transports: fallback.transports,
            routeSteps: fallback.routeSteps,
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: fallback.postCapture?.envelope.response.stateToken ??
                semantic.postCapture?.envelope.response.stateToken,
            cursor: fallback.cursor,
            frontmostBundleBefore: frontmostBefore,
            frontmostBundleBeforeDispatch: fallback.frontmostBundleBeforeDispatch ??
                semantic.frontmostBundleBeforeDispatch,
            frontmostBundleAfter: fallback.frontmostBundleAfter ?? semantic.frontmostBundleAfter,
            warnings: fallback.warnings,
            notes: fallback.notes,
            verification: fallback.verification ?? semantic.verification,
            postScreenshot: postScreenshot(from: fallback.postCapture) ??
                postScreenshot(from: semantic.postCapture)
        )
    }

    private func response(
        classification: ActionClassificationDTO,
        failureDomain: ActionFailureDomainDTO?,
        summary: String,
        window: ResolvedWindowDTO?,
        requestedTarget: ClickRequestedTargetDTO,
        target: AXActionTargetSnapshot?,
        clickCount: Int?,
        mouseButton: MouseButtonDTO?,
        finalRoute: ClickFinalRouteDTO,
        fallbackReason: ClickFallbackReasonDTO,
        axAttempt: ClickAXAttemptDTO?,
        coordinate: ClickCoordinateMappingDTO?,
        transports: [ClickTransportAttemptDTO],
        routeSteps: [ClickRouteStepDTO],
        preStateToken: String?,
        postStateToken: String?,
        cursor: ActionCursorTargetResponseDTO,
        frontmostBundleBefore: String?,
        frontmostBundleBeforeDispatch: String?,
        frontmostBundleAfter: String?,
        warnings: [String],
        notes: [String],
        verification: ClickVerificationEvidenceDTO?,
        postScreenshot: ScreenshotDTO? = nil
    ) -> ClickResponse {
        ClickResponse(
            contractVersion: ContractVersion.current,
            ok: classification == .success,
            classification: classification,
            failureDomain: failureDomain,
            summary: summary,
            window: window,
            requestedTarget: requestedTarget,
            target: target?.dto,
            clickCount: clickCount,
            mouseButton: mouseButton,
            finalRoute: finalRoute,
            fallbackReason: fallbackReason,
            axAttempt: axAttempt,
            coordinate: coordinate,
            transports: transports,
            routeSteps: routeSteps,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            frontmostBundleBefore: frontmostBundleBefore,
            frontmostBundleBeforeDispatch: frontmostBundleBeforeDispatch,
            frontmostBundleAfter: frontmostBundleAfter,
            warnings: warnings,
            notes: notes,
            verification: verification,
            postScreenshot: postScreenshot
        )
    }

    private func postScreenshot(from capture: AXActionStateCapture?) -> ScreenshotDTO? {
        guard let screenshot = capture?.envelope.response.screenshot,
              screenshot.status != "omitted" else {
            return nil
        }
        return screenshot
    }

    private func semanticStep(_ semantic: ClickSemanticOutcome) -> [ClickRouteStepDTO] {
        [
            ClickRouteStepDTO(
                route: .semanticAX,
                dispatchSuccess: semantic.dispatchSuccess,
                verificationSuccess: semantic.verificationSuccess,
                intentSuccess: semantic.intentSuccess,
                note: "semantic AX attempt \(semantic.axAttempt.rawValue)"
            )
        ]
    }

    private func rejectedStep(_ note: String) -> ClickRouteStepDTO {
        ClickRouteStepDTO(
            route: .rejected,
            dispatchSuccess: false,
            verificationSuccess: false,
            intentSuccess: false,
            note: note
        )
    }

    private func renderedTextChanged(before: AXActionStateCapture, after: AXActionStateCapture) -> Bool {
        normalizeText(before.envelope.response.tree.renderedText) != normalizeText(after.envelope.response.tree.renderedText)
    }

    private func sampleWebAreaTextBaseline(before capture: AXActionStateCapture) -> WebAreaTextBaseline {
        guard capture.envelope.response.tree.profile == AXProjectionProfile.richWeb.rawValue else {
            return .notApplicable
        }
        let firstSample = WebAreaTextSnapshot.canonicalText(in: capture.envelope.response.tree.nodes)
        do {
            let secondCapture = try targetResolver.reread(after: capture, imageMode: .omit)
            let secondSample = WebAreaTextSnapshot.canonicalText(in: secondCapture.envelope.response.tree.nodes)
            return WebAreaTextBaseline(firstSample: firstSample, secondSample: secondSample)
        } catch {
            return WebAreaTextBaseline(
                unavailableDiagnostic: "The second pre-dispatch web-area text sample failed: \(error)."
            )
        }
    }

    private func selectionSummaryChanged(before: AXActionStateCapture, after: AXActionStateCapture) -> Bool {
        before.envelope.response.selectionSummary?.focusedNodeID != after.envelope.response.selectionSummary?.focusedNodeID ||
            before.envelope.response.selectionSummary?.selectedText != after.envelope.response.selectionSummary?.selectedText ||
            before.envelope.response.selectionSummary?.selectedTextSource != after.envelope.response.selectionSummary?.selectedTextSource ||
            before.envelope.response.selectionSummary?.selectedCanonicalIndices != after.envelope.response.selectionSummary?.selectedCanonicalIndices ||
            before.envelope.response.selectionSummary?.selectedNodeIDs != after.envelope.response.selectionSummary?.selectedNodeIDs
    }

    /// Whether focus really moved between two captures.
    ///
    /// `focusedElement.index` is a POSITIONAL index in the projection: on a live page
    /// any node inserted or removed before the focused element shifts it while focus
    /// never moved. Treating that as a focus change would hand full intent credit to
    /// a click that never landed, which is the ambient-noise problem this gate exists
    /// to remove. Identity and labels are stable, so only those count.
    private func focusedElementChanged(before: AXActionStateCapture, after: AXActionStateCapture) -> Bool {
        let beforeNodeID = before.envelope.response.selectionSummary?.focusedNodeID
        let afterNodeID = after.envelope.response.selectionSummary?.focusedNodeID
        if beforeNodeID != nil || afterNodeID != nil, beforeNodeID != afterNodeID {
            return true
        }
        return before.envelope.response.focusedElement.title != after.envelope.response.focusedElement.title ||
            before.envelope.response.focusedElement.description != after.envelope.response.focusedElement.description ||
            before.envelope.response.focusedElement.displayRole != after.envelope.response.focusedElement.displayRole
    }

    private func normalizeText(_ text: String?) -> String {
        (text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func ocrCaptureImageMode(requested: ImageMode) -> ImageMode {
        requested == .omit ? .path : requested
    }

    static func normalizedOCRVerificationRegion(
        box: OCRBoxDTO,
        modelWidth: Double,
        modelHeight: Double
    ) -> CGRect {
        CGRect(
            x: box.x / modelWidth,
            y: 1 - (box.y + box.height) / modelHeight,
            width: box.width / modelWidth,
            height: box.height / modelHeight
        )
    }

    private func rect(from dto: RectDTO) -> CGRect {
        CGRect(x: dto.x, y: dto.y, width: dto.width, height: dto.height)
    }
}

enum ClickDialogEffectVerifier {
    static let verificationNote = "A modal/dialog surface appeared after click."

    static func modalDialogOpened(
        before: [AXPipelineV2SurfaceNodeDTO],
        after: [AXPipelineV2SurfaceNodeDTO]
    ) -> Bool {
        modalDialogOpened(
            before: before.map(ClickDialogEffectProbe.init),
            after: after.map(ClickDialogEffectProbe.init)
        )
    }

    static func modalDialogOpened(before: [ClickDialogEffectProbe], after: [ClickDialogEffectProbe]) -> Bool {
        let beforeSignatures = Set(before.compactMap(dialogSignature))
        return after.compactMap(dialogSignature).contains { beforeSignatures.contains($0) == false }
    }

    private static func dialogSignature(_ probe: ClickDialogEffectProbe) -> String? {
        guard isDialogLike(probe) else {
            return nil
        }
        return probe.signatureSignals
            .map(normalize)
            .filter { $0.isEmpty == false }
            .joined(separator: "|")
    }

    private static func isDialogLike(_ probe: ClickDialogEffectProbe) -> Bool {
        (probe.roleSignals + probe.metadataSignals).contains { signal in
            let normalized = normalize(signal)
            return normalized == "dialog" ||
                normalized == "alert" ||
                normalized == "alertdialog" ||
                normalized == "sheet" ||
                normalized.contains("modal") ||
                normalized.contains("dialog") ||
                normalized.contains("alert")
        }
    }

    private static func normalize(_ text: String?) -> String {
        (text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

struct ClickDialogEffectProbe: Hashable, Sendable {
    let roleSignals: [String]
    let signatureSignals: [String]
    let metadataSignals: [String]

    init(
        roleSignals: [String],
        signatureSignals: [String],
        metadataSignals: [String] = []
    ) {
        self.roleSignals = roleSignals
        self.signatureSignals = signatureSignals
        self.metadataSignals = metadataSignals
    }

    init(node: AXPipelineV2SurfaceNodeDTO) {
        let frameSignature = node.frameAppKit.map { "\($0.x),\($0.y),\($0.width),\($0.height)" }
        roleSignals = [
            node.displayRole,
            node.rawRole,
            node.rawSubrole,
            node.description,
            node.identifier,
        ].compactMap { $0 }
        signatureSignals = [
            node.displayRole,
            node.rawRole,
            node.rawSubrole,
            node.title,
            node.description,
            node.identifier,
            frameSignature,
        ].compactMap { $0 }
        metadataSignals = node.flags + node.dialogMetadataSignals + node.transformNotes
    }
}

private extension AXPipelineV2SurfaceNodeDTO {
    var dialogMetadataSignals: [String] {
        let affordanceSignals = (affordances ?? []).flatMap { affordance in
            [
                Optional(affordance.kind),
                affordance.label,
                affordance.value,
                affordance.sourceRole,
                affordance.sourceSubrole,
                affordance.sourceTitle,
                affordance.sourceURL,
                affordance.rawAction,
            ].compactMap { $0 }
        }
        let actionSignals = (availableActions ?? []).flatMap { action in
            [
                Optional(action.rawName),
                action.label,
                action.description,
                Optional(action.category),
            ].compactMap { $0 }
        }
        return affordanceSignals + actionSignals
    }
}

private enum ClickClickCountError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

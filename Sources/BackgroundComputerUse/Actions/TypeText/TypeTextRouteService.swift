import ApplicationServices
import Foundation

struct TypeTextRouteService {
    private let executionOptions: ActionExecutionOptions
    private let targetResolver: AXActionTargetResolver
    private let backgroundTextPreparation: BackgroundTextPreparation
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let dispatchPrimitive = "CGEvent.keyboardSetUnicodeString + postToPid"
    private let elementValueDispatchPrimitive = "AXUIElementSetAttributeValue(kAXValueAttribute) + AXUIElementSetAttributeValue(kAXSelectedTextRangeAttribute)"
    private let settleDelay: TimeInterval = 0.35

    init(
        executionOptions: ActionExecutionOptions = .visualCursorEnabled,
        backgroundTextPreparation: BackgroundTextPreparation = .live,
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? = ForegroundApplicationSnapshot.capture
    ) {
        self.executionOptions = executionOptions
        self.backgroundTextPreparation = backgroundTextPreparation
        self.foregroundApplication = foregroundApplication
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
    }

    func typeText(request: TypeTextRequest) throws -> TypeTextResponse {
        let foregroundBefore = foregroundApplication()
        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500
        )
        var warnings = targetResolver.stateTokenWarnings(
            suppliedStateToken: request.stateToken,
            liveStateToken: capture.envelope.response.stateToken
        )
        var notes: [String] = []

        let candidate: AXActionCandidate?
        if let target = request.target {
            candidate = targetResolver.resolveTarget(
                target,
                in: capture,
                kind: .typeText
            )
        } else {
            candidate = targetResolver.resolveFocusedTextEntryTarget(in: capture)
            notes.append("No target was supplied; type_text used the focused text-entry target fallback.")
        }

        guard let candidate else {
            if request.target == nil, request.allowOpaqueFocusedSurface == true {
                return typeTextOnOpaqueFocusedSurface(
                    request: request,
                    capture: capture,
                    foregroundBefore: foregroundBefore,
                    warnings: warnings,
                    notes: notes
                )
            }
            let summary = request.target.map {
                targetResolver.targetResolutionFailureDescription(for: $0, in: capture)
            } ?? "No focused text-entry target was available for type_text."
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: summary,
                window: capture.envelope.response.window,
                target: nil,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: nil,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the action target was not resolved.",
                    options: executionOptions
                ),
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let target = candidate.target
        let secureDecision = RuntimeSafetyPolicy.evaluateSecureTextEntry(
            rawRole: target.rawRole,
            rawSubrole: target.rawSubrole,
            displayRole: target.displayRole,
            confirmed: request.confirm == true
        )
        if secureDecision.blocked {
            return response(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: secureDecision.reason ?? "Typing into secure text fields requires explicit confirmation.",
                window: capture.envelope.response.window,
                target: target,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: nil,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because runtime safety policy blocked typing.",
                    options: executionOptions
                ),
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }
        let semantic = targetResolver.semanticSuitability(for: target, kind: .typeText)

        guard semantic.appropriate else {
            return response(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: "The resolved node does not look like a text-entry surface for type_text.",
                window: capture.envelope.response.window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: nil,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because type_text rejected the target as semantically unsupported.",
                    options: executionOptions
                ),
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let liveElement: AXActionResolvedLiveElement
        do {
            liveElement = try targetResolver.resolveLiveElement(for: target, in: capture)
        } catch {
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: String(describing: error),
                window: capture.envelope.response.window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: nil,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: AXCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the live AX element could not be resolved.",
                    options: executionOptions
                ),
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }
        let cursor = AXCursorTargeting.prepareTypeText(
            requested: request.cursor,
            target: target,
            window: capture.envelope.response.window,
            options: executionOptions
        )
        warnings.append(contentsOf: cursor.warnings)

        let window = capture.envelope.response.window
        let preparation = backgroundTextPreparation.prepare(
            pid: window.pid,
            windowNumber: window.windowNumber
        )
        notes.append(contentsOf: preparation.notes)
        warnings.append(contentsOf: preparation.warnings)
        let foregroundBeforeDispatch = foregroundApplication()
        let preDispatchBackgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundBeforeDispatch
        )
        guard preparation.preparedTargetWindow(requireKeyWindowRecords: true),
              preDispatchBackgroundSafety.foregroundPreserved else {
            AXCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
            let preparationFailed = preparation.preparedTargetWindow(requireKeyWindowRecords: true) == false
            return response(
                classification: .effectNotVerified,
                failureDomain: preparationFailed ? .transport : .backgroundSafety,
                summary: preparationFailed
                    ? "Text dispatch failed closed during target-window preparation."
                    : "Text dispatch was blocked because target preparation changed the user's foreground application.",
                window: window,
                target: target,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: false,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElement.resolution,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil,
                backgroundSafety: preDispatchBackgroundSafety
            )
        }

        let preparedBeforeState = AXActionRuntimeSupport.readTextState(liveElement.element)
        let expected = expectedOutcome(from: preparedBeforeState, text: request.text)

        let dispatchResult = dispatchText(
            request.text,
            expected: expected,
            to: liveElement.element,
            pid: window.pid,
            warnings: &warnings,
            notes: &notes
        )
        if dispatchResult.succeeded == false {
            AXCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: foregroundBeforeDispatch,
                after: foregroundApplication()
            )
            return response(
                classification: .effectNotVerified,
                failureDomain: .transport,
                summary: "The text dispatch did not report success.",
                window: capture.envelope.response.window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchResult.primitive,
                dispatchSucceeded: false,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElement.resolution,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: TypeTextVerificationEvidenceDTO(
                    preparedBeforeLiveState: preparedBeforeState,
                    expectedOutcome: expected,
                    afterSameElementState: nil,
                    afterResolvedLiveState: nil,
                    afterProjectedState: nil,
                    exactValueMatch: false,
                    exactValueMatchSource: nil,
                    exactSelectionMatch: nil,
                    exactSelectionMatchSource: nil,
                    targetRelocated: false,
                    refreshedTargetMatchStrategy: nil,
                    beforeFocusedNodeID: capture.envelope.response.selectionSummary?.focusedNodeID,
                    afterFocusedNodeID: nil,
                    beforeTargetFocused: target.isFocused,
                    afterTargetFocused: nil,
                    renderedTextChanged: false,
                    verificationNotes: ["Transport failed before a reread could verify text insertion."]
                ),
                backgroundSafety: backgroundSafety
            )
        }

        AXCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
        sleepRunLoop(settleDelay)
        let afterSameElementState = AXActionRuntimeSupport.readTextState(liveElement.element)

        let postCapture: AXActionStateCapture?
        do {
            postCapture = try targetResolver.reread(after: capture)
        } catch {
            postCapture = nil
            notes.append("Post-type reread failed: \(error).")
        }

        let refreshedTargetResult = postCapture.flatMap {
            targetResolver.locateRefreshedTarget(in: $0, prior: target, kind: .typeText)
        }
        let refreshedTarget = refreshedTargetResult?.target
        let refreshedTargetStrategy = refreshedTargetResult?.strategy

        var afterResolvedLiveState: TypeTextObservedStateDTO?
        if let postCapture, let refreshedTarget,
           let resolved = try? targetResolver.resolveLiveElement(for: refreshedTarget, in: postCapture) {
            afterResolvedLiveState = AXActionRuntimeSupport.readTextState(resolved.element)
        }

        let afterProjectedState = projectedTextState(from: refreshedTarget)
        let exactValueMatchSource = exactValueMatchSource(
            expected: expected,
            afterSameElementState: afterSameElementState,
            afterResolvedLiveState: afterResolvedLiveState,
            afterProjectedState: afterProjectedState
        )
        let exactSelectionMatchSource = exactSelectionMatchSource(
            expected: expected,
            afterSameElementState: afterSameElementState,
            afterResolvedLiveState: afterResolvedLiveState
        )
        let renderedTextChanged = postCapture.map {
            normalizeRenderedText($0.envelope.response.tree.renderedText) != normalizeRenderedText(capture.envelope.response.tree.renderedText)
        } ?? false

        let verification = TypeTextVerificationEvidenceDTO(
            preparedBeforeLiveState: preparedBeforeState,
            expectedOutcome: expected,
            afterSameElementState: afterSameElementState,
            afterResolvedLiveState: afterResolvedLiveState,
            afterProjectedState: afterProjectedState,
            exactValueMatch: exactValueMatchSource != nil,
            exactValueMatchSource: exactValueMatchSource,
            exactSelectionMatch: expected?.selectionRange == nil ? nil : (exactSelectionMatchSource != nil),
            exactSelectionMatchSource: exactSelectionMatchSource,
            targetRelocated: refreshedTarget != nil,
            refreshedTargetMatchStrategy: refreshedTargetStrategy,
            beforeFocusedNodeID: capture.envelope.response.selectionSummary?.focusedNodeID,
            afterFocusedNodeID: postCapture?.envelope.response.selectionSummary?.focusedNodeID,
            beforeTargetFocused: target.isFocused,
            afterTargetFocused: refreshedTarget?.isFocused,
            renderedTextChanged: renderedTextChanged,
            verificationNotes: buildVerificationNotes(
                target: target,
                expected: expected,
                preparedBeforeState: preparedBeforeState,
                afterResolvedLiveState: afterResolvedLiveState,
                afterSameElementState: afterSameElementState
            )
        )
        let backgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundApplication()
        )

        return classifyResult(
            request: request,
            window: capture.envelope.response.window,
            target: target,
            semantic: semantic,
            liveElementResolution: liveElement.resolution,
            dispatchPrimitive: dispatchResult.primitive,
            dispatchSucceeded: dispatchResult.succeeded,
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: postCapture?.envelope.response.stateToken,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            verification: verification,
            backgroundSafety: backgroundSafety
        )
    }

    private struct TextDispatchResult {
        let succeeded: Bool
        let primitive: String
    }

    private func typeTextOnOpaqueFocusedSurface(
        request: TypeTextRequest,
        capture: AXActionStateCapture,
        foregroundBefore: ForegroundApplicationSnapshot?,
        warnings: [String],
        notes: [String]
    ) -> TypeTextResponse {
        var warnings = warnings
        var notes = notes
        let cursor = AXCursorTargeting.notAttempted(
            requested: request.cursor,
            reason: "Cursor movement was not attempted because the AX-opaque focused surface has no semantic target.",
            options: executionOptions
        )
        guard request.confirm == true else {
            return response(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: "Opaque focused-surface typing requires confirm=true because secure-field detection is unavailable.",
                window: capture.envelope.response.window,
                target: nil,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: nil,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let preDispatchCapture: AXActionStateCapture
        do {
            preDispatchCapture = try targetResolver.capture(
                windowID: request.window,
                includeMenuBar: request.includeMenuBar ?? true,
                maxNodes: request.maxNodes ?? 6500
            )
        } catch {
            return response(
                classification: .effectNotVerified,
                failureDomain: .targeting,
                summary: "Opaque focused-surface typing was not attempted because the requested window could not be recaptured: \(error)",
                window: capture.envelope.response.window,
                target: nil,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: false,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let initialWindow = capture.envelope.response.window
        let dispatchWindow = preDispatchCapture.envelope.response.window
        guard dispatchWindow.pid == initialWindow.pid,
              dispatchWindow.windowNumber == initialWindow.windowNumber else {
            return response(
                classification: .effectNotVerified,
                failureDomain: .targeting,
                summary: "Opaque focused-surface typing was not attempted because the requested window identity changed before dispatch.",
                window: dispatchWindow,
                target: nil,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: false,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: preDispatchCapture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil
            )
        }

        let preparation = backgroundTextPreparation.prepare(
            pid: dispatchWindow.pid,
            windowNumber: dispatchWindow.windowNumber
        )
        notes.append(contentsOf: preparation.notes)
        warnings.append(contentsOf: preparation.warnings)
        let foregroundBeforeDispatch = foregroundApplication()
        let preDispatchBackgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundBeforeDispatch
        )
        guard preparation.preparedTargetWindow(requireKeyWindowRecords: true),
              preDispatchBackgroundSafety.foregroundPreserved else {
            let preparationFailed = preparation.preparedTargetWindow(requireKeyWindowRecords: true) == false
            let preflightFailure = preparationFailed
                ? "PID-scoped Unicode posting was not attempted because WindowServer could not establish the requested AX-opaque window as the key input recipient."
                : "PID-scoped Unicode posting was not attempted because target preparation changed the user's foreground application."
            warnings.append(preflightFailure)
            notes.append(preflightFailure)
            return response(
                classification: .effectNotVerified,
                failureDomain: preparationFailed ? .transport : .backgroundSafety,
                summary: preparationFailed
                    ? "Opaque focused-surface typing failed closed during target-window preflight."
                    : "Opaque focused-surface typing failed closed because foreground preservation was not proven.",
                window: dispatchWindow,
                target: nil,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: false,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: preDispatchCapture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil,
                backgroundSafety: preDispatchBackgroundSafety
            )
        }

        let dispatched = AXActionRuntimeSupport.postUnicodeText(request.text, to: dispatchWindow.pid)
        guard dispatched else {
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: foregroundBeforeDispatch,
                after: foregroundApplication()
            )
            return response(
                classification: .effectNotVerified,
                failureDomain: .transport,
                summary: "PID-scoped Unicode posting failed for the AX-opaque focused surface.",
                window: dispatchWindow,
                target: nil,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: false,
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: preDispatchCapture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil,
                backgroundSafety: backgroundSafety
            )
        }

        sleepRunLoop(settleDelay)
        let postCapture: AXActionStateCapture?
        do {
            postCapture = try targetResolver.reread(after: preDispatchCapture)
        } catch {
            postCapture = nil
            notes.append("Post-type reread failed: \(error).")
        }
        notes.append(
            "Explicit opaque focused-surface fallback posted Unicode after successful target-window preflight; call get_window_state with imageMode path or base64 to verify the result before continuing."
        )
        let backgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundApplication()
        )
        let foregroundPreserved = backgroundSafety.foregroundPreserved
        return response(
            classification: foregroundPreserved ? .verifierAmbiguous : .effectNotVerified,
            failureDomain: foregroundPreserved ? .verification : .backgroundSafety,
            summary: foregroundPreserved
                ? "Text was dispatched to the AX-opaque focused surface; visual verification is required."
                : "Text dispatch did not preserve the user's foreground application.",
            window: dispatchWindow,
            target: nil,
            text: request.text,
            dispatchPrimitive: dispatchPrimitive,
            dispatchSucceeded: true,
            semanticAppropriate: nil,
            semanticReasons: [],
            liveElementResolution: nil,
            preStateToken: preDispatchCapture.envelope.response.stateToken,
            postStateToken: postCapture?.envelope.response.stateToken,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            verification: nil,
            backgroundSafety: backgroundSafety
        )
    }

    private func dispatchText(
        _ text: String,
        expected: TypeTextExpectedOutcomeDTO?,
        to element: AXUIElement,
        pid: pid_t,
        warnings: inout [String],
        notes: inout [String]
    ) -> TextDispatchResult {
        if let expectedValue = expected?.valueString,
           AXActionRuntimeSupport.isAttributeSettable(element, attribute: kAXValueAttribute as CFString) {
            notes.append("Using element-bound AX value write for type_text to avoid process-scoped same-app window routing.")
            let valueResult = AXActionRuntimeSupport.setValue(.string(expectedValue), on: element)
            notes.append("AX value write result: \(AXActionRuntimeSupport.rawStatusString(for: valueResult)).")
            guard valueResult == .success else {
                warnings.append("AX value write returned \(AXActionRuntimeSupport.rawStatusString(for: valueResult)); type_text did not fall back to PID-scoped Unicode posting for this writable target.")
                return TextDispatchResult(succeeded: false, primitive: elementValueDispatchPrimitive)
            }

            if let selectionRange = expected?.selectionRange {
                if AXActionRuntimeSupport.isAttributeSettable(element, attribute: kAXSelectedTextRangeAttribute as CFString) {
                    let rangeResult = AXActionRuntimeSupport.setSelectedTextRangeResult(
                        element,
                        location: selectionRange.location,
                        length: selectionRange.length
                    )
                    notes.append("AX caret restore result: \(AXActionRuntimeSupport.rawStatusString(for: rangeResult)).")
                    if rangeResult != .success {
                        warnings.append("AX caret restore returned \(AXActionRuntimeSupport.rawStatusString(for: rangeResult)).")
                    }
                } else {
                    warnings.append("AX value write succeeded, but the selected text range is not writable for caret restoration.")
                }
            }

            return TextDispatchResult(succeeded: true, primitive: elementValueDispatchPrimitive)
        }

        if expected?.valueString == nil {
            notes.append("Exact inserted value could not be computed; type_text used PID-scoped Unicode posting.")
        } else {
            notes.append("Live AX value was not writable; type_text used PID-scoped Unicode posting.")
        }
        return TextDispatchResult(
            succeeded: AXActionRuntimeSupport.postUnicodeText(text, to: pid),
            primitive: dispatchPrimitive
        )
    }

    private func classifyResult(
        request: TypeTextRequest,
        window: ResolvedWindowDTO,
        target: AXActionTargetSnapshot,
        semantic: (appropriate: Bool, reasons: [String]),
        liveElementResolution: String,
        dispatchPrimitive: String,
        dispatchSucceeded: Bool,
        preStateToken: String,
        postStateToken: String?,
        cursor: ActionCursorTargetResponseDTO,
        warnings: [String],
        notes: [String],
        verification: TypeTextVerificationEvidenceDTO,
        backgroundSafety: TypeTextBackgroundSafetyDTO
    ) -> TypeTextResponse {
        guard backgroundSafety.foregroundPreserved else {
            return response(
                classification: .effectNotVerified,
                failureDomain: .backgroundSafety,
                summary: "Text dispatch did not preserve the user's foreground application.",
                window: window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: dispatchSucceeded,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElementResolution,
                preStateToken: preStateToken,
                postStateToken: postStateToken,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: verification,
                backgroundSafety: backgroundSafety
            )
        }

        if verification.exactValueMatch {
            if verification.exactSelectionMatch == false {
                return response(
                    classification: .effectNotVerified,
                    failureDomain: .verification,
                    summary: "The text inserted exactly, but the expected caret or selection state did not verify.",
                    window: window,
                    target: target,
                    text: request.text,
                    dispatchPrimitive: dispatchPrimitive,
                    dispatchSucceeded: dispatchSucceeded,
                    semanticAppropriate: semantic.appropriate,
                    semanticReasons: semantic.reasons,
                    liveElementResolution: liveElementResolution,
                    preStateToken: preStateToken,
                    postStateToken: postStateToken,
                    cursor: cursor,
                    warnings: warnings,
                    notes: notes,
                    verification: verification,
                    backgroundSafety: backgroundSafety
                )
            }

            return response(
                classification: .success,
                failureDomain: nil,
                summary: "The targeted text dispatch matched the expected inserted value after reread.",
                window: window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: dispatchSucceeded,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElementResolution,
                preStateToken: preStateToken,
                postStateToken: postStateToken,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: verification,
                backgroundSafety: backgroundSafety
            )
        }

        if verification.targetRelocated == false || postStateToken == nil {
            return response(
                classification: .verifierAmbiguous,
                failureDomain: .verification,
                summary: "The text dispatch was attempted, but the route could not confidently relocate the target on reread.",
                window: window,
                target: target,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: dispatchSucceeded,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElementResolution,
                preStateToken: preStateToken,
                postStateToken: postStateToken,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: verification,
                backgroundSafety: backgroundSafety
            )
        }

        return response(
            classification: .effectNotVerified,
            failureDomain: .verification,
            summary: "The text dispatch was attempted, but the refreshed target state did not match the expected inserted text.",
            window: window,
            target: target,
            text: request.text,
            dispatchPrimitive: dispatchPrimitive,
            dispatchSucceeded: dispatchSucceeded,
            semanticAppropriate: semantic.appropriate,
            semanticReasons: semantic.reasons,
            liveElementResolution: liveElementResolution,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            verification: verification,
            backgroundSafety: backgroundSafety
        )
    }

    private func response(
        classification: ActionClassificationDTO,
        failureDomain: ActionFailureDomainDTO?,
        summary: String,
        window: ResolvedWindowDTO?,
        target: AXActionTargetSnapshot?,
        text: String,
        dispatchPrimitive: String?,
        dispatchSucceeded: Bool?,
        semanticAppropriate: Bool?,
        semanticReasons: [String],
        liveElementResolution: String?,
        preStateToken: String?,
        postStateToken: String?,
        cursor: ActionCursorTargetResponseDTO,
        warnings: [String],
        notes: [String],
        verification: TypeTextVerificationEvidenceDTO?,
        backgroundSafety: TypeTextBackgroundSafetyDTO? = nil
    ) -> TypeTextResponse {
        TypeTextResponse(
            contractVersion: ContractVersion.current,
            ok: classification == .success,
            classification: classification,
            failureDomain: failureDomain,
            summary: summary,
            window: window,
            target: target?.dto,
            text: text,
            dispatchPrimitive: dispatchPrimitive,
            dispatchSucceeded: dispatchSucceeded,
            semanticAppropriate: semanticAppropriate,
            semanticReasons: semanticReasons,
            liveElementResolution: liveElementResolution,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            backgroundSafety: backgroundSafety,
            verification: verification
        )
    }

    private func expectedOutcome(
        from beforeState: TypeTextObservedStateDTO,
        text: String
    ) -> TypeTextExpectedOutcomeDTO? {
        guard let value = beforeState.valueString,
              let range = beforeState.selectedTextRange else {
            return nil
        }

        let string = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location >= 0,
              nsRange.length >= 0,
              nsRange.location + nsRange.length <= string.length else {
            return nil
        }

        let replaced = string.replacingCharacters(in: nsRange, with: text)
        let caret = TypeTextSelectionRangeDTO(
            location: nsRange.location + (text as NSString).length,
            length: 0
        )

        return TypeTextExpectedOutcomeDTO(
            valuePreview: replaced.replacingOccurrences(of: "\n", with: "\\n"),
            valueString: replaced,
            selectionRange: caret
        )
    }

    private func projectedTextState(from target: AXActionTargetSnapshot?) -> TypeTextObservedStateDTO? {
        guard let target else {
            return nil
        }

        return TypeTextObservedStateDTO(
            valuePreview: target.projectedValuePreview,
            valueString: target.projectedValueKind == "string"
                ? target.projectedValuePreview?.replacingOccurrences(of: "\\n", with: "\n")
                : nil,
            length: target.projectedValueLength,
            truncated: target.projectedValueTruncated,
            selectedTextRange: nil,
            isFocused: target.isFocused
        )
    }

    private func exactValueMatchSource(
        expected: TypeTextExpectedOutcomeDTO?,
        afterSameElementState: TypeTextObservedStateDTO?,
        afterResolvedLiveState: TypeTextObservedStateDTO?,
        afterProjectedState: TypeTextObservedStateDTO?
    ) -> String? {
        guard let expectedValue = expected?.valueString else {
            return nil
        }

        if afterResolvedLiveState?.valueString == expectedValue {
            return "refreshed_live_element"
        }
        if afterSameElementState?.valueString == expectedValue {
            return "same_live_element"
        }
        if afterProjectedState?.valueString == expectedValue, afterProjectedState?.truncated == false {
            return "refreshed_projected_target"
        }
        return nil
    }

    private func exactSelectionMatchSource(
        expected: TypeTextExpectedOutcomeDTO?,
        afterSameElementState: TypeTextObservedStateDTO?,
        afterResolvedLiveState: TypeTextObservedStateDTO?
    ) -> String? {
        guard let expectedRange = expected?.selectionRange else {
            return nil
        }

        if afterResolvedLiveState?.selectedTextRange == expectedRange {
            return "refreshed_live_element"
        }
        if afterSameElementState?.selectedTextRange == expectedRange {
            return "same_live_element"
        }
        return nil
    }

    private func buildVerificationNotes(
        target: AXActionTargetSnapshot,
        expected: TypeTextExpectedOutcomeDTO?,
        preparedBeforeState: TypeTextObservedStateDTO?,
        afterResolvedLiveState: TypeTextObservedStateDTO?,
        afterSameElementState: TypeTextObservedStateDTO?
    ) -> [String] {
        var notes = [
            "Resolved display role: \(target.displayRole).",
            "Resolved raw role: \(target.rawRole ?? "unknown").",
        ]

        if let expectedValue = expected?.valuePreview {
            notes.append("Expected value after insertion: \(expectedValue).")
        } else {
            notes.append("Expected value could not be computed exactly because the live selection range was unavailable.")
        }

        if let preparedBeforeState {
            notes.append("Prepared before-state value: \(preparedBeforeState.valuePreview ?? "nil").")
        }
        if let afterResolvedLiveState {
            notes.append("Refreshed live value: \(afterResolvedLiveState.valuePreview ?? "nil").")
        } else if let afterSameElementState {
            notes.append("Same-element post value: \(afterSameElementState.valuePreview ?? "nil").")
        }

        return notes
    }

    private func normalizeRenderedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

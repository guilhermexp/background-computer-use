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
        let totalStarted = DispatchTime.now().uptimeNanoseconds
        let foregroundBefore = foregroundApplication()
        let captureStarted = DispatchTime.now().uptimeNanoseconds
        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500
        )
        let captureMs = elapsedMilliseconds(since: captureStarted)
        let resolveStarted = DispatchTime.now().uptimeNanoseconds
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
            text: request.text,
            options: executionOptions
        )
        warnings.append(contentsOf: cursor.warnings)
        let resolveMs = elapsedMilliseconds(since: resolveStarted)

        let window = capture.envelope.response.window
        let preparationStarted = DispatchTime.now().uptimeNanoseconds
        let preparation = backgroundTextPreparation.prepare(
            pid: window.pid,
            windowNumber: window.windowNumber
        )
        let preparationMs = elapsedMilliseconds(since: preparationStarted)
        notes.append(contentsOf: preparation.notes)
        warnings.append(contentsOf: preparation.warnings)
        let foregroundBeforeDispatch = foregroundApplication()
        let preDispatchBackgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundBeforeDispatch
        )
        guard preparation.preparedTargetWindow(requireKeyWindowRecords: true),
              preDispatchBackgroundSafety.foregroundPreserved
        else {
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

        let transportStarted = DispatchTime.now().uptimeNanoseconds
        let dispatchResult = dispatchText(
            request.text,
            baseline: preparedBeforeState,
            expected: expected,
            to: liveElement.element,
            pid: window.pid,
            foregroundBefore: foregroundBefore,
            foregroundBeforeDispatch: foregroundBeforeDispatch,
            warnings: &warnings,
            notes: &notes
        )
        let transportMs = elapsedMilliseconds(since: transportStarted)
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
                strategiesAttempted: dispatchResult.strategiesAttempted.map(\.rawValue),
                fallbackReason: dispatchResult.fallbackReason?.rawValue,
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
        let settle = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: Int((settleDelay * 1000).rounded()),
            sample: { AXActionRuntimeSupport.readTextState(liveElement.element) },
            isSatisfied: { state in
                ExactTextSettlePolicy.isSatisfied(
                    expected: expected?.valueString,
                    observed: state.valueString
                )
            }
        )
        let afterSameElementState = settle.sample
        let verificationStarted = DispatchTime.now().uptimeNanoseconds

        let postCapture: AXActionStateCapture?
        if TypeTextFastVerificationPolicy.canSkipProjectionReread(
            expected: expected,
            observed: afterSameElementState
        ) {
            postCapture = nil
            notes.append("Exact same-element value and selection evidence made a second full projection capture unnecessary.")
        } else {
            do {
                postCapture = try targetResolver.reread(after: capture)
            } catch {
                postCapture = nil
                notes.append("Post-type reread failed: \(error).")
            }
        }

        let refreshedTargetResult = postCapture.flatMap {
            targetResolver.locateRefreshedTarget(in: $0, prior: target, kind: .typeText)
        }
        let refreshedTarget = refreshedTargetResult?.target
        let refreshedTargetStrategy = refreshedTargetResult?.strategy

        var afterResolvedLiveState: TypeTextObservedStateDTO?
        if let postCapture, let refreshedTarget,
           let resolved = try? targetResolver.resolveLiveElement(for: refreshedTarget, in: postCapture)
        {
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
        let verificationMs = elapsedMilliseconds(since: verificationStarted)
        let performance = ActionPerformanceDTO(
            resolveMs: resolveMs,
            captureMs: captureMs,
            preparationMs: preparationMs,
            transportMs: transportMs,
            settleMs: Double(settle.elapsedMs),
            verificationMs: verificationMs,
            totalMs: elapsedMilliseconds(since: totalStarted)
        )

        return classifyResult(
            request: request,
            window: capture.envelope.response.window,
            target: target,
            semantic: semantic,
            liveElementResolution: liveElement.resolution,
            dispatchPrimitive: dispatchResult.primitive,
            dispatchSucceeded: dispatchResult.succeeded,
            strategiesAttempted: dispatchResult.strategiesAttempted.map(\.rawValue),
            fallbackReason: dispatchResult.fallbackReason?.rawValue,
            performance: performance,
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
        let strategiesAttempted: [AdaptiveTextStrategy]
        let fallbackReason: AdaptiveTextDispatchFallbackReason?
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
              dispatchWindow.windowNumber == initialWindow.windowNumber
        else {
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
              preDispatchBackgroundSafety.foregroundPreserved
        else {
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

        let settled = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: Int((settleDelay * 1000).rounded()),
            sample: { try? targetResolver.reread(after: preDispatchCapture) },
            isSatisfied: { capture in
                capture?.envelope.response.stateToken != preDispatchCapture.envelope.response.stateToken
            }
        )
        let postCapture = settled.sample
        if postCapture == nil {
            notes.append("Post-type reread failed for the AX-opaque target.")
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
        baseline: TypeTextObservedStateDTO,
        expected: TypeTextExpectedOutcomeDTO?,
        to element: AXUIElement,
        pid: pid_t,
        foregroundBefore: ForegroundApplicationSnapshot?,
        foregroundBeforeDispatch: ForegroundApplicationSnapshot?,
        warnings: inout [String],
        notes: inout [String]
    ) -> TextDispatchResult {
        if let expectedValue = expected?.valueString,
           AXActionRuntimeSupport.isAttributeSettable(element, attribute: kAXValueAttribute as CFString)
        {
            notes.append("Using element-bound AX value write for type_text to avoid process-scoped same-app window routing.")
            var valueStatus = "not_attempted"
            var rangeStatus: String?
            var fallbackDiagnostic: String?
            let adaptive = AdaptiveTextDispatcher.dispatch(
                baseline: baseline.valueString,
                expected: expectedValue,
                fallbackEligible: baseline.selectedTextRange != nil,
                writeAX: {
                    let valueResult = AXActionRuntimeSupport.setValue(.string(expectedValue), on: element)
                    valueStatus = AXActionRuntimeSupport.rawStatusString(for: valueResult)
                    if valueResult == .success, let selectionRange = expected?.selectionRange {
                        if AXActionRuntimeSupport.isAttributeSettable(
                            element,
                            attribute: kAXSelectedTextRangeAttribute as CFString
                        ) {
                            let rangeResult = AXActionRuntimeSupport.setSelectedTextRangeResult(
                                element,
                                location: selectionRange.location,
                                length: selectionRange.length
                            )
                            rangeStatus = AXActionRuntimeSupport.rawStatusString(for: rangeResult)
                        } else {
                            rangeStatus = "not_settable"
                        }
                    }
                    return valueResult == .success ? .success : .failure
                },
                readValue: {
                    AXActionRuntimeSupport.readTextState(element).valueString
                },
                performTargetBoundFallback: {
                    let textOperationAttribute = "AXTextOperation"
                    let selectedMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
                    guard AXActionRuntimeSupport.parameterizedAttributeNames(element)
                        .contains(textOperationAttribute),
                        let markerRange = AXActionRuntimeSupport.copyAttributeValue(
                            element,
                            attribute: selectedMarkerRangeAttribute
                        )
                    else {
                        return .unavailable
                    }
                    let payload = AXTextOperationPayload.replacing(
                        markerRange: markerRange,
                        text: text
                    )
                    let textOperationResult = AXActionRuntimeSupport.performParameterizedAttribute(
                        textOperationAttribute,
                        on: element,
                        parameter: payload as CFDictionary
                    )
                    if textOperationResult != .success {
                        fallbackDiagnostic = "AX text operation returned \(AXActionRuntimeSupport.rawStatusString(for: textOperationResult)); falling back to verified target focus."
                    }
                    return .attempted(succeeded: textOperationResult == .success)
                },
                prepareUnicodeFallback: {
                    if AXActionRuntimeSupport.readTextState(element).isFocused != true {
                        guard AXActionRuntimeSupport.isAttributeSettable(
                            element,
                            attribute: kAXFocusedAttribute as CFString
                        ), AXActionRuntimeSupport.setBoolAttributeResult(
                            element,
                            attribute: kAXFocusedAttribute as CFString,
                            value: true
                        ) == .success
                        else {
                            fallbackDiagnostic = "Fallback was blocked because the exact target could not be focused."
                            return false
                        }
                    }
                    let focus = ConditionedActionWait.poll(
                        intervalMs: 25,
                        deadlineMs: 150,
                        sample: { AXActionRuntimeSupport.readTextState(element).isFocused },
                        isSatisfied: { $0 == true }
                    )
                    let foregroundNow = foregroundApplication()
                    let safety = TypeTextBackgroundSafety.evaluate(
                        before: foregroundBefore,
                        beforeDispatch: foregroundBeforeDispatch,
                        after: foregroundNow
                    )
                    guard focus.sample == true, safety.foregroundPreserved
                    else {
                        if focus.sample != true {
                            fallbackDiagnostic = "Fallback was blocked because exact target focus could not be verified."
                        } else {
                            fallbackDiagnostic = "Fallback was blocked because the foreground application changed."
                        }
                        return false
                    }
                    return true
                },
                postUnicode: {
                    let liveState = AXActionRuntimeSupport.readTextState(element)
                    guard liveState.isFocused == true else {
                        fallbackDiagnostic = "Unicode fallback was blocked because the exact target was not focused after the AX attempt."
                        return false
                    }
                    let foregroundNow = foregroundApplication()
                    let safety = TypeTextBackgroundSafety.evaluate(
                        before: foregroundBefore,
                        beforeDispatch: foregroundBeforeDispatch,
                        after: foregroundNow
                    )
                    guard safety.foregroundPreserved else {
                        fallbackDiagnostic = "Unicode fallback was blocked because foreground preservation was lost."
                        return false
                    }
                    return AXActionRuntimeSupport.postUnicodeText(text, to: pid)
                }
            )
            notes.append("AX value write result: \(valueStatus).")
            if let rangeStatus {
                notes.append("AX caret restore result: \(rangeStatus).")
                if rangeStatus != "success" {
                    warnings.append("AX caret restore returned \(rangeStatus).")
                }
            }
            if adaptive.fallbackReason == .unchangedAXNoOp {
                notes.append("The complete immediate AX reread matched the prepared baseline; type_text prepared the exact target for one bounded fallback.")
            }
            if let fallbackDiagnostic {
                warnings.append(fallbackDiagnostic)
            }
            var primitives = [elementValueDispatchPrimitive]
            if adaptive.strategiesAttempted.contains(.axTextOperation) {
                primitives.append("AXUIElementCopyParameterizedAttributeValue(AXTextOperation)")
            }
            if adaptive.strategiesAttempted.contains(.pidUnicode) {
                primitives.append(dispatchPrimitive)
            }
            let primitive = primitives.joined(separator: " -> ")
            return TextDispatchResult(
                succeeded: adaptive.transportSucceeded,
                primitive: primitive,
                strategiesAttempted: adaptive.strategiesAttempted,
                fallbackReason: adaptive.fallbackReason
            )
        }

        if expected?.valueString == nil {
            notes.append("Exact inserted value could not be computed; type_text used PID-scoped Unicode posting.")
        } else {
            notes.append("Live AX value was not writable; type_text used PID-scoped Unicode posting.")
        }
        return TextDispatchResult(
            succeeded: AXActionRuntimeSupport.postUnicodeText(text, to: pid),
            primitive: dispatchPrimitive,
            strategiesAttempted: [.pidUnicode],
            fallbackReason: nil
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
        strategiesAttempted: [String],
        fallbackReason: String?,
        performance: ActionPerformanceDTO,
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
                strategiesAttempted: strategiesAttempted,
                fallbackReason: fallbackReason,
                performance: performance,
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
                    strategiesAttempted: strategiesAttempted,
                    fallbackReason: fallbackReason,
                    performance: performance,
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
                strategiesAttempted: strategiesAttempted,
                fallbackReason: fallbackReason,
                performance: performance,
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
                strategiesAttempted: strategiesAttempted,
                fallbackReason: fallbackReason,
                performance: performance,
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
            strategiesAttempted: strategiesAttempted,
            fallbackReason: fallbackReason,
            performance: performance,
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
        strategiesAttempted: [String] = [],
        fallbackReason: String? = nil,
        performance: ActionPerformanceDTO? = nil,
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
            strategiesAttempted: strategiesAttempted,
            fallbackReason: fallbackReason,
            performance: performance,
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
              let range = beforeState.selectedTextRange
        else {
            return nil
        }

        let string = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location >= 0,
              nsRange.length >= 0,
              nsRange.location + nsRange.length <= string.length
        else {
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

    private func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

import ApplicationServices
import Foundation

struct TypeTextRouteService {
    private let executionOptions: ActionExecutionOptions
    private let targetResolver: AXActionTargetResolver
    private let backgroundTextPreparation: BackgroundTextPreparation
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let foregroundFallbackCoordinator: ForegroundFallbackCoordinator
    private let dispatchPrimitive = "CGEvent.keyboardSetUnicodeString + postToPid"
    private let elementValueDispatchPrimitive = "AXUIElementSetAttributeValue(kAXValueAttribute) + AXUIElementSetAttributeValue(kAXSelectedTextRangeAttribute)"
    private let settleDelay: TimeInterval = 0.35

    init(
        executionOptions: ActionExecutionOptions = .visualCursorEnabled,
        backgroundTextPreparation: BackgroundTextPreparation = .live,
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? = ForegroundApplicationSnapshot.capture,
        foregroundFallbackCoordinator: ForegroundFallbackCoordinator? = nil
    ) {
        self.executionOptions = executionOptions
        self.backgroundTextPreparation = backgroundTextPreparation
        self.foregroundApplication = foregroundApplication
        self.foregroundFallbackCoordinator = foregroundFallbackCoordinator
            ?? ForegroundFallbackCoordinator(foregroundApplication: foregroundApplication)
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
        let preparedBeforeState = AXActionRuntimeSupport.readTextState(liveElement.element)
        let expected = expectedOutcome(from: preparedBeforeState, text: request.text)
        let foregroundAtDispatchStart = foregroundApplication()
        guard BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: foregroundBefore,
            current: foregroundAtDispatchStart,
            targetPID: window.pid
        ) else {
            AXCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: foregroundAtDispatchStart,
                after: foregroundAtDispatchStart
            )
            return response(
                classification: .effectNotVerified,
                failureDomain: .backgroundSafety,
                summary: "Text dispatch was blocked because an unrelated foreground change occurred before transport.",
                window: window,
                target: target,
                text: request.text,
                dispatchPrimitive: nil,
                dispatchSucceeded: nil,
                semanticAppropriate: semantic.appropriate,
                semanticReasons: semantic.reasons,
                liveElementResolution: liveElement.resolution,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil,
                backgroundSafety: backgroundSafety
            )
        }

        let transportStarted = DispatchTime.now().uptimeNanoseconds
        let dispatchResult = dispatchText(
            request.text,
            baseline: preparedBeforeState,
            expected: expected,
            to: liveElement.element,
            pid: window.pid,
            windowNumber: window.windowNumber,
            foregroundBefore: foregroundBefore,
            foregroundAtDispatchStart: foregroundAtDispatchStart,
            warnings: &warnings,
            notes: &notes
        )
        let transportMs = elapsedMilliseconds(since: transportStarted)
        if dispatchResult.succeeded == false,
           dispatchResult.strategiesAttempted.isEmpty
        {
            AXCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
            let attempt = TypeTextAttemptTelemetry(
                dispatchSucceeded: false,
                strategiesAttempted: []
            )
            let foregroundRestored = TypeTextOutcomePolicy.canRestoreForeground(
                attempt: attempt,
                verificationCompleted: false
            ) && foregroundFallbackCoordinator.restore(
                original: foregroundBefore,
                targetPID: window.pid,
                fallbackUsed: dispatchResult.foregroundFallbackUsed
            )
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: dispatchResult.foregroundBeforeDispatch,
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
                    verificationNotes: ["Text transport was blocked before any strategy was attempted."]
                ),
                backgroundSafety: backgroundSafety,
                foregroundFallbackUsed: dispatchResult.foregroundFallbackUsed,
                foregroundRestored: foregroundRestored
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
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: dispatchResult.succeeded,
            strategiesAttempted: dispatchResult.strategiesAttempted
        )
        let foregroundRestored = TypeTextOutcomePolicy.canRestoreForeground(
            attempt: attempt,
            verificationCompleted: true
        ) && foregroundFallbackCoordinator.restore(
            original: foregroundBefore,
            targetPID: window.pid,
            fallbackUsed: dispatchResult.foregroundFallbackUsed
        )
        let backgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: dispatchResult.foregroundBeforeDispatch,
            after: foregroundApplication()
        )
        let verificationMs = elapsedMilliseconds(since: verificationStarted)
        let performance = ActionPerformanceDTO(
            resolveMs: resolveMs,
            captureMs: captureMs,
            preparationMs: dispatchResult.preparationMs,
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
            backgroundSafety: backgroundSafety,
            foregroundFallbackUsed: dispatchResult.foregroundFallbackUsed,
            foregroundRestored: foregroundRestored
        )
    }

    private struct TextDispatchResult {
        let succeeded: Bool
        let primitive: String
        let strategiesAttempted: [AdaptiveTextStrategy]
        let fallbackReason: AdaptiveTextDispatchFallbackReason?
        let foregroundFallbackUsed: Bool
        let foregroundBeforeDispatch: ForegroundApplicationSnapshot?
        let preparationMs: Double
    }

    private struct PIDUnicodePreparationResult {
        let permitted: Bool
        let foregroundFallbackUsed: Bool
        let foregroundBeforeDispatch: ForegroundApplicationSnapshot?
        let elapsedMs: Double
        let warnings: [String]
        let notes: [String]
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

        let preparation = preparePIDUnicodeFallback(
            originalForeground: foregroundBefore,
            targetPID: dispatchWindow.pid,
            windowNumber: dispatchWindow.windowNumber,
            exactTarget: nil
        )
        notes.append(contentsOf: preparation.notes)
        warnings.append(contentsOf: preparation.warnings)
        let foregroundBeforeDispatch = preparation.foregroundBeforeDispatch
        let preDispatchBackgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundBeforeDispatch
        )
        guard preparation.permitted else {
            let preflightFailure = "PID-scoped Unicode posting was not attempted because foreground preparation was blocked before dispatch."
            warnings.append(preflightFailure)
            notes.append(preflightFailure)
            return response(
                classification: .effectNotVerified,
                failureDomain: .backgroundSafety,
                summary: "Opaque focused-surface typing was blocked before text dispatch.",
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
                backgroundSafety: preDispatchBackgroundSafety,
                foregroundFallbackUsed: preparation.foregroundFallbackUsed,
                foregroundRestored: false
            )
        }

        guard foregroundApplication() == foregroundBeforeDispatch else {
            let warning = "PID-scoped Unicode posting was not attempted because the foreground application changed after preparation."
            warnings.append(warning)
            notes.append(warning)
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: foregroundBeforeDispatch,
                after: foregroundApplication()
            )
            return response(
                classification: .effectNotVerified,
                failureDomain: .backgroundSafety,
                summary: "Opaque focused-surface typing was blocked before text dispatch.",
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
                backgroundSafety: backgroundSafety,
                foregroundFallbackUsed: preparation.foregroundFallbackUsed,
                foregroundRestored: false
            )
        }

        let dispatched = AXActionRuntimeSupport.postUnicodeText(request.text, to: dispatchWindow.pid)
        let foregroundFallbackUsed = preparation.foregroundFallbackUsed
            || (foregroundBefore?.pid != dispatchWindow.pid
                && foregroundApplication()?.pid == dispatchWindow.pid)
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
        guard dispatched else {
            let attempt = TypeTextAttemptTelemetry(
                dispatchSucceeded: false,
                strategiesAttempted: [.pidUnicode]
            )
            let foregroundRestored = TypeTextOutcomePolicy.canRestoreForeground(
                attempt: attempt,
                verificationCompleted: true
            ) && foregroundFallbackCoordinator.restore(
                original: foregroundBefore,
                targetPID: dispatchWindow.pid,
                fallbackUsed: foregroundFallbackUsed
            )
            let backgroundSafety = TypeTextBackgroundSafety.evaluate(
                before: foregroundBefore,
                beforeDispatch: foregroundBeforeDispatch,
                after: foregroundApplication()
            )
            let decision = TypeTextOutcomePolicy.classifyOpaqueDispatch(
                attempt: attempt,
                foregroundPreserved: backgroundSafety.foregroundPreserved
            )
            return response(
                classification: decision.classification,
                failureDomain: decision.failureDomain,
                summary: decision.summary,
                window: dispatchWindow,
                target: nil,
                text: request.text,
                dispatchPrimitive: dispatchPrimitive,
                dispatchSucceeded: false,
                strategiesAttempted: [AdaptiveTextStrategy.pidUnicode.rawValue],
                semanticAppropriate: nil,
                semanticReasons: [],
                liveElementResolution: nil,
                preStateToken: preDispatchCapture.envelope.response.stateToken,
                postStateToken: postCapture?.envelope.response.stateToken,
                cursor: cursor,
                warnings: warnings,
                notes: notes,
                verification: nil,
                backgroundSafety: backgroundSafety,
                foregroundFallbackUsed: foregroundFallbackUsed,
                foregroundRestored: foregroundRestored
            )
        }

        notes.append(
            "Explicit opaque focused-surface fallback posted Unicode after controlled foreground preparation; call get_window_state with imageMode path or base64 to verify the result before continuing."
        )
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: true,
            strategiesAttempted: [.pidUnicode]
        )
        let foregroundRestored = TypeTextOutcomePolicy.canRestoreForeground(
            attempt: attempt,
            verificationCompleted: true
        ) && foregroundFallbackCoordinator.restore(
            original: foregroundBefore,
            targetPID: dispatchWindow.pid,
            fallbackUsed: foregroundFallbackUsed
        )
        let backgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundApplication()
        )
        let decision = TypeTextOutcomePolicy.classifyOpaqueDispatch(
            attempt: attempt,
            foregroundPreserved: backgroundSafety.foregroundPreserved
        )
        return response(
            classification: decision.classification,
            failureDomain: decision.failureDomain,
            summary: decision.summary,
            window: dispatchWindow,
            target: nil,
            text: request.text,
            dispatchPrimitive: dispatchPrimitive,
            dispatchSucceeded: true,
            strategiesAttempted: [AdaptiveTextStrategy.pidUnicode.rawValue],
            semanticAppropriate: nil,
            semanticReasons: [],
            liveElementResolution: nil,
            preStateToken: preDispatchCapture.envelope.response.stateToken,
            postStateToken: postCapture?.envelope.response.stateToken,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            verification: nil,
            backgroundSafety: backgroundSafety,
            foregroundFallbackUsed: foregroundFallbackUsed,
            foregroundRestored: foregroundRestored
        )
    }

    private func preparePIDUnicodeFallback(
        originalForeground: ForegroundApplicationSnapshot?,
        targetPID: pid_t,
        windowNumber: Int,
        exactTarget: AXUIElement?
    ) -> PIDUnicodePreparationResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let foregroundAtPreparationStart = foregroundApplication()
        guard BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: originalForeground,
            current: foregroundAtPreparationStart,
            targetPID: targetPID
        ) else {
            return PIDUnicodePreparationResult(
                permitted: false,
                foregroundFallbackUsed: false,
                foregroundBeforeDispatch: foregroundAtPreparationStart,
                elapsedMs: elapsedMilliseconds(since: started),
                warnings: ["PID-scoped Unicode fallback was blocked before WindowServer or AX focus effects because an unrelated foreground change occurred."],
                notes: []
            )
        }
        let windowPreparation = backgroundTextPreparation.prepareUnicodeFallback(
            pid: targetPID,
            windowNumber: windowNumber
        )
        var warnings = windowPreparation.warnings
        var notes = windowPreparation.notes
        var backgroundPrepared = windowPreparation.preparedTargetWindow(
            requireKeyWindowRecords: true
        )

        if let exactTarget {
            if AXActionRuntimeSupport.readTextState(exactTarget).isFocused != true {
                let focused = AXActionRuntimeSupport.isAttributeSettable(
                    exactTarget,
                    attribute: kAXFocusedAttribute as CFString
                ) && AXActionRuntimeSupport.setBoolAttributeResult(
                    exactTarget,
                    attribute: kAXFocusedAttribute as CFString,
                    value: true
                ) == .success
                if focused == false {
                    warnings.append("Unicode fallback could not focus the exact AX target in the background.")
                }
            }
            let focus = ConditionedActionWait.poll(
                intervalMs: 25,
                deadlineMs: 150,
                sample: { AXActionRuntimeSupport.readTextState(exactTarget).isFocused },
                isSatisfied: { $0 == true }
            )
            backgroundPrepared = backgroundPrepared && focus.sample == true
            if focus.sample != true {
                notes.append("Exact AX target focus was not verified before foreground coordination.")
            }
        }

        let outcome = foregroundFallbackCoordinator.prepare(
            original: originalForeground,
            targetPID: targetPID,
            backgroundPrepared: backgroundPrepared
        )
        var foregroundTargetPrepared = true
        if outcome.mode == .foregroundFallback,
           let exactTarget,
           AXActionRuntimeSupport.readTextState(exactTarget).isFocused != true
        {
            let focused = AXActionRuntimeSupport.isAttributeSettable(
                exactTarget,
                attribute: kAXFocusedAttribute as CFString
            ) && AXActionRuntimeSupport.setBoolAttributeResult(
                exactTarget,
                attribute: kAXFocusedAttribute as CFString,
                value: true
            ) == .success
            let focus = ConditionedActionWait.poll(
                intervalMs: 25,
                deadlineMs: 150,
                sample: { AXActionRuntimeSupport.readTextState(exactTarget).isFocused },
                isSatisfied: { $0 == true }
            )
            foregroundTargetPrepared = focused && focus.sample == true
            if foregroundTargetPrepared == false {
                warnings.append("Unicode fallback could not focus the exact AX target after foreground activation.")
            }
        }
        switch outcome.mode {
        case .background:
            return PIDUnicodePreparationResult(
                permitted: true,
                foregroundFallbackUsed: false,
                foregroundBeforeDispatch: outcome.foregroundBeforeDispatch,
                elapsedMs: elapsedMilliseconds(since: started),
                warnings: warnings,
                notes: notes
            )
        case .foregroundFallback:
            notes.append("PID-scoped Unicode fallback continued with the exact target application in the foreground.")
            return PIDUnicodePreparationResult(
                permitted: foregroundTargetPrepared,
                foregroundFallbackUsed: true,
                foregroundBeforeDispatch: outcome.foregroundBeforeDispatch,
                elapsedMs: elapsedMilliseconds(since: started),
                warnings: warnings,
                notes: notes
            )
        case .blockedByUserChange:
            warnings.append("PID-scoped Unicode fallback was blocked before dispatch because foreground coordination did not preserve the current user choice.")
            return PIDUnicodePreparationResult(
                permitted: false,
                foregroundFallbackUsed: false,
                foregroundBeforeDispatch: outcome.foregroundBeforeDispatch,
                elapsedMs: elapsedMilliseconds(since: started),
                warnings: warnings,
                notes: notes
            )
        }
    }

    private func dispatchText(
        _ text: String,
        baseline: TypeTextObservedStateDTO,
        expected: TypeTextExpectedOutcomeDTO?,
        to element: AXUIElement,
        pid: pid_t,
        windowNumber: Int,
        foregroundBefore: ForegroundApplicationSnapshot?,
        foregroundAtDispatchStart: ForegroundApplicationSnapshot?,
        warnings: inout [String],
        notes: inout [String]
    ) -> TextDispatchResult {
        var foregroundBeforeDispatch = foregroundAtDispatchStart
        var foregroundFallbackUsed = false
        var preparationMs = 0.0
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
                    let preparation = preparePIDUnicodeFallback(
                        originalForeground: foregroundBefore,
                        targetPID: pid,
                        windowNumber: windowNumber,
                        exactTarget: element
                    )
                    notes.append(contentsOf: preparation.notes)
                    warnings.append(contentsOf: preparation.warnings)
                    foregroundBeforeDispatch = preparation.foregroundBeforeDispatch
                    foregroundFallbackUsed = preparation.foregroundFallbackUsed
                    preparationMs = preparation.elapsedMs
                    guard preparation.permitted else {
                        fallbackDiagnostic = "Unicode fallback was blocked before text dispatch."
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
                    guard foregroundApplication() == foregroundBeforeDispatch else {
                        fallbackDiagnostic = "Unicode fallback was blocked because the foreground application changed after preparation."
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
            if foregroundFallbackUsed == false,
               foregroundBefore?.pid != pid,
               foregroundApplication()?.pid == pid
            {
                foregroundFallbackUsed = true
                notes.append("The exact target application became foreground during text transport; restoration remains conditional on it staying foreground through verification.")
            }
            return TextDispatchResult(
                succeeded: adaptive.transportSucceeded,
                primitive: primitive,
                strategiesAttempted: adaptive.strategiesAttempted,
                fallbackReason: adaptive.fallbackReason,
                foregroundFallbackUsed: foregroundFallbackUsed,
                foregroundBeforeDispatch: foregroundBeforeDispatch,
                preparationMs: preparationMs
            )
        }

        if expected?.valueString == nil {
            notes.append("Exact inserted value could not be computed; type_text used PID-scoped Unicode posting.")
        } else {
            notes.append("Live AX value was not writable; type_text used PID-scoped Unicode posting.")
        }
        let preparation = preparePIDUnicodeFallback(
            originalForeground: foregroundBefore,
            targetPID: pid,
            windowNumber: windowNumber,
            exactTarget: element
        )
        notes.append(contentsOf: preparation.notes)
        warnings.append(contentsOf: preparation.warnings)
        foregroundBeforeDispatch = preparation.foregroundBeforeDispatch
        foregroundFallbackUsed = preparation.foregroundFallbackUsed
        preparationMs = preparation.elapsedMs
        guard preparation.permitted else {
            return TextDispatchResult(
                succeeded: false,
                primitive: dispatchPrimitive,
                strategiesAttempted: [],
                fallbackReason: nil,
                foregroundFallbackUsed: foregroundFallbackUsed,
                foregroundBeforeDispatch: foregroundBeforeDispatch,
                preparationMs: preparationMs
            )
        }
        guard foregroundApplication() == foregroundBeforeDispatch else {
            warnings.append("Unicode fallback was blocked because the foreground application changed after preparation.")
            return TextDispatchResult(
                succeeded: false,
                primitive: dispatchPrimitive,
                strategiesAttempted: [],
                fallbackReason: nil,
                foregroundFallbackUsed: foregroundFallbackUsed,
                foregroundBeforeDispatch: foregroundBeforeDispatch,
                preparationMs: preparationMs
            )
        }
        let unicodeSucceeded = AXActionRuntimeSupport.postUnicodeText(text, to: pid)
        if foregroundFallbackUsed == false,
           foregroundBefore?.pid != pid,
           foregroundApplication()?.pid == pid
        {
            foregroundFallbackUsed = true
            notes.append("The target application became foreground during PID-scoped Unicode transport; restoration remains conditional on it staying foreground through verification.")
        }
        return TextDispatchResult(
            succeeded: unicodeSucceeded,
            primitive: dispatchPrimitive,
            strategiesAttempted: [.pidUnicode],
            fallbackReason: nil,
            foregroundFallbackUsed: foregroundFallbackUsed,
            foregroundBeforeDispatch: foregroundBeforeDispatch,
            preparationMs: preparationMs
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
        backgroundSafety: TypeTextBackgroundSafetyDTO,
        foregroundFallbackUsed: Bool,
        foregroundRestored: Bool
    ) -> TypeTextResponse {
        let decision = TypeTextOutcomePolicy.classifySemanticDispatch(
            exactValueMatch: verification.exactValueMatch,
            exactSelectionMatch: verification.exactSelectionMatch,
            targetRelocated: verification.targetRelocated,
            postStateTokenAvailable: postStateToken != nil,
            foregroundPreserved: backgroundSafety.foregroundPreserved
        )
        return response(
            classification: decision.classification,
            failureDomain: decision.failureDomain,
            summary: decision.summary,
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
            backgroundSafety: backgroundSafety,
            foregroundFallbackUsed: foregroundFallbackUsed,
            foregroundRestored: foregroundRestored
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
        backgroundSafety: TypeTextBackgroundSafetyDTO? = nil,
        foregroundFallbackUsed: Bool = false,
        foregroundRestored: Bool = false
    ) -> TypeTextResponse {
        let strategies = strategiesAttempted.compactMap(AdaptiveTextStrategy.init(rawValue:))
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: dispatchSucceeded,
            strategiesAttempted: strategies
        )
        return TypeTextResponse(
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
            verification: verification,
            retrySafe: attempt.retrySafe,
            foregroundFallbackUsed: foregroundFallbackUsed,
            foregroundRestored: foregroundRestored
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

import AppKit
import Foundation

enum PasteFallbackFocusPolicy {
    static func allows(isFocused: Bool?, foregroundPreserved: Bool) -> Bool {
        isFocused == true && foregroundPreserved
    }
}

struct PasteRouteService {
    private let executionOptions: ActionExecutionOptions
    private let targetResolver: AXActionTargetResolver
    private let clickRouteService: ClickRouteService
    private let pressKeyRouteService: PressKeyRouteService
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let settleDelay: TimeInterval = 0.35

    init(
        executionOptions: ActionExecutionOptions = .visualCursorEnabled,
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? = ForegroundApplicationSnapshot.capture
    ) {
        self.executionOptions = executionOptions
        self.foregroundApplication = foregroundApplication
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
        clickRouteService = ClickRouteService(executionOptions: executionOptions)
        pressKeyRouteService = PressKeyRouteService(executionOptions: executionOptions)
    }

    func paste(request: PasteRequest) throws -> PasteResponse {
        let foregroundBefore = foregroundApplication()
        let initialCapture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500
        )
        var warnings = targetResolver.stateTokenWarnings(
            suppliedStateToken: request.stateToken,
            liveStateToken: initialCapture.envelope.response.stateToken
        )
        var notes: [String] = []
        guard let candidate = targetResolver.resolveTarget(request.target, in: initialCapture, kind: .typeText) else {
            return failure(
                request: request,
                classification: .verifierAmbiguous,
                domain: .targeting,
                summary: targetResolver.targetResolutionFailureDescription(for: request.target, in: initialCapture),
                window: initialCapture.envelope.response.window,
                target: nil,
                cursor: notAttemptedCursor(request, reason: "Paste target could not be resolved."),
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes
            )
        }
        let target = candidate.target
        let secureDecision = RuntimeSafetyPolicy.evaluateSecureTextEntry(
            rawRole: target.rawRole,
            rawSubrole: target.rawSubrole,
            displayRole: target.displayRole,
            confirmed: request.confirm == true
        )
        guard secureDecision.blocked == false else {
            return failure(
                request: request,
                classification: .unsupported,
                domain: .unsupported,
                summary: secureDecision.reason ?? "Pasting into secure text fields requires explicit confirmation.",
                window: initialCapture.envelope.response.window,
                target: target,
                cursor: notAttemptedCursor(request, reason: "Paste was blocked by secure-field policy."),
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes
            )
        }
        let semantic = targetResolver.semanticSuitability(for: target, kind: .typeText)
        guard semantic.appropriate else {
            return failure(
                request: request,
                classification: .unsupported,
                domain: .unsupported,
                summary: "The resolved node is not a semantic text-entry target for paste.",
                window: initialCapture.envelope.response.window,
                target: target,
                cursor: notAttemptedCursor(request, reason: "Paste target was semantically unsupported."),
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes
            )
        }

        guard let liveElement = try? targetResolver.resolveLiveElement(for: target, in: initialCapture) else {
            return failure(
                request: request,
                classification: .verifierAmbiguous,
                domain: .targeting,
                summary: "Paste target could not be resolved to its live AX element.",
                window: initialCapture.envelope.response.window,
                target: target,
                cursor: notAttemptedCursor(request, reason: "Paste live target resolution failed."),
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes
            )
        }
        let beforeState = AXActionRuntimeSupport.readTextState(liveElement.element)
        guard let insertion = PasteboardPayload.plainText(request.content, format: request.format),
              let expectedValue = expectedValue(before: beforeState, insertion: insertion)
        else {
            return failure(
                request: request,
                classification: .verifierAmbiguous,
                domain: .verification,
                summary: "Paste could not compute an exact expected text value for this target.",
                window: initialCapture.envelope.response.window,
                target: target,
                cursor: notAttemptedCursor(request, reason: "Paste exact outcome could not be computed."),
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes
            )
        }

        let directCursor = AXCursorTargeting.prepareTypeText(
            requested: request.cursor,
            target: target,
            window: initialCapture.envelope.response.window,
            text: insertion,
            options: executionOptions
        )
        warnings.append(contentsOf: directCursor.warnings)
        var responseCursor = directCursor

        let foregroundBeforeDispatch = foregroundApplication()
        let preSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundBeforeDispatch
        )
        guard preSafety.foregroundPreserved else {
            return failure(
                request: request,
                classification: .effectNotVerified,
                domain: .backgroundSafety,
                summary: "Paste was blocked because foreground preservation was lost before dispatch.",
                window: initialCapture.envelope.response.window,
                target: target,
                cursor: directCursor,
                preStateToken: initialCapture.envelope.response.stateToken,
                warnings: warnings,
                notes: notes,
                backgroundSafety: preSafety
            )
        }

        let textOperationAttribute = "AXTextOperation"
        let plainTextRole = target.rawRole == "AXTextField" || target.rawRole == "AXTextArea"
        let requiresRichClipboard = request.format == .html && plainTextRole == false
        let targetBoundEligible = requiresRichClipboard == false
            && AXActionRuntimeSupport.parameterizedAttributeNames(liveElement.element)
            .contains(textOperationAttribute)
        notes.append(
            "Adaptive paste target-bound eligibility: \(targetBoundEligible); rawRole=\(target.rawRole ?? "nil"); format=\(request.format.rawValue)."
        )

        var clickResponse: ClickResponse?
        var pressResponse: PressKeyResponse?
        var transaction: PasteTransactionResult?
        var directDiagnostic: String?
        let adaptive = AdaptivePasteDispatcher.dispatch(
            baseline: beforeState.valueString,
            expected: expectedValue,
            targetBoundEligible: targetBoundEligible,
            performTargetBoundOperation: {
                if let selection = beforeState.selectedTextRange {
                    let selectionResult = AXActionRuntimeSupport.setSelectedTextRangeResult(
                        liveElement.element,
                        location: selection.location,
                        length: selection.length
                    )
                    if selectionResult != .success {
                        directDiagnostic = "AX selection preparation returned \(AXActionRuntimeSupport.rawStatusString(for: selectionResult))."
                    }
                }
                guard let markerRange = AXActionRuntimeSupport.copyAttributeValue(
                    liveElement.element,
                    attribute: "AXSelectedTextMarkerRange" as CFString
                ) else {
                    directDiagnostic = directDiagnostic ?? "AX selected text marker range was unavailable after selection preparation."
                    return false
                }
                let result = AXActionRuntimeSupport.performParameterizedAttribute(
                    textOperationAttribute,
                    on: liveElement.element,
                    parameter: AXTextOperationPayload.replacing(
                        markerRange: markerRange,
                        text: insertion
                    ) as CFDictionary
                )
                if result != .success {
                    directDiagnostic = "AX text operation returned \(AXActionRuntimeSupport.rawStatusString(for: result))."
                }
                return result == .success
            },
            readValue: {
                AXActionRuntimeSupport.readTextState(liveElement.element).valueString
            },
            performClipboardPaste: {
                clickResponse = try? clickRouteService.click(
                    request: ClickRequest(
                        window: request.window,
                        stateToken: initialCapture.envelope.response.stateToken,
                        interactionToken: initialCapture.envelope.response.interactionToken,
                        target: request.target,
                        clickCount: 1,
                        cursor: request.cursor,
                        includeMenuBar: request.includeMenuBar,
                        maxNodes: request.maxNodes,
                        imageMode: .omit,
                        confirm: request.confirm
                    )
                )
                let focusSettle = ConditionedActionWait.poll(
                    intervalMs: 25,
                    deadlineMs: 150,
                    sample: { AXActionRuntimeSupport.readTextState(liveElement.element).isFocused },
                    isSatisfied: { $0 == true }
                )
                let safetyAfterFocus = TypeTextBackgroundSafety.evaluate(
                    before: foregroundBefore,
                    beforeDispatch: foregroundBeforeDispatch,
                    after: foregroundApplication()
                )
                guard PasteFallbackFocusPolicy.allows(
                    isFocused: focusSettle.sample,
                    foregroundPreserved: safetyAfterFocus.foregroundPreserved
                ) else {
                    directDiagnostic = focusSettle.sample == true
                        ? "Clipboard paste was blocked because target preparation changed the foreground application."
                        : "Clipboard paste was blocked because the exact target did not become focused."
                    return false
                }
                transaction = PasteTransaction.perform(
                    content: request.content,
                    format: request.format,
                    pasteboard: .general,
                    dispatch: {
                        pressResponse = try? pressKeyRouteService.pressKey(
                            request: PressKeyRequest(
                                window: request.window,
                                stateToken: initialCapture.envelope.response.stateToken,
                                interactionToken: initialCapture.envelope.response.interactionToken,
                                key: "command+v",
                                cursor: request.cursor,
                                includeMenuBar: request.includeMenuBar,
                                maxNodes: request.maxNodes,
                                imageMode: .omit,
                                debug: request.debug,
                                confirm: request.confirm
                            )
                        )
                        return pressResponse?.ok == true
                    }
                )
                return transaction?.dispatchSucceeded == true
            }
        )
        AXCursorTargeting.finishTypeText(cursor: directCursor, text: insertion)
        warnings.append(contentsOf: clickResponse?.warnings ?? [])
        warnings.append(contentsOf: pressResponse?.warnings ?? [])
        notes.append(contentsOf: clickResponse?.notes ?? [])
        notes.append(contentsOf: pressResponse?.notes ?? [])
        if let directDiagnostic {
            warnings.append(directDiagnostic)
        }
        if adaptive.strategiesAttempted == [.axTextOperation] {
            notes.append("Paste used the target-bound AX text operation; the system pasteboard was not modified.")
        } else {
            notes.append("Paste used the temporary-pasteboard Command-V fallback and restored the original pasteboard snapshot.")
        }
        if let fallbackCursor = pressResponse?.cursor ?? clickResponse?.cursor {
            responseCursor = fallbackCursor
        }

        let sameElementAfter: TypeTextObservedStateDTO = if adaptive.transportSucceeded {
            ConditionedActionWait.poll(
                intervalMs: 25,
                deadlineMs: Int((settleDelay * 1000).rounded()),
                sample: { AXActionRuntimeSupport.readTextState(liveElement.element) },
                isSatisfied: { state in
                    ExactTextSettlePolicy.isSatisfied(
                        expected: expectedValue,
                        observed: state.valueString
                    )
                }
            ).sample
        } else {
            AXActionRuntimeSupport.readTextState(liveElement.element)
        }
        let postCapture = try? targetResolver.reread(after: initialCapture)
        let postTargetResult = postCapture.flatMap {
            targetResolver.locateRefreshedTarget(in: $0, prior: target, kind: .typeText)
        }
        var postLiveValue: String?
        if let postCapture, let postTarget = postTargetResult?.target,
           let postLive = try? targetResolver.resolveLiveElement(for: postTarget, in: postCapture)
        {
            postLiveValue = AXActionRuntimeSupport.readTextState(postLive.element).valueString
        }
        let afterValue = postLiveValue ?? sameElementAfter.valueString
        let exactMatch = afterValue == expectedValue
        let backgroundSafety = TypeTextBackgroundSafety.evaluate(
            before: foregroundBefore,
            beforeDispatch: foregroundBeforeDispatch,
            after: foregroundApplication()
        )
        let verification = PasteVerificationDTO(
            beforeValue: beforeState.valueString,
            expectedValue: expectedValue,
            afterValue: afterValue,
            exactValueMatch: exactMatch,
            targetRelocated: postTargetResult?.target != nil,
            refreshedTargetMatchStrategy: postTargetResult?.strategy
        )

        let classification: ActionClassificationDTO
        let domain: ActionFailureDomainDTO?
        let summary: String
        if backgroundSafety.foregroundPreserved == false {
            classification = .effectNotVerified
            domain = .backgroundSafety
            summary = "Paste did not preserve the user's foreground application."
        } else if adaptive.transportSucceeded == false {
            classification = .effectNotVerified
            domain = .transport
            summary = "Every eligible paste transport failed or a partial mutation was detected."
        } else if transaction?.restoreSucceeded == false {
            classification = .effectNotVerified
            domain = .verification
            summary = "Paste dispatched, but the original clipboard could not be restored."
        } else if exactMatch {
            classification = .success
            domain = nil
            summary = transaction == nil
                ? "Paste matched the exact expected target value without modifying the system pasteboard."
                : "Paste matched the exact expected target value and restored the clipboard."
        } else {
            classification = .effectNotVerified
            domain = .verification
            summary = "Paste dispatched, but the exact expected target value did not verify."
        }

        return PasteResponse(
            contractVersion: ContractVersion.current,
            ok: classification == .success,
            classification: classification,
            failureDomain: domain,
            summary: summary,
            window: initialCapture.envelope.response.window,
            target: postTargetResult?.target?.dto ?? target.dto,
            format: request.format,
            contentLength: request.content.utf8.count,
            dispatchPrimitive: adaptive.strategiesAttempted.map(\.rawValue).joined(separator: " -> "),
            dispatchSucceeded: adaptive.transportSucceeded,
            pasteboardRestored: transaction?.restoreSucceeded ?? true,
            preStateToken: initialCapture.envelope.response.stateToken,
            postStateToken: postCapture?.envelope.response.stateToken,
            cursor: responseCursor,
            warnings: warnings,
            notes: notes,
            backgroundSafety: backgroundSafety,
            verification: verification
        )
    }

    private func expectedValue(before: TypeTextObservedStateDTO, insertion: String) -> String? {
        guard let value = before.valueString, let range = before.selectedTextRange else { return nil }
        let source = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location >= 0, nsRange.length >= 0, NSMaxRange(nsRange) <= source.length else {
            return nil
        }
        return source.replacingCharacters(in: nsRange, with: insertion)
    }

    private func notAttemptedCursor(_ request: PasteRequest, reason: String) -> ActionCursorTargetResponseDTO {
        AXCursorTargeting.notAttempted(requested: request.cursor, reason: reason, options: executionOptions)
    }

    private func failure(
        request: PasteRequest,
        classification: ActionClassificationDTO,
        domain: ActionFailureDomainDTO?,
        summary: String,
        window: ResolvedWindowDTO?,
        target: AXActionTargetSnapshot?,
        cursor: ActionCursorTargetResponseDTO,
        preStateToken: String?,
        warnings: [String],
        notes: [String],
        backgroundSafety: TypeTextBackgroundSafetyDTO? = nil
    ) -> PasteResponse {
        PasteResponse(
            contractVersion: ContractVersion.current,
            ok: false,
            classification: classification,
            failureDomain: domain,
            summary: summary,
            window: window,
            target: target?.dto,
            format: request.format,
            contentLength: request.content.utf8.count,
            dispatchPrimitive: nil,
            dispatchSucceeded: nil,
            pasteboardRestored: true,
            preStateToken: preStateToken,
            postStateToken: nil,
            cursor: cursor,
            warnings: warnings,
            notes: notes,
            backgroundSafety: backgroundSafety,
            verification: nil
        )
    }
}

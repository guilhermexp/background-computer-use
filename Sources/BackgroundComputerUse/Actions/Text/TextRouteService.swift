import ApplicationServices
import Foundation

struct TextRouteService {
    private let targetResolver: AXActionTargetResolver

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
    }

    func readText(request: ReadTextRequest) throws -> ReadTextResponse {
        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500
        )
        guard let candidate = targetResolver.resolveTarget(request.target, in: capture, kind: .typeText) else {
            throw AXActionTargetResolverError.unresolvedTarget(
                targetResolver.targetResolutionFailureDescription(for: request.target, in: capture)
            )
        }
        let target = candidate.target
        let liveElement = try targetResolver.resolveLiveElement(for: target, in: capture)
        let value = AXActionRuntimeSupport.stringAttribute(
            liveElement.element,
            attribute: kAXValueAttribute as CFString
        ) ?? ""
        let chunk = try TextChunker.chunk(
            value,
            offset: request.offset ?? 0,
            length: request.length ?? 20_000
        )

        return ReadTextResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            summary: "Read \(chunk.text.count) of \(chunk.totalLength) characters from the target.",
            window: capture.envelope.response.window,
            target: target.dto,
            chunk: chunk,
            warnings: []
        )
    }

    func selectText(request: SelectTextRequest) throws -> SelectTextResponse {
        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500
        )
        let warnings = targetResolver.stateTokenWarnings(
            suppliedStateToken: request.stateToken,
            liveStateToken: capture.envelope.response.stateToken
        )

        guard let candidate = targetResolver.resolveTarget(request.target, in: capture, kind: .typeText) else {
            return selectResponse(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: targetResolver.targetResolutionFailureDescription(for: request.target, in: capture),
                window: capture.envelope.response.window,
                target: nil,
                selectedRange: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
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
            return selectResponse(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: secureDecision.reason ?? "Selection in secure text fields is blocked.",
                window: capture.envelope.response.window,
                target: target.dto,
                selectedRange: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
            )
        }

        let liveElement: AXActionResolvedLiveElement
        do {
            liveElement = try targetResolver.resolveLiveElement(for: target, in: capture)
        } catch {
            return selectResponse(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: String(describing: error),
                window: capture.envelope.response.window,
                target: target.dto,
                selectedRange: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
            )
        }

        guard let value = AXActionRuntimeSupport.stringAttribute(
            liveElement.element,
            attribute: kAXValueAttribute as CFString
        ) else {
            return selectResponse(
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: "The target has no readable AXValue text to select within.",
                window: capture.envelope.response.window,
                target: target.dto,
                selectedRange: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
            )
        }

        let plannedRange: CFRange
        do {
            plannedRange = try TextSelectionPlanner.range(
                in: value,
                query: request.text,
                occurrence: request.occurrence ?? 1,
                position: request.position ?? .select
            )
        } catch {
            return selectResponse(
                classification: .verifierAmbiguous,
                failureDomain: .targeting,
                summary: String(describing: error),
                window: capture.envelope.response.window,
                target: target.dto,
                selectedRange: nil,
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
            )
        }

        let axStatus = AXActionRuntimeSupport.setSelectedTextRangeResult(
            liveElement.element,
            location: plannedRange.location,
            length: plannedRange.length
        )
        guard axStatus == .success else {
            return selectResponse(
                classification: .effectNotVerified,
                failureDomain: .transport,
                summary: "Setting kAXSelectedTextRangeAttribute failed with \(axStatus).",
                window: capture.envelope.response.window,
                target: target.dto,
                selectedRange: TextSelectionRangeResponseDTO(location: plannedRange.location, length: plannedRange.length),
                preStateToken: capture.envelope.response.stateToken,
                postStateToken: nil,
                warnings: warnings,
                notes: []
            )
        }

        let postCapture = try? targetResolver.reread(after: capture, imageMode: request.imageMode ?? .omit)
        return selectResponse(
            classification: .success,
            failureDomain: nil,
            summary: "Selected requested text range.",
            window: capture.envelope.response.window,
            target: target.dto,
            selectedRange: TextSelectionRangeResponseDTO(location: plannedRange.location, length: plannedRange.length),
            preStateToken: capture.envelope.response.stateToken,
            postStateToken: postCapture?.envelope.response.stateToken,
            warnings: warnings,
            notes: ["Resolved live element via \(liveElement.resolution)."]
        )
    }

    private func selectResponse(
        classification: ActionClassificationDTO,
        failureDomain: ActionFailureDomainDTO?,
        summary: String,
        window: ResolvedWindowDTO?,
        target: AXActionTargetSnapshotDTO?,
        selectedRange: TextSelectionRangeResponseDTO?,
        preStateToken: String?,
        postStateToken: String?,
        warnings: [String],
        notes: [String]
    ) -> SelectTextResponse {
        SelectTextResponse(
            contractVersion: ContractVersion.current,
            ok: classification == .success,
            classification: classification,
            failureDomain: failureDomain,
            summary: summary,
            window: window,
            target: target,
            selectedRange: selectedRange,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            warnings: warnings,
            notes: notes
        )
    }
}

import Foundation

struct WaitForRouteService {
    private let targetResolver: AXActionTargetResolver

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
    }

    func waitFor(request: WaitForRequest) throws -> WaitForResponse {
        guard request.role != nil || request.label != nil || request.valueContains != nil else {
            throw AXActionTargetResolverError.unresolvedTarget(
                "wait_for requires at least one of role, label, or valueContains."
            )
        }

        let waitForGone = request.gone ?? false
        let timeout = min(60.0, max(0.1, request.timeoutSeconds ?? 10.0))
        let pollInterval = min(2.0, max(0.05, Double(request.pollIntervalMs ?? 400) / 1000.0))
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        var lastCapture: AXActionStateCapture?
        var conditionMet = false

        repeat {
            let capture = try targetResolver.capture(
                windowID: request.window,
                includeMenuBar: request.includeMenuBar ?? true,
                maxNodes: request.maxNodes ?? 6500,
                imageMode: request.imageMode ?? .path
            )
            lastCapture = capture
            let found = capture.envelope.response.tree.nodes.contains { node in
                WaitForMatcher.matches(
                    WaitForMatcherNode(surfaceNode: node),
                    role: request.role,
                    label: request.label,
                    valueContains: request.valueContains
                )
            }
            if found != waitForGone {
                conditionMet = true
                break
            }
            if Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
            }
        } while Date() < deadline

        let capture = try lastCapture ?? targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500,
            imageMode: request.imageMode ?? .path
        )
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        let targetDescription = [
            request.role.map { "role '\($0)'" },
            request.label.map { "label '\($0)'" },
            request.valueContains.map { "value containing '\($0)'" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        let summary = conditionMet
            ? "Condition met for \(targetDescription)\(waitForGone ? " disappearing" : " appearing")."
            : "Timed out waiting for \(targetDescription)\(waitForGone ? " to disappear" : " to appear")."

        return WaitForResponse(
            contractVersion: ContractVersion.current,
            ok: conditionMet,
            conditionMet: conditionMet,
            elapsedMs: sanitizedJSONDouble(elapsedMs),
            summary: summary,
            state: capture.envelope.response,
            notes: [
                "wait_for polled every \(Int(pollInterval * 1000))ms for up to \(String(format: "%.1f", timeout))s."
            ]
        )
    }
}

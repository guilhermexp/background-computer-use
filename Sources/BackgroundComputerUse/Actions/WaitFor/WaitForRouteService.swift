import Foundation

enum WaitForRouteError: Error, CustomStringConvertible {
    case invalidRequest(String)

    var description: String {
        switch self {
        case let .invalidRequest(message):
            return message
        }
    }
}

struct WaitForRouteService {
    private let targetResolver: AXActionTargetResolver

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        targetResolver = AXActionTargetResolver(executionOptions: executionOptions)
    }

    func waitFor(request: WaitForRequest) throws -> WaitForResponse {
        guard request.role != nil
            || request.label != nil
            || request.valueContains != nil
            || request.windowTitleContains != nil
            || request.windowTitleChanged == true
            || request.urlContains != nil
            || request.textContains != nil else {
            throw WaitForRouteError.invalidRequest(
                "wait_for requires at least one of role, label, valueContains, windowTitleContains, windowTitleChanged, urlContains, or textContains."
            )
        }

        let waitForGone = request.gone ?? false
        if waitForGone, request.windowTitleChanged == true {
            throw WaitForRouteError.invalidRequest(
                "wait_for does not support gone=true with windowTitleChanged=true; wait for a title substring to disappear instead."
            )
        }

        let timeout = min(60.0, max(0.1, request.timeoutSeconds ?? 10.0))
        let pollInterval = min(2.0, max(0.05, Double(request.pollIntervalMs ?? 400) / 1000.0))
        let finalImageMode = request.imageMode ?? .path
        let pollImageMode: ImageMode = .omit
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        var lastCapture: AXActionStateCapture?
        var baselineWindowTitle: String?
        var conditionMet = false

        repeat {
            let capture = try targetResolver.capture(
                windowID: request.window,
                includeMenuBar: request.includeMenuBar ?? true,
                maxNodes: request.maxNodes ?? 6500,
                imageMode: pollImageMode
            )
            lastCapture = capture
            baselineWindowTitle = baselineWindowTitle ?? capture.envelope.response.window.title
            let found = WaitForMatcher.conditionMatches(
                state: capture.envelope.response,
                role: request.role,
                label: request.label,
                valueContains: request.valueContains,
                windowTitleContains: request.windowTitleContains,
                windowTitleChanged: request.windowTitleChanged ?? false,
                baselineWindowTitle: baselineWindowTitle,
                urlContains: request.urlContains,
                textContains: request.textContains
            )
            if found != waitForGone {
                conditionMet = true
                break
            }
            if Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
            }
        } while Date() < deadline

        let capture = try targetResolver.capture(
            windowID: request.window,
            includeMenuBar: request.includeMenuBar ?? true,
            maxNodes: request.maxNodes ?? 6500,
            imageMode: finalImageMode
        )
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        let targetDescription = [
            request.role.map { "role '\($0)'" },
            request.label.map { "label '\($0)'" },
            request.valueContains.map { "value containing '\($0)'" },
            request.windowTitleContains.map { "window title containing '\($0)'" },
            request.windowTitleChanged == true ? "window title changed from '\(baselineWindowTitle ?? lastCapture?.envelope.response.window.title ?? "")'" : nil,
            request.urlContains.map { "URL containing '\($0)'" },
            request.textContains.map { "rendered text containing '\($0)'" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        let summary = conditionMet
            ? "Condition met for \(targetDescription)\(waitForGone ? " to stop matching" : " to match")."
            : "Timed out waiting for \(targetDescription)\(waitForGone ? " to stop matching" : " to match")."

        return WaitForResponse(
            contractVersion: ContractVersion.current,
            ok: conditionMet,
            conditionMet: conditionMet,
            elapsedMs: sanitizedJSONDouble(elapsedMs),
            summary: summary,
            state: capture.envelope.response,
            notes: [
                "wait_for polled every \(Int(pollInterval * 1000))ms for up to \(String(format: "%.1f", timeout))s.",
                "Intermediate polls used imageMode=omit; the returned state was captured with imageMode=\(finalImageMode.rawValue)."
            ]
        )
    }
}

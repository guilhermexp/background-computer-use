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

enum WaitForCaptureStage {
    case poll
    case finalCapture
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
        var windowClosedDuringPoll = false
        var notes: [String] = []

        repeat {
            let capture: AXActionStateCapture
            do {
                capture = try targetResolver.capture(
                    windowID: request.window,
                    includeMenuBar: request.includeMenuBar ?? true,
                    maxNodes: request.maxNodes ?? 6500,
                    imageMode: pollImageMode
                )
            } catch let DiscoveryError.windowNotFound(windowID) {
                guard lastCapture != nil else {
                    throw DiscoveryError.windowNotFound(windowID)
                }
                let outcome = Self.closedWindowOutcome(waitForGone: waitForGone, stage: .poll)
                conditionMet = outcome.conditionMet
                notes.append(outcome.note)
                windowClosedDuringPoll = true
                break
            }
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
                sleepRunLoop(pollInterval)
            }
        } while Date() < deadline

        let capture: AXActionStateCapture
        var returnedLastLiveState = false
        if windowClosedDuringPoll, let lastCapture {
            capture = lastCapture
            returnedLastLiveState = true
        } else {
            do {
                capture = try targetResolver.capture(
                    windowID: request.window,
                    includeMenuBar: request.includeMenuBar ?? true,
                    maxNodes: request.maxNodes ?? 6500,
                    imageMode: finalImageMode
                )
            } catch let DiscoveryError.windowNotFound(windowID) {
                guard let lastCapture else {
                    throw DiscoveryError.windowNotFound(windowID)
                }
                let outcome = Self.closedWindowOutcome(waitForGone: waitForGone, stage: .finalCapture)
                conditionMet = outcome.conditionMet
                notes.append(outcome.note)
                capture = lastCapture
                returnedLastLiveState = true
            }
        }
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
            notes: notes + [
                "wait_for polled every \(Int(pollInterval * 1000))ms for up to \(String(format: "%.1f", timeout))s.",
                returnedLastLiveState
                    ? "The target window closed; state contains the last live poll captured with imageMode=omit."
                    : "Intermediate polls used imageMode=omit; the returned state was captured with imageMode=\(finalImageMode.rawValue)."
            ]
        )
    }

    static func closedWindowOutcome(
        waitForGone: Bool,
        stage: WaitForCaptureStage
    ) -> (conditionMet: Bool, note: String) {
        let stageDescription = stage == .poll ? "during polling" : "before the final capture"
        let result = waitForGone ? "condition met" : "condition not met"
        return (
            conditionMet: waitForGone,
            note: "The target window closed \(stageDescription); \(result) without returning window_not_found."
        )
    }
}

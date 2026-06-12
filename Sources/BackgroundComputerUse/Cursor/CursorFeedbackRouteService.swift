import AppKit
import Foundation

struct CursorFeedbackRouteService {
    private let executionOptions: ActionExecutionOptions
    private let windowResolver = WindowTargetResolver()

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        self.executionOptions = executionOptions
    }

    func update(request: CursorFeedbackRequest) throws -> CursorFeedbackResponse {
        let now = CACurrentMediaTime()
        let dwell = request.dwellMs.map { max(0, $0) / 1_000 }
        var warnings: [String] = []

        let windowNumber: Int?
        if let windowID = request.window {
            windowNumber = try windowResolver.resolve(windowID: windowID).windowNumber
        } else {
            windowNumber = nil
        }

        let anchor = try feedbackPoint(x: request.x, y: request.y)

        guard executionOptions.visualCursorEnabled else {
            let state = request.state ?? (request.operation == .point ? .pointing : .idle)
            return CursorFeedbackResponse(
                contractVersion: ContractVersion.current,
                ok: true,
                operation: request.operation,
                state: state,
                message: CursorFeedbackLayout.boundedMessage(request.message),
                cursor: AXCursorTargeting.disabledSession(requested: request.cursor),
                attachment: "disabled",
                targetPointAppKit: anchor.map { PointDTO(x: $0.x, y: $0.y) },
                clamped: false,
                plannedDurationMs: nil,
                warnings: ["Visual cursor is disabled for this execution path; cursor feedback was accepted as a no-op."]
            )
        }

        let update = CursorFeedbackUpdate(
            operation: request.operation,
            state: request.state,
            message: request.message,
            append: request.append ?? (request.operation == .append),
            now: now,
            dwell: dwell,
            target: anchor,
            renderInModelFacingScreenshots: false
        )
        let result = CursorRuntime.updateFeedback(
            requested: request.cursor,
            update: update,
            attachedWindowNumber: windowNumber,
            anchorPoint: anchor
        )
        let snapshot = CursorRuntime.feedbackSnapshot(cursorID: result.session.id)

        if result.clamped {
            warnings.append("Feedback target point was clamped to the visible screen bounds.")
        }
        if result.attachment == "deferred" {
            warnings.append("Feedback has no window attachment; visual presentation is deferred until a window is supplied or the cursor is attached by an action.")
        }

        return CursorFeedbackResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            operation: request.operation,
            state: snapshot?.state ?? request.state ?? .idle,
            message: snapshot?.message ?? CursorFeedbackLayout.boundedMessage(request.message),
            cursor: result.session,
            attachment: result.attachment,
            targetPointAppKit: result.target.map { PointDTO(x: $0.x, y: $0.y) },
            clamped: result.clamped,
            plannedDurationMs: result.plannedDuration.map { sanitizedJSONDouble($0 * 1_000) },
            warnings: warnings
        )
    }

    private func feedbackPoint(x: Double?, y: Double?) throws -> CGPoint? {
        guard x != nil || y != nil else { return nil }
        guard let x, let y, x.isFinite, y.isFinite else {
            throw CursorFeedbackRouteError.invalidPoint
        }
        return CGPoint(x: x, y: y)
    }
}

enum CursorFeedbackRouteError: Error {
    case invalidPoint
}

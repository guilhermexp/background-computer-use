import AppKit
import Foundation

enum AXCursorTargeting {
    /// HTTP actions keep one visible default cursor when the runtime has visual cursors enabled.
    /// Explicit cursor requests can still override id/name/color, while package-level disabled
    /// execution remains honored.
    static func effectiveOptions(
        requested: CursorRequestDTO?,
        options: ActionExecutionOptions
    ) -> ActionExecutionOptions {
        options
    }

    static func notAttempted(
        requested: CursorRequestDTO?,
        reason: String,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        let options = effectiveOptions(requested: requested, options: options)
        return cursorResponse(
            requested: requested,
            options: options,
            targetPointAppKit: nil,
            targetPointSource: nil,
            moved: false,
            moveDurationMs: nil,
            movement: options.visualCursorEnabled ? "not_attempted" : "disabled",
            warnings: [reason]
        )
    }

    static func moveToTarget(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach",
            options: options
        ) { point, windowNumber, cursorID in
            let duration = CursorRuntime.approach(
                to: point,
                attachedWindowNumber: windowNumber,
                cursorID: cursorID
            )
            CursorRuntime.waitUntilSettled(cursorID: cursorID, timeout: duration + 0.35)
            return duration
        }
    }

    static func prepareClick(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach_click_choreography",
            options: options
        ) { point, windowNumber, cursorID in
            let duration = CursorRuntime.approach(
                to: point,
                attachedWindowNumber: windowNumber,
                cursorID: cursorID
            )
            CursorRuntime.waitUntilSettled(cursorID: cursorID, timeout: duration + 0.35)
            CursorRuntime.setPressed(true, cursorID: cursorID, attachedWindowNumber: windowNumber)
            sleepRunLoop(CursorRuntime.pressLeadDuration())
            return duration
        }
    }

    static func prepareClick(
        requested: CursorRequestDTO?,
        pointAppKit: CGPoint,
        targetPointSource: String,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        let options = effectiveOptions(requested: requested, options: options)
        var warnings: [String] = []
        let point = CursorWindowPinning.pin(
            pointAppKit,
            toWindowFrame: rect(from: window.frameAppKit),
            warnings: &warnings
        )
        guard options.visualCursorEnabled else {
            return cursorResponse(
                requested: requested,
                options: options,
                targetPointAppKit: PointDTO(x: point.x, y: point.y),
                targetPointSource: targetPointSource,
                moved: false,
                moveDurationMs: nil,
                movement: "disabled",
                warnings: warnings
            )
        }

        let session = CursorRuntime.resolve(requested: requested)
        let duration = CursorRuntime.approach(
            to: point,
            attachedWindowNumber: window.windowNumber,
            cursorID: session.id
        )
        CursorRuntime.waitUntilSettled(cursorID: session.id, timeout: duration + 0.35)
        CursorRuntime.setPressed(true, cursorID: session.id, attachedWindowNumber: window.windowNumber)
        sleepRunLoop(CursorRuntime.pressLeadDuration())

        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: targetPointSource,
            moved: true,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: "approach_click_choreography",
            warnings: warnings
        )
    }

    static func finishClick(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishClick(cursorID: cursor.session.id, afterHold: CursorRuntime.releaseHoldDuration())
    }

    static func prepareSecondaryAction(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach_secondary_choreography",
            options: options
        ) { point, windowNumber, cursorID in
            CursorRuntime.prepareSecondaryAction(to: point, attachedWindowNumber: windowNumber, cursorID: cursorID)
        }
    }

    static func finishSecondaryAction(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishSecondaryAction(cursorID: cursor.session.id)
    }

    static func prepareScroll(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        direction: ScrollDirectionDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        let mapped = cursorScrollMapping(for: direction)
        return prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach_scroll_choreography",
            options: options
        ) { point, windowNumber, cursorID in
            CursorRuntime.prepareScroll(
                to: point,
                axis: mapped.axis,
                direction: mapped.direction,
                attachedWindowNumber: windowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishScroll(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishScroll(cursorID: cursor.session.id)
    }

    static func prepareSetValue(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach_set_value_choreography",
            options: options
        ) { point, windowNumber, cursorID in
            CursorRuntime.prepareSetValue(to: point, attachedWindowNumber: windowNumber, cursorID: cursorID)
        }
    }

    static func finishSetValue(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishSetValue(cursorID: cursor.session.id)
    }

    static func prepareTypeText(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        prepareTargetedCursor(
            requested: requested,
            target: target,
            window: window,
            movement: "approach_type_text_choreography",
            options: options
        ) { point, windowNumber, cursorID in
            CursorRuntime.prepareTypeText(to: point, attachedWindowNumber: windowNumber, cursorID: cursorID)
        }
    }

    static func finishTypeText(cursor: ActionCursorTargetResponseDTO, text: String) {
        guard cursor.moved else { return }
        CursorRuntime.finishTypeText(cursorID: cursor.session.id, text: text)
    }

    static func preparePressKey(
        requested: CursorRequestDTO?,
        window: ResolvedWindowDTO,
        keyLabel: String,
        options: ActionExecutionOptions = .visualCursorEnabled
    ) -> ActionCursorTargetResponseDTO {
        let options = effectiveOptions(requested: requested, options: options)
        let point = pressKeyAnchor(in: window)
        guard options.visualCursorEnabled else {
            return cursorResponse(
                requested: requested,
                options: options,
                targetPointAppKit: PointDTO(x: point.x, y: point.y),
                targetPointSource: "window_titlebar_keyboard_anchor",
                moved: false,
                moveDurationMs: nil,
                movement: "disabled",
                warnings: []
            )
        }

        let session = CursorRuntime.resolve(requested: requested)
        let currentPoint = CursorRuntime.currentPosition(cursorID: session.id)
        let visualPoint = currentPoint ?? point
        let pointSource = currentPoint == nil ? "window_titlebar_keyboard_anchor" : "current_cursor_keyboard_anchor"
        let duration = CursorRuntime.preparePressKeyInPlace(
            at: visualPoint,
            label: keyLabel,
            attachedWindowNumber: window.windowNumber,
            cursorID: session.id
        )

        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: visualPoint.x, y: visualPoint.y),
            targetPointSource: pointSource,
            moved: false,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: "key_choreography_in_place",
            warnings: []
        )
    }

    static func finishPressKey(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.movement != "disabled" else { return }
        CursorRuntime.finishPressKey(cursorID: cursor.session.id)
    }

    private static func prepareTargetedCursor(
        requested: CursorRequestDTO?,
        target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO,
        movement: String,
        options: ActionExecutionOptions,
        prepare: (CGPoint, Int, String) -> TimeInterval
    ) -> ActionCursorTargetResponseDTO {
        let options = effectiveOptions(requested: requested, options: options)
        guard options.visualCursorEnabled else {
            let resolvedPoint = targetPoint(for: target, window: window)
            guard let point = resolvedPoint.point else {
                return cursorResponse(
                    requested: requested,
                    options: options,
                    targetPointAppKit: nil,
                    targetPointSource: nil,
                    moved: false,
                    moveDurationMs: nil,
                    movement: "disabled",
                    warnings: resolvedPoint.warnings
                )
            }

            return cursorResponse(
                requested: requested,
                options: options,
                targetPointAppKit: PointDTO(x: point.x, y: point.y),
                targetPointSource: resolvedPoint.source,
                moved: false,
                moveDurationMs: nil,
                movement: "disabled",
                warnings: resolvedPoint.warnings
            )
        }

        let session = CursorRuntime.resolve(requested: requested)
        let resolvedPoint = targetPoint(for: target, window: window)

        guard let point = resolvedPoint.point else {
            return ActionCursorTargetResponseDTO(
                session: session,
                targetPointAppKit: nil,
                targetPointSource: nil,
                moved: false,
                moveDurationMs: nil,
                movement: "no_target_point",
                warnings: resolvedPoint.warnings
            )
        }

        let duration = prepare(point, window.windowNumber, session.id)

        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: resolvedPoint.source,
            moved: true,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: movement,
            warnings: resolvedPoint.warnings
        )
    }

    private static func cursorResponse(
        requested: CursorRequestDTO?,
        options: ActionExecutionOptions,
        targetPointAppKit: PointDTO?,
        targetPointSource: String?,
        moved: Bool,
        moveDurationMs: Double?,
        movement: String,
        warnings: [String]
    ) -> ActionCursorTargetResponseDTO {
        ActionCursorTargetResponseDTO(
            session: options.visualCursorEnabled
                ? CursorRuntime.resolve(requested: requested)
                : disabledSession(requested: requested),
            targetPointAppKit: targetPointAppKit,
            targetPointSource: targetPointSource,
            moved: moved,
            moveDurationMs: moveDurationMs,
            movement: movement,
            warnings: warnings
        )
    }

    static func disabledSession(requested: CursorRequestDTO?) -> CursorResponseDTO {
        CursorResponseDTO(
            id: normalizedCursorID(requested?.id) ?? "visual-cursor-disabled",
            name: normalizedCursorName(requested?.name) ?? "Visual Cursor Disabled",
            color: normalizedCursorHex(requested?.color) ?? "#7A7A7A",
            reused: true
        )
    }

    static func targetPoint(
        for target: AXActionTargetSnapshot,
        window: ResolvedWindowDTO
    ) -> (point: CGPoint?, source: String?, warnings: [String]) {
        var warnings: [String] = []
        let rawCandidate: (point: CGPoint, source: String)? =
            target.suggestedInteractionPointAppKit.map { (cgPoint(from: $0), "suggested_interaction_point") } ??
            target.activationPointAppKit.map { (cgPoint(from: $0), "activation_point") } ??
            target.frameAppKit.map { (rect(from: $0).center, "frame_center") }

        guard let rawCandidate else {
            return (nil, nil, ["Target node had no suggested point, activation point, or frame center for cursor movement."])
        }

        var point = rawCandidate.point
        guard point.x.isFinite, point.y.isFinite else {
            return (nil, rawCandidate.source, ["Target point was not finite."])
        }

        point = CursorWindowPinning.pin(
            point,
            toWindowFrame: rect(from: window.frameAppKit),
            warnings: &warnings
        )

        return (point, rawCandidate.source, warnings)
    }

    private static func rect(from dto: RectDTO) -> CGRect {
        CGRect(x: dto.x, y: dto.y, width: dto.width, height: dto.height)
    }

    private static func cgPoint(from dto: PointDTO) -> CGPoint {
        CGPoint(x: dto.x, y: dto.y)
    }

    private static func cursorScrollMapping(for direction: ScrollDirectionDTO) -> (axis: CursorScrollAxis, direction: CursorScrollDirection) {
        switch direction {
        case .up:
            return (.vertical, .positive)
        case .down:
            return (.vertical, .negative)
        case .left:
            return (.horizontal, .negative)
        case .right:
            return (.horizontal, .positive)
        }
    }

    private static func pressKeyAnchor(in window: ResolvedWindowDTO) -> CGPoint {
        let frame = rect(from: window.frameAppKit).standardized
        guard frame.width > 1, frame.height > 1 else {
            return CGPoint(x: 0, y: 0)
        }
        return CursorTargetProjector.titlebarAnchor(for: frame)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

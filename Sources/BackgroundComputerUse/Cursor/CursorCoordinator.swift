import AppKit
import QuartzCore

private struct CursorFollowerPoint {
    var position: CGPoint
    var velocity: CGVector = .zero
    var history: [CGPoint]
}

private final class CursorSessionState {
    let id: String
    var visible = false
    var visibilityAlpha: CGFloat = 0
    var lastActivityAt: TimeInterval
    var attachedWindowNumber: Int?
    var attachedWindowLevelRawValue = NSWindow.Level.normal.rawValue
    var attachedWindowFrame: CGRect?
    var attachmentIsLive = false
    var attachmentCheckedAt: TimeInterval = 0
    var labelText: String
    var colorHex: String

    var position = CGPoint.zero
    var angle: CGFloat = CursorMotionConstants.arrowHomeAngle
    var angleVelocity: CGFloat = 0
    var scale: CGFloat = 1
    var scaleVelocity: CGFloat = 0
    var alpha: CGFloat = 1
    var currentMotion: CursorMotionPlan?
    var glyph: CursorGlyph = .arrow
    var previousGlyph: CursorGlyph?
    var morphStartedAt: TimeInterval = 0
    var morphDuration: TimeInterval = CursorActionTimings.defaults.morphDurationMilliseconds / 1000
    var isPressed = false
    var releaseUntil: TimeInterval?
    var labelAlpha: CGFloat = 1
    var labelAlphaVelocity: CGFloat = 0
    var labelScale: CGFloat = 1
    var labelScaleVelocity: CGFloat = 0
    var caretPhase: CGFloat = 0
    var isTyping = false
    var caretStart: TimeInterval = 0
    var actionInProgress = false
    var followers: [CursorFollowerPoint] = []
    var effects: [CursorVisualEffect] = []
    var scrollStreakEnabledUntil: TimeInterval = 0
    var scrollStreakAxis: CursorScrollAxis = .vertical
    var scrollStreakDirection: CursorScrollDirection = .positive
    var scrollStreakColor: NSColor = .white
    var scrollStreakOrigin = CGPoint.zero
    var acquireGlowEmitted = false
    var anticipationTilt: CGFloat = 0
    var nextMotionEntersFromEdge = false
    var actionGeneration: UInt64 = 0
    var feedback = CursorFeedbackState()

    init(descriptor: CursorSessionDescriptor, now: TimeInterval) {
        id = descriptor.id
        labelText = descriptor.name
        colorHex = descriptor.colorHex
        lastActivityAt = now
    }

    var hasPosition: Bool {
        followers.isEmpty == false
    }

    var baseColor: NSColor {
        NSColor.presenceCursorColor(hex: colorHex)
    }

    var accent: CursorAccentPalette {
        CursorAccentPalette.derive(from: baseColor)
    }

    var pivotLocal: CGPoint {
        CursorPivotKind.tip.pathPoint
    }

    func activity(at now: TimeInterval) -> CursorSessionActivity {
        CursorSessionActivity(
            hasMotion: currentMotion != nil,
            hasAction: actionInProgress,
            isPressed: isPressed,
            hasPendingRelease: releaseUntil != nil,
            hasEffects: effects.isEmpty == false,
            hasActiveFeedback: feedback.isActive(at: now)
        )
    }

    func responseDTO(reused: Bool) -> CursorResponseDTO {
        CursorResponseDTO(
            id: id,
            name: labelText,
            color: colorHex,
            reused: reused
        )
    }
}

private struct CursorOverlayKey: Hashable {
    let cursorID: String
    let screenID: String
}

@MainActor
final class CursorCoordinator {
    static let shared = CursorCoordinator()
    private static let maxTypeTextPuffs = 6
    /// How often a pinned session re-reads its window geometry from the window server.
    private static let attachmentRefreshInterval: TimeInterval = 0.25

    private let defaultAppearance = CursorProfile.defaultAppearance
    private let tuning = CursorMotionTuning.swoopy
    private let timings = CursorActionTimings.defaults

    private var sessionsByID: [String: CursorSessionState] = [:]
    private var overlaysByKey: [CursorOverlayKey: CursorOverlayController] = [:]
    private var screenObservation: NSObjectProtocol?
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: CursorDisplayLinkProxy?
    private var lastTimestamp: TimeInterval?
    private var started = false

    private init() {}

    func startIfNeeded() {
        guard started == false else { return }
        started = true
        synchronizeOverlayControllers()
        observeScreens()
        startDisplayLink()
    }

    func resolveSession(requested: CursorRequestDTO?) -> CursorResponseDTO {
        startIfNeeded()

        let now = CACurrentMediaTime()
        let sessionID = normalizedCursorID(requested?.id) ?? defaultAppearance.id

        if let existing = sessionsByID[sessionID] {
            applyMetadataUpdate(to: existing, requested: requested)
            existing.lastActivityAt = now
            return existing.responseDTO(reused: true)
        }

        let descriptor = CursorSessionDescriptor(
            id: sessionID,
            name: normalizedCursorName(requested?.name) ?? defaultAppearance.name,
            colorHex: normalizedCursorHex(requested?.color) ?? defaultAppearance.colorHex,
            reused: false
        )
        let session = CursorSessionState(descriptor: descriptor, now: now)
        applyMetadataUpdate(to: session, requested: requested)
        sessionsByID[descriptor.id] = session
        return session.responseDTO(reused: false)
    }

    func snap(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        pressed: Bool = false
    ) {
        startIfNeeded()
        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)
        session.currentMotion = nil
        session.releaseUntil = nil
        session.isPressed = pressed
        session.actionInProgress = false
        touchVisibility(session, now: CACurrentMediaTime())
        snapState(session, to: point)
        refreshPresentation()
    }

    @discardableResult
    func move(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        duration: TimeInterval,
        pressed: Bool? = nil
    ) -> CursorMotionPlan {
        startIfNeeded()
        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)
        ensurePosition(for: session, near: point)
        let entrance = consumeEdgeEntranceFlag(for: session)

        if let pressed {
            session.isPressed = pressed
            if pressed == false {
                session.releaseUntil = nil
            }
        }
        touchVisibility(session, now: CACurrentMediaTime())

        let plan = startMotion(
            session,
            toTip: point,
            duration: max(duration, 0.001),
            entrance: entrance
        )
        refreshPresentation()
        return plan
    }

    func approach(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        pressed: Bool = false
    ) -> TimeInterval {
        startIfNeeded()
        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)
        ensurePosition(for: session, near: point)
        let entrance = consumeEdgeEntranceFlag(for: session)
        session.isPressed = pressed
        session.releaseUntil = nil
        touchVisibility(session, now: CACurrentMediaTime())

        let duration = moveDuration(from: session.position, toTip: point, entrance: entrance)
        _ = startMotion(session, toTip: point, duration: duration, entrance: entrance)
        refreshPresentation()
        return duration
    }

    @discardableResult
    func performPrimaryClick(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        session.isPressed = true
        emit(
            .ripple(origin: point, color: session.accent.fill, maxRadius: 26, thickness: 1.8, lifetime: 0.48, age: 0),
            in: session
        )
        sleepFor(timings.clickPressHoldMilliseconds / 1000)
        session.isPressed = false
        emit(
            .sparkRing(origin: point, color: session.accent.trail, count: 6, lifetime: 0.42, age: 0, rngSeed: UInt64.random(in: 0..<9999)),
            in: session
        )
        endAction(session)
        return duration
    }

    @discardableResult
    func prepareSecondaryAction(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        setGlyph(.arrowWithBadge, for: session)
        sleepFor(timings.secondaryPreRippleMilliseconds / 1000)
        emit(.doubleRipple(origin: point, color: session.accent.fill, lifetime: 0.65, age: 0), in: session)
        return duration
    }

    func finishSecondaryAction(cursorID: String) {
        let session = session(for: cursorID)
        scheduleActionEnd(
            cursorID: cursorID,
            generation: session.actionGeneration,
            after: timings.secondaryDwellMilliseconds / 1000
        )
    }

    @discardableResult
    func prepareScroll(
        to point: CGPoint,
        axis: CursorScrollAxis,
        direction: CursorScrollDirection,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        setGlyph(.chevronPill(axis, direction), for: session)
        session.scrollStreakOrigin = point
        session.scrollStreakAxis = axis
        session.scrollStreakDirection = direction
        session.scrollStreakColor = session.accent.trail
        session.scrollStreakEnabledUntil = CACurrentMediaTime() + timings.scrollStreakMilliseconds / 1000
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
        return duration
    }

    func finishScroll(cursorID: String) {
        let session = session(for: cursorID)
        scheduleActionEnd(
            cursorID: cursorID,
            generation: session.actionGeneration,
            after: timings.scrollDwellMilliseconds / 1000
        )
    }

    @discardableResult
    func preparePressKey(
        to point: CGPoint,
        label: String,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        setGlyph(.keycap(label), for: session)
        sleepFor(timings.pressKeyPreBounceMilliseconds / 1000)
        session.isPressed = true
        emit(
            .ripple(
                origin: CGPoint(x: point.x, y: point.y + 6),
                color: session.accent.trail,
                maxRadius: 20,
                thickness: 1.2,
                lifetime: 0.4,
                age: 0
            ),
            in: session
        )
        refreshPresentation()
        return duration
    }

    @discardableResult
    func preparePressKeyInPlace(
        at point: CGPoint,
        label: String,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        startIfNeeded()
        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)
        if session.hasPosition == false || session.visible == false || session.visibilityAlpha <= 0.01 {
            snapState(session, to: point)
        }
        session.actionGeneration &+= 1
        session.actionInProgress = true
        session.releaseUntil = nil
        session.isPressed = false
        session.isTyping = false
        session.scrollStreakEnabledUntil = 0
        session.currentMotion = nil
        clearFeedbackForActionStart(session)
        setGlyph(.keycap(label), for: session)
        touchVisibility(session, now: CACurrentMediaTime())
        sleepFor(timings.pressKeyPreBounceMilliseconds / 1000)
        session.isPressed = true
        emit(
            .ripple(
                origin: session.position,
                color: session.accent.trail,
                maxRadius: 20,
                thickness: 1.2,
                lifetime: 0.4,
                age: 0
            ),
            in: session
        )
        refreshPresentation()
        return 0
    }

    func finishPressKey(cursorID: String) {
        let session = session(for: cursorID)
        let generation = session.actionGeneration
        clearAutomaticActionFeedback(session)
        touchVisibility(session, now: CACurrentMediaTime())
        schedulePressed(
            false,
            cursorID: cursorID,
            generation: generation,
            after: timings.pressKeyHoldMilliseconds / 1000
        )
        scheduleActionEnd(
            cursorID: cursorID,
            generation: generation,
            after: (timings.pressKeyHoldMilliseconds + timings.pressKeyReleaseMilliseconds) / 1000
        )
    }

    @discardableResult
    func prepareSetValue(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        setGlyph(.crosshair, for: session)
        sleepFor(timings.setValuePreRippleMilliseconds / 1000)
        emit(.ripple(origin: point, color: session.accent.fill, maxRadius: 32, thickness: 1.1, lifetime: 0.52, age: 0), in: session)
        emit(.sparkRing(origin: point, color: session.accent.trail, count: 6, lifetime: 0.52, age: 0, rngSeed: UInt64.random(in: 0..<9999)), in: session)
        return duration
    }

    func finishSetValue(cursorID: String) {
        let session = session(for: cursorID)
        scheduleActionEnd(
            cursorID: cursorID,
            generation: session.actionGeneration,
            after: timings.setValueDwellMilliseconds / 1000
        )
    }

    @discardableResult
    func prepareTypeText(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        let session = prepareActionSession(cursorID: cursorID, attachedWindowNumber: attachedWindowNumber, target: point)
        let duration = moveToTipAndWait(session, point)
        setGlyph(.ibeam, for: session)
        sleepFor(timings.typeArrowToIBeamMilliseconds / 1000)
        setGlyph(.caret, for: session)
        session.isTyping = true
        session.caretStart = CACurrentMediaTime()
        sleepFor(timings.typeIBeamToCaretMilliseconds / 1000)
        return duration
    }

    func finishTypeText(cursorID: String, text: String) {
        let session = session(for: cursorID)
        let generation = session.actionGeneration
        let puffCount = min(text.count, Self.maxTypeTextPuffs)
        let puffInterval = timings.typeCharacterIntervalMilliseconds / 1000

        for index in 0..<puffCount {
            scheduleTypePuff(
                cursorID: cursorID,
                generation: generation,
                after: Double(index) * puffInterval
            )
        }

        scheduleActionEnd(
            cursorID: cursorID,
            generation: generation,
            after: (Double(puffCount) * puffInterval) + (timings.typeTailDwellMilliseconds / 1000)
        )
    }

    func finishClick(cursorID: String, afterHold hold: TimeInterval = MotionPacing.releaseHold) {
        let session = session(for: cursorID)
        let generation = session.actionGeneration
        session.releaseUntil = CACurrentMediaTime() + hold
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
        scheduleActionEnd(cursorID: cursorID, generation: generation, after: hold)
    }

    func beginActionFeedback(cursorID: String, attachedWindowNumber: Int?) {
        startIfNeeded()
        let session = session(for: cursorID)
        if let attachedWindowNumber {
            updateAttachment(for: session, windowNumber: attachedWindowNumber)
        }
        session.actionGeneration &+= 1
        session.actionInProgress = true
        session.releaseUntil = nil
        clearFeedbackForActionStart(session)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    func finishActionFeedback(cursorID: String, after delay: TimeInterval = 0) {
        startIfNeeded()
        let session = session(for: cursorID)
        let generation = session.actionGeneration
        if delay <= 0 {
            clearActionFeedback(session)
            return
        }
        scheduleActionFeedbackEnd(cursorID: cursorID, generation: generation, after: delay)
    }

    func setPressed(_ pressed: Bool, cursorID: String, attachedWindowNumber: Int? = nil) {
        startIfNeeded()
        let session = session(for: cursorID)
        if let attachedWindowNumber {
            updateAttachment(for: session, windowNumber: attachedWindowNumber)
        }
        session.isPressed = pressed
        session.releaseUntil = nil
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    func track(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        pressed: Bool
    ) {
        startIfNeeded()

        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)

        if session.hasPosition == false {
            snapState(session, to: point)
        } else {
            session.position = point
        }

        session.currentMotion = nil
        session.isPressed = pressed
        session.releaseUntil = nil
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    func release(cursorID: String, afterHold hold: TimeInterval = 0.08) {
        startIfNeeded()
        let session = session(for: cursorID)
        session.releaseUntil = CACurrentMediaTime() + hold
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    func updateFeedback(
        requested: CursorRequestDTO?,
        update: CursorFeedbackUpdate,
        attachedWindowNumber: Int?,
        anchorPoint: CGPoint?
    ) -> CursorFeedbackApplicationResult {
        startIfNeeded()
        let response = resolveSession(requested: requested)
        let session = session(for: response.id)
        let now = update.now

        let attachment: String
        let hasWindowAttachment: Bool
        if let attachedWindowNumber {
            self.updateAttachment(for: session, windowNumber: attachedWindowNumber)
            attachment = "window"
            hasWindowAttachment = true
        } else if session.attachedWindowNumber != nil {
            attachment = "window"
            hasWindowAttachment = true
        } else {
            attachment = "deferred"
            hasWindowAttachment = false
        }

        let resolvedAnchor = anchorPoint ?? update.target ?? sessionCurrentOrFallbackPoint(session)
        let clamped = clampToVisibleScreen(resolvedAnchor, session: session)
        if session.hasPosition == false || session.visible == false || session.visibilityAlpha <= 0.01 {
            snapState(session, to: clamped.point)
        }

        var effectiveUpdate = update
        if update.operation == .point {
            let duration = hasWindowAttachment
                ? schedulePointing(session: session, target: clamped.point)
                : nil
            effectiveUpdate = CursorFeedbackUpdate(
                operation: .point,
                state: update.state ?? .pointing,
                message: update.message,
                append: update.append,
                now: now,
                dwell: update.dwell,
                target: clamped.point,
                renderInModelFacingScreenshots: update.renderInModelFacingScreenshots
            )
            session.feedback.apply(effectiveUpdate)
            touchVisibility(session, now: now)
            refreshPresentation()
            return CursorFeedbackApplicationResult(
                session: response,
                clamped: clamped.clamped,
                target: clamped.point,
                plannedDuration: duration,
                attachment: attachment
            )
        }

        session.feedback.apply(effectiveUpdate)
        touchVisibility(session, now: now)
        refreshPresentation()
        return CursorFeedbackApplicationResult(
            session: response,
            clamped: clamped.clamped,
            target: anchorPoint.map { _ in clamped.point },
            plannedDuration: nil,
            attachment: attachment
        )
    }

    func snapshots(forWindowNumber windowNumber: Int) -> [CursorSnapshot] {
        startIfNeeded()

        return sessionsByID.values
            .filter { session in
                session.attachedWindowNumber == windowNumber && session.visibilityAlpha > 0.01
            }
            .sorted { $0.id < $1.id }
            .map(snapshot(for:))
    }

    func isMotionSettled(cursorID: String) -> Bool {
        startIfNeeded()
        return session(for: cursorID).currentMotion == nil
    }

    func currentPosition(cursorID: String) -> CGPoint? {
        startIfNeeded()
        guard let session = sessionsByID[cursorID],
              session.hasPosition,
              session.visible,
              session.visibilityAlpha > 0.01 else {
            return nil
        }
        return session.position
    }

    func feedbackSnapshot(cursorID: String) -> CursorFeedbackSnapshot? {
        startIfNeeded()
        guard let session = sessionsByID[cursorID] else { return nil }
        return session.feedback.snapshot(at: CACurrentMediaTime())
    }

    fileprivate func displayLinkTick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - (lastTimestamp ?? now), 1.0 / 240.0), 1.0 / 24.0))
        lastTimestamp = now
        tick(now: now, dt: dt)
    }

    /// Test seam: runs one animation frame for a single session against an
    /// injected clock, so presence and motion can be asserted without waiting on
    /// the display link and without disturbing other sessions.
    func tickForTesting(cursorID: String, now: TimeInterval, dt: CGFloat = 1.0 / 60.0) {
        guard let session = sessionsByID[cursorID] else { return }
        refreshAttachmentIfStale(session, now: now)
        advance(session, now: now, dt: dt)
        refreshPresentation()
    }

    private func tick(now: TimeInterval, dt: CGFloat) {
        purgeExpiredSessions(now: now)

        for session in sessionsByID.values {
            refreshAttachmentIfStale(session, now: now)
            advance(session, now: now, dt: dt)
        }

        refreshPresentation()
    }

    private func session(for cursorID: String) -> CursorSessionState {
        if let session = sessionsByID[cursorID] {
            return session
        }

        let descriptor = CursorSessionDescriptor(
            id: cursorID,
            name: defaultAppearance.name,
            colorHex: defaultAppearance.colorHex,
            reused: false
        )
        let session = CursorSessionState(descriptor: descriptor, now: CACurrentMediaTime())
        sessionsByID[descriptor.id] = session
        return session
    }

    private func applyMetadataUpdate(to session: CursorSessionState, requested: CursorRequestDTO?) {
        if let name = normalizedCursorName(requested?.name) {
            session.labelText = name
        }
        if let colorHex = normalizedCursorHex(requested?.color) {
            session.colorHex = colorHex
        }
    }

    private func generatedCursorID() -> String {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
        return "cur_\(suffix)"
    }

    private func updateAttachment(
        for session: CursorSessionState,
        windowNumber: Int,
        now: TimeInterval = CACurrentMediaTime()
    ) {
        let sameWindow = session.attachedWindowNumber == windowNumber
        session.attachedWindowNumber = windowNumber
        session.attachmentCheckedAt = now

        guard let anchor = CursorWindowAnchorResolver.anchor(forWindowNumber: windowNumber) else {
            session.attachedWindowFrame = nil
            session.attachmentIsLive = false
            session.attachedWindowLevelRawValue = NSWindow.Level.normal.rawValue
            return
        }

        session.attachedWindowLevelRawValue = anchor.levelRawValue
        session.attachmentIsLive = anchor.isOnScreen
        if sameWindow,
           let previous = session.attachedWindowFrame,
           previous != anchor.frameAppKit {
            reanchorPosition(session, from: previous, to: anchor.frameAppKit)
        }
        session.attachedWindowFrame = anchor.frameAppKit
    }

    private func refreshAttachmentIfStale(_ session: CursorSessionState, now: TimeInterval) {
        guard let windowNumber = session.attachedWindowNumber,
              now - session.attachmentCheckedAt >= Self.attachmentRefreshInterval else {
            return
        }
        updateAttachment(for: session, windowNumber: windowNumber, now: now)
    }

    /// Keeps the cursor at the same relative spot inside a window that moved or
    /// resized, so a pinned cursor never stays behind at a stale screen point.
    private func reanchorPosition(
        _ session: CursorSessionState,
        from previous: CGRect,
        to current: CGRect
    ) {
        guard session.hasPosition, session.currentMotion == nil else { return }
        let moved = CursorWindowPinning.reanchor(session.position, from: previous, to: current)
        let delta = CGPoint(x: moved.x - session.position.x, y: moved.y - session.position.y)
        guard delta.x != 0 || delta.y != 0 else { return }

        session.position = moved
        for index in session.followers.indices {
            session.followers[index].position.x += delta.x
            session.followers[index].position.y += delta.y
            session.followers[index].history = session.followers[index].history.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
        }
    }

    private func prepareActionSession(
        cursorID: String,
        attachedWindowNumber: Int,
        target: CGPoint
    ) -> CursorSessionState {
        startIfNeeded()
        let session = session(for: cursorID)
        updateAttachment(for: session, windowNumber: attachedWindowNumber)
        ensurePosition(for: session, near: target)
        session.actionGeneration &+= 1
        session.actionInProgress = true
        session.releaseUntil = nil
        session.isPressed = false
        session.isTyping = false
        session.scrollStreakEnabledUntil = 0
        clearFeedbackForActionStart(session)
        setGlyph(.arrow, for: session)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
        return session
    }

    private func endAction(_ session: CursorSessionState, preserveScrollStreak: Bool = false) {
        session.isPressed = false
        session.isTyping = false
        if preserveScrollStreak == false {
            session.scrollStreakEnabledUntil = 0
        }
        setGlyph(.arrow, for: session)
        session.actionInProgress = false
        clearAutomaticActionFeedback(session)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    private func clearActionFeedback(_ session: CursorSessionState) {
        session.actionInProgress = false
        clearAutomaticActionFeedback(session)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    private func clearFeedbackForActionStart(_ session: CursorSessionState) {
        if session.feedback.state == .pointing {
            session.feedback.clear()
        }
    }

    private func clearAutomaticActionFeedback(_ session: CursorSessionState) {
        if session.feedback.state == .acting {
            session.feedback.clear()
        }
    }

    private func schedulePressed(
        _ pressed: Bool,
        cursorID: String,
        generation: UInt64,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.setPressedIfCurrent(
                    pressed,
                    cursorID: cursorID,
                    generation: generation
                )
            }
        }
    }

    private func scheduleActionFeedbackEnd(
        cursorID: String,
        generation: UInt64,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.clearActionFeedbackIfCurrent(cursorID: cursorID, generation: generation)
            }
        }
    }

    private func scheduleActionEnd(
        cursorID: String,
        generation: UInt64,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.endActionIfCurrent(cursorID: cursorID, generation: generation)
            }
        }
    }

    private func scheduleTypePuff(
        cursorID: String,
        generation: UInt64,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.emitTypePuffIfCurrent(cursorID: cursorID, generation: generation)
            }
        }
    }

    private func setPressedIfCurrent(_ pressed: Bool, cursorID: String, generation: UInt64) {
        guard let session = sessionsByID[cursorID],
              session.actionGeneration == generation else {
            return
        }
        session.isPressed = pressed
        session.releaseUntil = nil
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    private func clearActionFeedbackIfCurrent(cursorID: String, generation: UInt64) {
        guard let session = sessionsByID[cursorID],
              session.actionGeneration == generation else {
            return
        }
        clearActionFeedback(session)
    }

    private func endActionIfCurrent(cursorID: String, generation: UInt64) {
        guard let session = sessionsByID[cursorID],
              session.actionGeneration == generation else {
            return
        }
        endAction(session)
    }

    private func emitTypePuffIfCurrent(cursorID: String, generation: UInt64) {
        guard let session = sessionsByID[cursorID],
              session.actionGeneration == generation else {
            return
        }
        emit(
            .puff(
                origin: CGPoint(x: session.position.x + CGFloat.random(in: -2...2), y: session.position.y + 10),
                drift: CGVector(dx: CGFloat.random(in: -0.3...0.3), dy: 1),
                color: session.accent.trail,
                radius: 2.4,
                lifetime: 0.5,
                age: 0
            ),
            in: session
        )
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    private func setGlyph(_ glyph: CursorGlyph, for session: CursorSessionState) {
        guard glyph != session.glyph else { return }
        session.previousGlyph = session.glyph
        session.glyph = glyph
        session.morphStartedAt = CACurrentMediaTime()
        session.morphDuration = timings.morphDurationMilliseconds / 1000
    }

    private func emit(_ effect: CursorVisualEffect, in session: CursorSessionState) {
        session.effects.append(effect)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
    }

    private func ensurePosition(for session: CursorSessionState, near point: CGPoint) {
        guard session.hasPosition == false || session.visible == false || session.visibilityAlpha <= 0.01 else { return }
        snapState(session, to: initialPoint(for: point, session: session))
        session.nextMotionEntersFromEdge = true
    }

    private func snapState(_ session: CursorSessionState, to point: CGPoint) {
        session.position = point
        session.angle = CursorMotionConstants.arrowHomeAngle
        session.angleVelocity = 0
        session.scale = 1
        session.scaleVelocity = 0
        session.alpha = 1
        session.currentMotion = nil
        session.acquireGlowEmitted = false
        session.anticipationTilt = 0
        session.followers = (0..<CursorMotionConstants.followerCount).map { _ in
            CursorFollowerPoint(
                position: point,
                velocity: .zero,
                history: Array(repeating: point, count: CursorMotionConstants.trailHistoryLength)
            )
        }
    }

    private func startMotion(
        _ session: CursorSessionState,
        toTip tipTarget: CGPoint,
        duration: TimeInterval,
        entrance: Bool
    ) -> CursorMotionPlan {
        let pivotTarget = pivotTarget(forTip: tipTarget, session: session)
        let plan = CursorMotionPlanner.plan(
            from: session.position,
            to: pivotTarget,
            tuning: tuning,
            now: CACurrentMediaTime(),
            entrance: entrance,
            forcedDuration: duration
        )
        session.currentMotion = plan
        session.acquireGlowEmitted = false
        session.anticipationTilt = 0
        return plan
    }

    private func moveToTipAndWait(_ session: CursorSessionState, _ tipTarget: CGPoint) -> TimeInterval {
        let entrance = consumeEdgeEntranceFlag(for: session)
        let duration = moveDuration(from: session.position, toTip: tipTarget, entrance: entrance)
        _ = startMotion(session, toTip: tipTarget, duration: duration, entrance: entrance)
        touchVisibility(session, now: CACurrentMediaTime())
        refreshPresentation()
        waitForMotionCompletion(session, timeout: duration + 0.35)
        return duration
    }

    private func waitForMotionCompletion(_ session: CursorSessionState, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if session.currentMotion == nil {
                return
            }
            sleepRunLoop(1.0 / 120.0)
        }
    }

    private func moveDuration(from start: CGPoint, toTip tipTarget: CGPoint, entrance: Bool = false) -> TimeInterval {
        let pivotTarget = pivotTarget(forTip: tipTarget, pivotLocal: CursorPivotKind.tip.pathPoint)
        return MotionPacing.transitDuration(for: start.distance(to: pivotTarget), tuning: tuning, entrance: entrance)
    }

    private func consumeEdgeEntranceFlag(for session: CursorSessionState) -> Bool {
        let entrance = session.nextMotionEntersFromEdge
        session.nextMotionEntersFromEdge = false
        return entrance
    }

    private func schedulePointing(session: CursorSessionState, target: CGPoint) -> TimeInterval {
        ensurePosition(for: session, near: target)
        session.actionGeneration &+= 1
        session.actionInProgress = false
        session.releaseUntil = nil
        session.isPressed = false
        session.isTyping = false
        session.scrollStreakEnabledUntil = 0
        setGlyph(.arrowWithBadge, for: session)
        let entrance = consumeEdgeEntranceFlag(for: session)
        let duration = moveDuration(from: session.position, toTip: target, entrance: entrance)
        _ = startMotion(session, toTip: target, duration: duration, entrance: entrance)
        return duration + (session.feedback.isActive(at: CACurrentMediaTime()) ? CursorFeedbackLayout.pointingDwell : 0)
    }

    private func pivotTarget(forTip tipTarget: CGPoint, session: CursorSessionState) -> CGPoint {
        pivotTarget(forTip: tipTarget, pivotLocal: session.pivotLocal)
    }

    private func pivotTarget(forTip tipTarget: CGPoint, pivotLocal: CGPoint) -> CGPoint {
        let effectiveAngle = CursorMotionConstants.arrowHomeAngle + CursorMotionConstants.drawAngleOffset
        let c = cos(effectiveAngle)
        let s = sin(effectiveAngle)
        let vx = -pivotLocal.x
        let vy = -pivotLocal.y
        let offset = CGPoint(x: c * vx - s * vy, y: s * vx + c * vy)
        return CGPoint(x: tipTarget.x - offset.x, y: tipTarget.y - offset.y)
    }

    private func initialPoint(for targetPoint: CGPoint, session: CursorSessionState) -> CGPoint {
        let frame = anchorScreen(for: session, near: targetPoint)?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CursorMotionPlanner.edgeEntrancePoint(for: frame)
    }

    private func sessionCurrentOrFallbackPoint(_ session: CursorSessionState) -> CGPoint {
        if session.hasPosition {
            return session.position
        }
        if let windowFrame = session.attachedWindowFrame {
            return CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        }
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Display a cursor session is allowed to occupy: the one holding its
    /// attached window, never `NSScreen.main` while an attachment exists.
    private func anchorScreen(for session: CursorSessionState, near point: CGPoint) -> NSScreen? {
        if let windowFrame = session.attachedWindowFrame,
           let screen = CursorWindowPinning.screen(forWindowFrame: windowFrame) {
            return screen
        }
        return DesktopGeometry.screenContaining(point: point) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Keeps a feedback/pointing anchor inside the window the session is pinned
    /// to, then inside that window's display. Sessions with no attachment keep
    /// the previous screen-only behavior.
    private func clampToVisibleScreen(
        _ point: CGPoint,
        session: CursorSessionState
    ) -> (point: CGPoint, clamped: Bool) {
        var pinned = point
        let screen: NSScreen?
        if let windowFrame = session.attachedWindowFrame, windowFrame.width > 0, windowFrame.height > 0 {
            var ignoredWarnings: [String] = []
            pinned = CursorWindowPinning.pin(pinned, toWindowFrame: windowFrame, warnings: &ignoredWarnings)
            screen = CursorWindowPinning.screen(forWindowFrame: windowFrame)
        } else {
            screen = DesktopGeometry.screenContaining(point: pinned) ?? NSScreen.main ?? NSScreen.screens.first
        }

        if let frame = screen?.visibleFrame {
            pinned = CGPoint(
                x: max(frame.minX + 12, min(pinned.x, frame.maxX - 12)),
                y: max(frame.minY + 12, min(pinned.y, frame.maxY - 12))
            )
        }
        return (pinned, pinned.distance(to: point) > 0.01)
    }

    private func sleepFor(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        sleepRunLoop(seconds)
    }

    private func advance(_ session: CursorSessionState, now: TimeInterval, dt: CGFloat) {
        if let plan = session.currentMotion {
            session.position = plan.samplePoint(at: now)
            let tangent = plan.sampleTangent(at: now, lookAhead: CursorMotionConstants.rotationLookAhead)
            let targetAngle = atan2(tangent.dy, tangent.dx) + .pi / 2
            var angle = session.angle
            var angleVelocity = session.angleVelocity
            cursorAngularSpring(
                angle: &angle,
                velocity: &angleVelocity,
                target: targetAngle,
                stiffness: CursorMotionConstants.rotationStiffness,
                damping: CursorMotionConstants.rotationDamping,
                dt: dt
            )
            session.angle = angle
            session.angleVelocity = angleVelocity

            if plan.progress(at: now) > 0.88,
               CursorMotionConstants.glowOnAcquire,
               session.acquireGlowEmitted == false,
               plan.entrance == false {
                session.acquireGlowEmitted = true
                session.effects.append(.glowPulse(origin: plan.end, color: session.accent.fill, lifetime: 0.4, age: 0))
            }

            if plan.isFinished(at: now) {
                session.currentMotion = nil
                session.position = plan.end
                session.acquireGlowEmitted = false
                session.anticipationTilt = 0
            }
        } else if session.hasPosition {
            var angle = session.angle
            var angleVelocity = session.angleVelocity
            cursorAngularSpring(
                angle: &angle,
                velocity: &angleVelocity,
                target: CursorMotionConstants.arrowHomeAngle,
                stiffness: 8,
                damping: 4,
                dt: dt
            )
            session.angle = angle
            session.angleVelocity = angleVelocity
        }

        let atRest = session.currentMotion == nil && session.actionInProgress == false
        let labelTarget: CGFloat = atRest && labelVisible(for: session.glyph) ? 1 : 0
        cursorScalarSpring(
            value: &session.labelAlpha,
            velocity: &session.labelAlphaVelocity,
            target: labelTarget,
            stiffness: 240,
            damping: 22,
            dt: dt
        )
        cursorScalarSpring(
            value: &session.labelScale,
            velocity: &session.labelScaleVelocity,
            target: labelTarget,
            stiffness: 180,
            damping: 16,
            dt: dt
        )
        cursorScalarSpring(
            value: &session.scale,
            velocity: &session.scaleVelocity,
            target: targetScale(for: session),
            stiffness: 120,
            damping: 14,
            dt: dt
        )

        if CursorMotionConstants.anticipationEnabled,
           let plan = session.currentMotion,
           plan.progress(at: now) < 0.08 {
            session.anticipationTilt = 0.24
        } else {
            session.anticipationTilt *= 0.85
        }

        updateFollowers(session, dt: dt)
        stepTyping(session, now: now)
        stepScrollStreak(session, now: now)
        stepEffects(session, dt: TimeInterval(dt))
        stepReleaseState(session, now: now)
        session.feedback.expireIfNeeded(at: now)
        stepVisibility(session, now: now)
    }

    private func labelVisible(for glyph: CursorGlyph) -> Bool {
        switch glyph {
        case .arrow, .arrowWithBadge:
            return true
        case .chevronPill, .keycap, .crosshair, .ibeam, .caret:
            return false
        }
    }

    private func targetScale(for session: CursorSessionState) -> CGFloat {
        if session.isPressed {
            return 0.92
        }
        return 1
    }

    private func updateFollowers(_ session: CursorSessionState, dt: CGFloat) {
        guard session.followers.isEmpty == false else { return }
        var target = session.position
        for index in session.followers.indices {
            let stiffness: CGFloat = 220 - CGFloat(index) * 22
            let damping: CGFloat = 20 - CGFloat(index) * 1.4
            var follower = session.followers[index]
            let ax = (target.x - follower.position.x) * stiffness - follower.velocity.dx * damping
            let ay = (target.y - follower.position.y) * stiffness - follower.velocity.dy * damping
            follower.velocity.dx += ax * dt
            follower.velocity.dy += ay * dt
            follower.position.x += follower.velocity.dx * dt
            follower.position.y += follower.velocity.dy * dt

            follower.history.append(follower.position)
            if follower.history.count > CursorMotionConstants.trailHistoryLength {
                follower.history.removeFirst()
            }

            session.followers[index] = follower
            target = follower.position
        }
    }

    private func stepTyping(_ session: CursorSessionState, now: TimeInterval) {
        if session.isTyping {
            let elapsed = now - session.caretStart
            session.caretPhase = CGFloat((elapsed * 1.3).truncatingRemainder(dividingBy: 1))
        } else {
            session.caretPhase = 0
        }
    }

    private func stepScrollStreak(_ session: CursorSessionState, now: TimeInterval) {
        if now < session.scrollStreakEnabledUntil, Int.random(in: 0..<2) == 0 {
            session.effects.append(
                .chevronStreak(
                    origin: session.scrollStreakOrigin,
                    axis: session.scrollStreakAxis,
                    direction: session.scrollStreakDirection,
                    color: session.scrollStreakColor,
                    speed: 140,
                    lifetime: 0.42,
                    age: 0
                )
            )
        }
    }

    private func stepEffects(_ session: CursorSessionState, dt: TimeInterval) {
        session.effects = session.effects
            .map { $0.advanced(by: dt) }
            .filter { $0.finished == false }
    }

    private func stepReleaseState(_ session: CursorSessionState, now: TimeInterval) {
        if let releaseUntil = session.releaseUntil, now >= releaseUntil {
            session.releaseUntil = nil
            session.isPressed = false
        }
    }

    private func stepVisibility(_ session: CursorSessionState, now: TimeInterval) {
        if session.activity(at: now).isActive {
            touchVisibility(session, now: now)
            return
        }

        // A cursor pinned to a live window stays on screen: the agent pointer must
        // remain visible in the window it drives. Presence deliberately does not
        // renew `lastActivityAt`, so `idleExpireDelay` still retires the session.
        if session.attachmentIsLive {
            session.visible = true
            session.visibilityAlpha = 1
            return
        }

        let idleFor = now - session.lastActivityAt
        if idleFor <= CursorPresenceTiming.idleHideDelay {
            session.visible = true
            session.visibilityAlpha = 1
            return
        }

        let fadeProgress = min(
            max((idleFor - CursorPresenceTiming.idleHideDelay) / CursorPresenceTiming.fadeOutDuration, 0),
            1
        )
        session.visibilityAlpha = max(0, 1 - CGFloat(fadeProgress))
        session.visible = session.visibilityAlpha > 0.01

        if session.visible == false {
            session.followers = session.followers.map { follower in
                var next = follower
                next.history = Array(follower.history.suffix(1))
                return next
            }
        }
    }

    private func touchVisibility(_ session: CursorSessionState, now: TimeInterval) {
        session.visible = true
        session.visibilityAlpha = 1
        session.lastActivityAt = now
    }

    private func snapshot(for session: CursorSessionState) -> CursorSnapshot {
        let now = CACurrentMediaTime()
        let morphProgress: CGFloat
        if session.previousGlyph == nil {
            morphProgress = 1
        } else {
            let t = CGFloat((now - session.morphStartedAt) / max(0.001, session.morphDuration))
            morphProgress = min(max(t, 0), 1)
        }

        let accent = session.accent
        return CursorSnapshot(
            cursorID: session.id,
            attachedWindowNumber: session.attachedWindowNumber ?? 0,
            attachedWindowLevelRawValue: session.attachedWindowLevelRawValue,
            position: session.position,
            angle: session.angle,
            scale: session.scale,
            alpha: session.alpha * session.visibilityAlpha,
            glyph: session.glyph,
            previousGlyph: morphProgress < 1 ? session.previousGlyph : nil,
            morphProgress: morphProgress,
            isPressed: session.isPressed,
            accent: accent,
            baseColor: accent.fill,
            pivotLocal: session.pivotLocal,
            labelText: session.labelText,
            labelAlpha: session.labelAlpha,
            labelScale: session.labelScale,
            trailHistories: session.followers.map(\.history),
            trailVisible: CursorMotionConstants.trailVisible,
            caretPhase: session.caretPhase,
            anticipationTilt: session.anticipationTilt,
            effects: session.effects,
            feedback: session.feedback.snapshot(at: now)
        )
    }

    private func refreshPresentation() {
        synchronizeOverlayControllers()

        let screens = NSScreen.screens
        let screensByID = Dictionary(uniqueKeysWithValues: screens.map { ($0.cursorOverlayID, $0) })
        var activeKeys = Set<CursorOverlayKey>()

        for session in sessionsByID.values.sorted(by: { $0.id < $1.id }) {
            guard session.visible else {
                continue
            }
            guard session.attachedWindowNumber != nil else {
                continue
            }

            let snapshot = snapshot(for: session)
            for screen in screens {
                let screenID = screen.cursorOverlayID
                let visibleRect = screen.frame.insetBy(dx: -160, dy: -160)
                let pointVisible = visibleRect.contains(snapshot.position)
                let trailVisible = snapshot.trailHistories.contains { history in
                    history.contains { visibleRect.contains($0) }
                }
                let effectsVisible = snapshot.effects.contains { effect in
                    effectContainsVisiblePoint(effect, in: visibleRect)
                }
                let feedbackVisible = snapshot.feedback.map { feedback in
                    feedback.target.map { visibleRect.contains($0) } ?? pointVisible
                } ?? false
                guard pointVisible || trailVisible || effectsVisible || feedbackVisible else {
                    continue
                }

                let key = CursorOverlayKey(cursorID: session.id, screenID: screenID)
                activeKeys.insert(key)
                overlayController(for: key, screen: screen).setPresentation(
                    CursorOverlayPresentation(
                        attachedWindowNumber: session.attachedWindowNumber,
                        attachedWindowLevelRawValue: session.attachedWindowLevelRawValue,
                        snapshot: snapshot
                    )
                )
            }
        }

        for (key, controller) in overlaysByKey where activeKeys.contains(key) == false {
            if screensByID[key.screenID] != nil {
                controller.setPresentation(nil)
            }
        }
    }

    private func effectContainsVisiblePoint(_ effect: CursorVisualEffect, in rect: CGRect) -> Bool {
        switch effect {
        case let .ripple(origin, _, _, _, _, _),
             let .doubleRipple(origin, _, _, _),
             let .chevronStreak(origin, _, _, _, _, _, _),
             let .puff(origin, _, _, _, _, _),
             let .glowPulse(origin, _, _, _),
             let .sparkRing(origin, _, _, _, _, _):
            return rect.contains(origin)
        }
    }

    private func synchronizeOverlayControllers() {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.cursorOverlayID, $0) })
        for (key, controller) in overlaysByKey {
            guard let screen = screensByID[key.screenID] else {
                controller.teardown()
                overlaysByKey.removeValue(forKey: key)
                continue
            }
            controller.updateScreen(screen)
        }
    }

    private func overlayController(for key: CursorOverlayKey, screen: NSScreen) -> CursorOverlayController {
        if let existing = overlaysByKey[key] {
            existing.updateScreen(screen)
            return existing
        }

        let controller = CursorOverlayController(screen: screen)
        overlaysByKey[key] = controller
        return controller
    }

    private func purgeExpiredSessions(now: TimeInterval) {
        let expiredSessionIDs = sessionsByID.values.compactMap { session -> String? in
            guard session.activity(at: now).isActive == false,
                  now - session.lastActivityAt >= CursorPresenceTiming.idleExpireDelay else {
                return nil
            }
            return session.id
        }

        for sessionID in expiredSessionIDs {
            sessionsByID.removeValue(forKey: sessionID)
            teardownOverlays(for: sessionID)
        }
    }

    private func teardownOverlays(for cursorID: String) {
        for (key, controller) in overlaysByKey where key.cursorID == cursorID {
            controller.teardown()
            overlaysByKey.removeValue(forKey: key)
        }
    }

    private func observeScreens() {
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronizeOverlayControllers()
                self?.refreshPresentation()
            }
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = CursorDisplayLinkProxy(target: self)
        let link = NSScreen.main?.displayLink(target: proxy, selector: #selector(CursorDisplayLinkProxy.tick(_:)))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link?.add(to: .main, forMode: .common)
        displayLink = link
        displayLinkProxy = proxy
    }

    /// Test seam: drops every cursor session and overlay so suites never inherit
    /// cursor state from each other.
    func resetState() {
        for controller in overlaysByKey.values {
            controller.teardown()
        }
        overlaysByKey.removeAll()
        sessionsByID.removeAll()
    }
}

@MainActor
private final class CursorDisplayLinkProxy: NSObject {
    weak var target: CursorCoordinator?

    init(target: CursorCoordinator) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.displayLinkTick(link)
    }
}

enum CursorRuntime {
    static func startIfNeeded() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CursorCoordinator.shared.startIfNeeded()
            }
            return
        }
        DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.startIfNeeded()
        }
    }

    /// Test seam: clears every cursor session and overlay plus any injected window
    /// geometry, so cursor suites start from a known runtime state.
    static func resetForTesting(windowAnchors: [Int: CursorWindowAnchor]? = nil) {
        runOnMain {
            CursorWindowAnchorResolver.setOverrides(windowAnchors)
            CursorCoordinator.shared.resetState()
        }
    }

    /// Test seam: swaps the injected window geometry without dropping sessions.
    static func setWindowAnchorsForTesting(_ anchors: [Int: CursorWindowAnchor]?) {
        runOnMain {
            CursorWindowAnchorResolver.setOverrides(anchors)
        }
    }

    /// Test seam: advances one animation frame for one session against an injected clock.
    static func tickForTesting(cursorID: String, now: TimeInterval, dt: CGFloat = 1.0 / 60.0) {
        runOnMain {
            CursorCoordinator.shared.tickForTesting(cursorID: cursorID, now: now, dt: dt)
        }
    }

    static func resolve(requested: CursorRequestDTO?) -> CursorResponseDTO {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.resolveSession(requested: requested)
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.resolveSession(requested: requested)
        }
    }

    static func snap(to point: CGPoint, attachedWindowNumber: Int, cursorID: String, pressed: Bool = false) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CursorCoordinator.shared.snap(
                    to: point,
                    attachedWindowNumber: attachedWindowNumber,
                    cursorID: cursorID,
                    pressed: pressed
                )
            }
            return
        }
        DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.snap(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID,
                pressed: pressed
            )
        }
    }

    @discardableResult
    static func move(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        duration: TimeInterval,
        pressed: Bool? = nil
    ) -> CursorMotionPlan {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.move(
                    to: point,
                    attachedWindowNumber: attachedWindowNumber,
                    cursorID: cursorID,
                    duration: duration,
                    pressed: pressed
                )
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.move(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID,
                duration: duration,
                pressed: pressed
            )
        }
    }

    static func approach(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        pressed: Bool = false
    ) -> TimeInterval {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.approach(
                    to: point,
                    attachedWindowNumber: attachedWindowNumber,
                    cursorID: cursorID,
                    pressed: pressed
                )
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.approach(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID,
                pressed: pressed
            )
        }
    }

    static func prepareSecondaryAction(to point: CGPoint, attachedWindowNumber: Int, cursorID: String) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.prepareSecondaryAction(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishSecondaryAction(cursorID: String) {
        runOnMain {
            CursorCoordinator.shared.finishSecondaryAction(cursorID: cursorID)
        }
    }

    static func finishClick(cursorID: String, afterHold hold: TimeInterval = MotionPacing.releaseHold) {
        runOnMain {
            CursorCoordinator.shared.finishClick(cursorID: cursorID, afterHold: hold)
        }
    }

    static func beginActionFeedback(cursorID: String, attachedWindowNumber: Int? = nil) {
        runOnMain {
            CursorCoordinator.shared.beginActionFeedback(
                cursorID: cursorID,
                attachedWindowNumber: attachedWindowNumber
            )
        }
    }

    static func finishActionFeedback(cursorID: String, after delay: TimeInterval = 0) {
        runOnMain {
            CursorCoordinator.shared.finishActionFeedback(cursorID: cursorID, after: delay)
        }
    }

    static func prepareScroll(
        to point: CGPoint,
        axis: CursorScrollAxis,
        direction: CursorScrollDirection,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.prepareScroll(
                to: point,
                axis: axis,
                direction: direction,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishScroll(cursorID: String) {
        runOnMain {
            CursorCoordinator.shared.finishScroll(cursorID: cursorID)
        }
    }

    static func preparePressKey(
        to point: CGPoint,
        label: String,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.preparePressKey(
                to: point,
                label: label,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func preparePressKeyInPlace(
        at point: CGPoint,
        label: String,
        attachedWindowNumber: Int,
        cursorID: String
    ) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.preparePressKeyInPlace(
                at: point,
                label: label,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishPressKey(cursorID: String) {
        runOnMain {
            CursorCoordinator.shared.finishPressKey(cursorID: cursorID)
        }
    }

    static func prepareSetValue(to point: CGPoint, attachedWindowNumber: Int, cursorID: String) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.prepareSetValue(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishSetValue(cursorID: String) {
        runOnMain {
            CursorCoordinator.shared.finishSetValue(cursorID: cursorID)
        }
    }

    static func prepareTypeText(to point: CGPoint, attachedWindowNumber: Int, cursorID: String) -> TimeInterval {
        runOnMain {
            CursorCoordinator.shared.prepareTypeText(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID
            )
        }
    }

    static func finishTypeText(cursorID: String, text: String) {
        runOnMain {
            CursorCoordinator.shared.finishTypeText(cursorID: cursorID, text: text)
        }
    }

    static func pressLeadDuration() -> TimeInterval {
        MotionPacing.pressLead
    }

    static func releaseHoldDuration() -> TimeInterval {
        MotionPacing.releaseHold
    }

    static func setPressed(_ pressed: Bool, cursorID: String, attachedWindowNumber: Int? = nil) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CursorCoordinator.shared.setPressed(
                    pressed,
                    cursorID: cursorID,
                    attachedWindowNumber: attachedWindowNumber
                )
            }
            return
        }
        DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.setPressed(
                pressed,
                cursorID: cursorID,
                attachedWindowNumber: attachedWindowNumber
            )
        }
    }

    static func track(
        to point: CGPoint,
        attachedWindowNumber: Int,
        cursorID: String,
        pressed: Bool = true
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CursorCoordinator.shared.track(
                    to: point,
                    attachedWindowNumber: attachedWindowNumber,
                    cursorID: cursorID,
                    pressed: pressed
                )
            }
            return
        }
        DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.track(
                to: point,
                attachedWindowNumber: attachedWindowNumber,
                cursorID: cursorID,
                pressed: pressed
            )
        }
    }

    static func release(cursorID: String, afterHold hold: TimeInterval = 0.08) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CursorCoordinator.shared.release(cursorID: cursorID, afterHold: hold)
            }
            return
        }
        DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.release(cursorID: cursorID, afterHold: hold)
        }
    }

    static func snapshots(forWindowNumber windowNumber: Int) -> [CursorSnapshot] {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.snapshots(forWindowNumber: windowNumber)
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.snapshots(forWindowNumber: windowNumber)
        }
    }

    static func currentPosition(cursorID: String) -> CGPoint? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.currentPosition(cursorID: cursorID)
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.currentPosition(cursorID: cursorID)
        }
    }

    static func updateFeedback(
        requested: CursorRequestDTO?,
        update: CursorFeedbackUpdate,
        attachedWindowNumber: Int? = nil,
        anchorPoint: CGPoint? = nil
    ) -> CursorFeedbackApplicationResult {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.updateFeedback(
                    requested: requested,
                    update: update,
                    attachedWindowNumber: attachedWindowNumber,
                    anchorPoint: anchorPoint
                )
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.updateFeedback(
                requested: requested,
                update: update,
                attachedWindowNumber: attachedWindowNumber,
                anchorPoint: anchorPoint
            )
        }
    }

    static func feedbackSnapshot(cursorID: String) -> CursorFeedbackSnapshot? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                CursorCoordinator.shared.feedbackSnapshot(cursorID: cursorID)
            }
        }
        return DispatchQueue.main.sync { @MainActor in
            CursorCoordinator.shared.feedbackSnapshot(cursorID: cursorID)
        }
    }

    static func waitUntilSettled(cursorID: String, timeout: TimeInterval = 1.5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let settled: Bool
            if Thread.isMainThread {
                settled = MainActor.assumeIsolated {
                    CursorCoordinator.shared.isMotionSettled(cursorID: cursorID)
                }
            } else {
                settled = DispatchQueue.main.sync { @MainActor in
                    CursorCoordinator.shared.isMotionSettled(cursorID: cursorID)
                }
            }

            if settled {
                return
            }
            sleepRunLoop(1.0 / 120.0)
        }
    }

    private static func runOnMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body()
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }
}

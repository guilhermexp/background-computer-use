import AppKit
import Foundation

struct CursorProfile {
    let id: String
    let name: String
    let colorHex: String

    /// Stable default cursor used when an action omits a cursor object. Keeping one id prevents
    /// duplicate overlay sessions while still making agent activity visible on screen.
    static let defaultAppearance = CursorProfile(
        id: "agent",
        name: "Agent",
        colorHex: "#0095A1"
    )
}

struct CursorSessionDescriptor {
    let id: String
    let name: String
    let colorHex: String
    let reused: Bool
}

struct CursorMotionTuning: Equatable, Hashable {
    let startHandle: Double
    let endHandle: Double
    let arcSize: Double
    let arcFlow: Double
    let baseDurationMilliseconds: Double
    let name: String

    static let swoopy = CursorMotionTuning(
        startHandle: 0.94,
        endHandle: 0.38,
        arcSize: 0.42,
        arcFlow: 0.72,
        baseDurationMilliseconds: 650,
        name: "Swoopy"
    )
}

enum CursorMotionConstants {
    static let speedMultiplier: Double = 2.20
    static let rotationStiffness: CGFloat = 60
    static let rotationDamping: CGFloat = 10
    static let rotationLookAhead: CGFloat = 0
    static let arrowHomeAngle: CGFloat = .pi / 2
    static let drawAngleOffset: CGFloat = -0.35
    static let followerCount = 6
    static let trailHistoryLength = 14
    static let trailVisible = true
    static let idleBreathing = true
    static let anticipationEnabled = true
    static let glowOnAcquire = true
}

struct CursorActionTimings: Equatable {
    let clickPressHoldMilliseconds: Double
    let secondaryPreRippleMilliseconds: Double
    let secondaryDwellMilliseconds: Double
    let scrollStreakMilliseconds: Double
    let scrollDwellMilliseconds: Double
    let pressKeyPreBounceMilliseconds: Double
    let pressKeyHoldMilliseconds: Double
    let pressKeyReleaseMilliseconds: Double
    let setValuePreRippleMilliseconds: Double
    let setValueDwellMilliseconds: Double
    let typeArrowToIBeamMilliseconds: Double
    let typeIBeamToCaretMilliseconds: Double
    let typeCharacterIntervalMilliseconds: Double
    let typeTailDwellMilliseconds: Double
    let morphDurationMilliseconds: Double

    static let defaults = CursorActionTimings(
        clickPressHoldMilliseconds: 45,
        secondaryPreRippleMilliseconds: 50,
        secondaryDwellMilliseconds: 220,
        scrollStreakMilliseconds: 260,
        scrollDwellMilliseconds: 260,
        pressKeyPreBounceMilliseconds: 35,
        pressKeyHoldMilliseconds: 55,
        pressKeyReleaseMilliseconds: 150,
        setValuePreRippleMilliseconds: 45,
        setValueDwellMilliseconds: 200,
        typeArrowToIBeamMilliseconds: 60,
        typeIBeamToCaretMilliseconds: 60,
        typeCharacterIntervalMilliseconds: 28,
        typeTailDwellMilliseconds: 160,
        morphDurationMilliseconds: 150
    )
}

enum CursorPivotKind: String, CaseIterable, Hashable {
    case tip

    var pathPoint: CGPoint {
        switch self {
        case .tip:
            return .zero
        }
    }
}

enum CursorScrollAxis: Hashable {
    case vertical
    case horizontal
}

enum CursorScrollDirection: Hashable {
    case positive
    case negative
}

enum CursorGlyph: Equatable {
    case arrow
    case arrowWithBadge
    case chevronPill(CursorScrollAxis, CursorScrollDirection)
    case keycap(String)
    case crosshair
    case ibeam
    case caret
}

struct CursorAccentPalette {
    let fill: NSColor
    let trail: NSColor

    static func derive(from base: NSColor) -> CursorAccentPalette {
        let rgb = base.usingColorSpace(.sRGB) ?? base
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let trail = NSColor(
            calibratedHue: hue,
            saturation: max(0, saturation * 0.9),
            brightness: min(1, brightness * 1.12),
            alpha: 1
        )
        return CursorAccentPalette(fill: rgb, trail: trail)
    }
}

struct CursorMotionPlan {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
    let startedAt: TimeInterval
    let duration: TimeInterval
    let entrance: Bool

    func progress(at now: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return min(max(CGFloat((now - startedAt) / duration), 0), 1)
    }

    func easedProgress(at now: TimeInterval) -> CGFloat {
        let t = progress(at: now)
        if t < 0.5 {
            return 4 * t * t * t
        }
        let remainder = -2 * t + 2
        return 1 - (remainder * remainder * remainder) / 2
    }

    func samplePoint(at now: TimeInterval) -> CGPoint {
        cursorCubicBezier(start, control1, control2, end, t: easedProgress(at: now))
    }

    func sampleTangent(at now: TimeInterval, lookAhead: CGFloat = CursorMotionConstants.rotationLookAhead) -> CGVector {
        let base = easedProgress(at: now)
        let sampleT = min(1, max(0, base + lookAhead))
        return cursorCubicBezierDerivative(start, control1, control2, end, t: sampleT)
            .normalizedOrFallback(CGVector(dx: 1, dy: 0))
    }

    func isFinished(at now: TimeInterval) -> Bool {
        progress(at: now) >= 1
    }
}

enum CursorMotionPlanner {
    static func plan(
        from start: CGPoint,
        to end: CGPoint,
        tuning: CursorMotionTuning = .swoopy,
        now: TimeInterval,
        entrance: Bool = false,
        forcedDuration: TimeInterval? = nil
    ) -> CursorMotionPlan {
        let delta = end - start
        let distance = max(1, delta.length)
        let direction = delta.normalizedOrFallback(CGVector(dx: 1, dy: 0))
        let normal = direction.perpendicular

        let side: CGFloat = Bool.random() ? 1 : -1
        let arcMagnitude = CGFloat(tuning.arcSize) * distance * 0.5 * side
        let flow = CGFloat(tuning.arcFlow)
        let handleStart = CGFloat(tuning.startHandle)
        let handleEnd = CGFloat(tuning.endHandle)

        let control1 = CGPoint(
            x: start.x + direction.dx * distance * handleStart * flow + normal.dx * arcMagnitude,
            y: start.y + direction.dy * distance * handleStart * flow + normal.dy * arcMagnitude
        )
        let control2 = CGPoint(
            x: end.x - direction.dx * distance * handleEnd * flow + normal.dx * arcMagnitude * 0.4,
            y: end.y - direction.dy * distance * handleEnd * flow + normal.dy * arcMagnitude * 0.4
        )

        let duration = forcedDuration ?? MotionPacing.transitDuration(
            for: distance,
            tuning: tuning,
            entrance: entrance
        )

        return CursorMotionPlan(
            start: start,
            control1: control1,
            control2: control2,
            end: end,
            startedAt: now,
            duration: duration,
            entrance: entrance
        )
    }

    static func edgeEntrancePoint(for screen: CGRect) -> CGPoint {
        let edge = Int.random(in: 0..<4)
        let inset: CGFloat = 120
        switch edge {
        case 0:
            return CGPoint(x: CGFloat.random(in: screen.minX...screen.maxX), y: screen.maxY + inset)
        case 1:
            return CGPoint(x: CGFloat.random(in: screen.minX...screen.maxX), y: screen.minY - inset)
        case 2:
            return CGPoint(x: screen.minX - inset, y: CGFloat.random(in: screen.minY...screen.maxY))
        default:
            return CGPoint(x: screen.maxX + inset, y: CGFloat.random(in: screen.minY...screen.maxY))
        }
    }
}

enum MotionPacing {
    static let pressLead: TimeInterval = 0.08
    static let releaseHold: TimeInterval = 0.50

    static func transitDuration(
        for distance: CGFloat,
        tuning: CursorMotionTuning = .swoopy,
        entrance: Bool = false,
        speedMultiplier: Double = CursorMotionConstants.speedMultiplier
    ) -> TimeInterval {
        let base = (tuning.baseDurationMilliseconds / 1000) / max(0.1, speedMultiplier)
        let factor = max(0.55, min(1.80, Double(distance) / 520))
        if entrance {
            return max(base, 0.38) * 1.05
        }
        return max(0.28, base * factor)
    }

    static func approachDuration(for distance: CGFloat, tuning: CursorMotionTuning = .swoopy) -> TimeInterval {
        transitDuration(for: distance, tuning: tuning)
    }
}

enum CursorPresenceTiming {
    static let idleHideDelay: TimeInterval = 1.2
    static let fadeOutDuration: TimeInterval = 0.24
    static let idleExpireDelay: TimeInterval = 45
}

enum CursorFeedbackVisualState: String, Codable, Sendable {
    case idle
    case moving
    case acting
    case waiting
    case streaming
    case pointing
    case error
}

enum CursorFeedbackOperation: String, Codable, Sendable {
    case update
    case append
    case finish
    case hide
    case point
}

enum CursorFeedbackLayout {
    static let maxMessageCharacters = 180
    static let defaultFinishedDwell: TimeInterval = 1.8
    static let pointingDwell: TimeInterval = 1.4
    static let maxBubbleWidth: CGFloat = 340
    static let maxBubbleLines = 5
    private static let truncationMarker = "... "

    static func boundedMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard collapsed.isEmpty == false else { return nil }
        guard collapsed.count > maxMessageCharacters else {
            return collapsed
        }

        let suffixLength = maxMessageCharacters - truncationMarker.count
        return truncationMarker + String(collapsed.suffix(suffixLength))
    }
}

struct CursorFeedbackUpdate: Sendable {
    let operation: CursorFeedbackOperation
    let state: CursorFeedbackVisualState?
    let message: String?
    let append: Bool
    let now: TimeInterval
    let dwell: TimeInterval?
    let target: CGPoint?
    let renderInModelFacingScreenshots: Bool

    init(
        operation: CursorFeedbackOperation,
        state: CursorFeedbackVisualState? = nil,
        message: String? = nil,
        append: Bool = false,
        now: TimeInterval,
        dwell: TimeInterval? = nil,
        target: CGPoint? = nil,
        renderInModelFacingScreenshots: Bool = false
    ) {
        self.operation = operation
        self.state = state
        self.message = message
        self.append = append
        self.now = now
        self.dwell = dwell
        self.target = target
        self.renderInModelFacingScreenshots = renderInModelFacingScreenshots
    }
}

struct CursorFeedbackState: Sendable {
    private(set) var state: CursorFeedbackVisualState = .idle
    private(set) var message: String?
    private(set) var opacity: CGFloat = 0
    private(set) var target: CGPoint?
    private(set) var renderInModelFacingScreenshots = false
    private var activeUntil: TimeInterval?

    mutating func apply(_ update: CursorFeedbackUpdate) {
        switch update.operation {
        case .hide:
            clear()

        case .append:
            let combined = (message ?? "") + (update.message ?? "")
            message = CursorFeedbackLayout.boundedMessage(combined)
            state = update.state ?? state
            target = update.target ?? target
            activeUntil = nil
            opacity = message == nil ? 0 : 1
            renderInModelFacingScreenshots = update.renderInModelFacingScreenshots

        case .finish:
            if let bounded = CursorFeedbackLayout.boundedMessage(update.message) {
                message = bounded
            }
            state = update.state ?? .idle
            target = update.target ?? target
            activeUntil = update.now + (update.dwell ?? CursorFeedbackLayout.defaultFinishedDwell)
            opacity = message == nil ? 0 : 1
            renderInModelFacingScreenshots = update.renderInModelFacingScreenshots

        case .update, .point:
            message = CursorFeedbackLayout.boundedMessage(update.message)
            state = update.state ?? (update.operation == .point ? .pointing : .waiting)
            target = update.target
            activeUntil = update.operation == .point
                ? update.now + (update.dwell ?? CursorFeedbackLayout.pointingDwell)
                : nil
            opacity = message == nil && update.operation != .point ? 0 : 1
            renderInModelFacingScreenshots = update.renderInModelFacingScreenshots
        }
    }

    mutating func clear() {
        state = .idle
        message = nil
        opacity = 0
        target = nil
        activeUntil = nil
        renderInModelFacingScreenshots = false
    }

    mutating func expireIfNeeded(at now: TimeInterval) {
        if isActive(at: now) == false {
            clear()
        }
    }

    func isActive(at now: TimeInterval) -> Bool {
        if state == .streaming || state == .waiting || state == .acting || state == .moving || state == .error {
            return message != nil || opacity > 0.01
        }
        if state == .pointing {
            guard let activeUntil else { return true }
            return now <= activeUntil
        }
        if let activeUntil {
            return now <= activeUntil
        }
        return false
    }

    func snapshot(at now: TimeInterval) -> CursorFeedbackSnapshot? {
        guard isActive(at: now), (message != nil || state == .pointing) else {
            return nil
        }
        return CursorFeedbackSnapshot(
            state: state,
            message: message,
            opacity: opacity,
            target: target,
            renderInModelFacingScreenshots: renderInModelFacingScreenshots
        )
    }
}

struct CursorFeedbackSnapshot {
    let state: CursorFeedbackVisualState
    let message: String?
    let opacity: CGFloat
    let target: CGPoint?
    let renderInModelFacingScreenshots: Bool

    func mapGeometry(_ transform: (CGPoint) -> CGPoint) -> CursorFeedbackSnapshot {
        CursorFeedbackSnapshot(
            state: state,
            message: message,
            opacity: opacity,
            target: target.map(transform),
            renderInModelFacingScreenshots: renderInModelFacingScreenshots
        )
    }

    func excludingModelFacingFeedback() -> CursorFeedbackSnapshot? {
        renderInModelFacingScreenshots ? self : nil
    }
}

struct CursorSessionActivity {
    let hasMotion: Bool
    let hasAction: Bool
    let isPressed: Bool
    let hasPendingRelease: Bool
    let hasEffects: Bool
    let hasActiveFeedback: Bool

    init(
        hasMotion: Bool = false,
        hasAction: Bool = false,
        isPressed: Bool = false,
        hasPendingRelease: Bool = false,
        hasEffects: Bool = false,
        hasActiveFeedback: Bool = false
    ) {
        self.hasMotion = hasMotion
        self.hasAction = hasAction
        self.isPressed = isPressed
        self.hasPendingRelease = hasPendingRelease
        self.hasEffects = hasEffects
        self.hasActiveFeedback = hasActiveFeedback
    }

    var isActive: Bool {
        hasMotion || hasAction || isPressed || hasPendingRelease || hasEffects || hasActiveFeedback
    }
}

struct CursorFeedbackApplicationResult {
    let session: CursorResponseDTO
    let clamped: Bool
    let target: CGPoint?
    let plannedDuration: TimeInterval?
    let attachment: String
}

struct CursorSnapshot {
    let cursorID: String
    let attachedWindowNumber: Int
    let attachedWindowLevelRawValue: Int
    let position: CGPoint
    let angle: CGFloat
    let scale: CGFloat
    let alpha: CGFloat
    let glyph: CursorGlyph
    let previousGlyph: CursorGlyph?
    let morphProgress: CGFloat
    let isPressed: Bool
    let accent: CursorAccentPalette
    let baseColor: NSColor
    let pivotLocal: CGPoint
    let labelText: String
    let labelAlpha: CGFloat
    let labelScale: CGFloat
    let trailHistories: [[CGPoint]]
    let trailVisible: Bool
    let caretPhase: CGFloat
    let anticipationTilt: CGFloat
    let effects: [CursorVisualEffect]
    let feedback: CursorFeedbackSnapshot?

    init(
        cursorID: String,
        attachedWindowNumber: Int,
        attachedWindowLevelRawValue: Int,
        position: CGPoint,
        angle: CGFloat,
        scale: CGFloat,
        alpha: CGFloat,
        glyph: CursorGlyph,
        previousGlyph: CursorGlyph?,
        morphProgress: CGFloat,
        isPressed: Bool,
        accent: CursorAccentPalette,
        baseColor: NSColor,
        pivotLocal: CGPoint,
        labelText: String,
        labelAlpha: CGFloat,
        labelScale: CGFloat,
        trailHistories: [[CGPoint]],
        trailVisible: Bool,
        caretPhase: CGFloat,
        anticipationTilt: CGFloat,
        effects: [CursorVisualEffect],
        feedback: CursorFeedbackSnapshot? = nil
    ) {
        self.cursorID = cursorID
        self.attachedWindowNumber = attachedWindowNumber
        self.attachedWindowLevelRawValue = attachedWindowLevelRawValue
        self.position = position
        self.angle = angle
        self.scale = scale
        self.alpha = alpha
        self.glyph = glyph
        self.previousGlyph = previousGlyph
        self.morphProgress = morphProgress
        self.isPressed = isPressed
        self.accent = accent
        self.baseColor = baseColor
        self.pivotLocal = pivotLocal
        self.labelText = labelText
        self.labelAlpha = labelAlpha
        self.labelScale = labelScale
        self.trailHistories = trailHistories
        self.trailVisible = trailVisible
        self.caretPhase = caretPhase
        self.anticipationTilt = anticipationTilt
        self.effects = effects
        self.feedback = feedback
    }

    func mapGeometry(_ transform: (CGPoint) -> CGPoint) -> CursorSnapshot {
        CursorSnapshot(
            cursorID: cursorID,
            attachedWindowNumber: attachedWindowNumber,
            attachedWindowLevelRawValue: attachedWindowLevelRawValue,
            position: transform(position),
            angle: angle,
            scale: scale,
            alpha: alpha,
            glyph: glyph,
            previousGlyph: previousGlyph,
            morphProgress: morphProgress,
            isPressed: isPressed,
            accent: accent,
            baseColor: baseColor,
            pivotLocal: pivotLocal,
            labelText: labelText,
            labelAlpha: labelAlpha,
            labelScale: labelScale,
            trailHistories: trailHistories.map { $0.map(transform) },
            trailVisible: trailVisible,
            caretPhase: caretPhase,
            anticipationTilt: anticipationTilt,
            effects: effects.map { $0.mapGeometry(transform) },
            feedback: feedback?.mapGeometry(transform)
        )
    }
}

enum CursorVisualEffect {
    case ripple(origin: CGPoint, color: NSColor, maxRadius: CGFloat, thickness: CGFloat, lifetime: TimeInterval, age: TimeInterval)
    case doubleRipple(origin: CGPoint, color: NSColor, lifetime: TimeInterval, age: TimeInterval)
    case chevronStreak(origin: CGPoint, axis: CursorScrollAxis, direction: CursorScrollDirection, color: NSColor, speed: CGFloat, lifetime: TimeInterval, age: TimeInterval)
    case puff(origin: CGPoint, drift: CGVector, color: NSColor, radius: CGFloat, lifetime: TimeInterval, age: TimeInterval)
    case glowPulse(origin: CGPoint, color: NSColor, lifetime: TimeInterval, age: TimeInterval)
    case sparkRing(origin: CGPoint, color: NSColor, count: Int, lifetime: TimeInterval, age: TimeInterval, rngSeed: UInt64)

    var lifetime: TimeInterval {
        switch self {
        case .ripple(_, _, _, _, let lifetime, _),
             .doubleRipple(_, _, let lifetime, _),
             .chevronStreak(_, _, _, _, _, let lifetime, _),
             .puff(_, _, _, _, let lifetime, _),
             .glowPulse(_, _, let lifetime, _),
             .sparkRing(_, _, _, let lifetime, _, _):
            return lifetime
        }
    }

    var age: TimeInterval {
        switch self {
        case .ripple(_, _, _, _, _, let age),
             .doubleRipple(_, _, _, let age),
             .chevronStreak(_, _, _, _, _, _, let age),
             .puff(_, _, _, _, _, let age),
             .glowPulse(_, _, _, let age),
             .sparkRing(_, _, _, _, let age, _):
            return age
        }
    }

    var finished: Bool {
        age >= lifetime
    }

    var progress: CGFloat {
        CGFloat(min(1, age / lifetime))
    }

    func advanced(by dt: TimeInterval) -> CursorVisualEffect {
        switch self {
        case let .ripple(origin, color, maxRadius, thickness, lifetime, age):
            return .ripple(origin: origin, color: color, maxRadius: maxRadius, thickness: thickness, lifetime: lifetime, age: age + dt)
        case let .doubleRipple(origin, color, lifetime, age):
            return .doubleRipple(origin: origin, color: color, lifetime: lifetime, age: age + dt)
        case let .chevronStreak(origin, axis, direction, color, speed, lifetime, age):
            return .chevronStreak(origin: origin, axis: axis, direction: direction, color: color, speed: speed, lifetime: lifetime, age: age + dt)
        case let .puff(origin, drift, color, radius, lifetime, age):
            return .puff(origin: origin, drift: drift, color: color, radius: radius, lifetime: lifetime, age: age + dt)
        case let .glowPulse(origin, color, lifetime, age):
            return .glowPulse(origin: origin, color: color, lifetime: lifetime, age: age + dt)
        case let .sparkRing(origin, color, count, lifetime, age, rngSeed):
            return .sparkRing(origin: origin, color: color, count: count, lifetime: lifetime, age: age + dt, rngSeed: rngSeed)
        }
    }

    func mapGeometry(_ transform: (CGPoint) -> CGPoint) -> CursorVisualEffect {
        switch self {
        case let .ripple(origin, color, maxRadius, thickness, lifetime, age):
            return .ripple(origin: transform(origin), color: color, maxRadius: maxRadius, thickness: thickness, lifetime: lifetime, age: age)
        case let .doubleRipple(origin, color, lifetime, age):
            return .doubleRipple(origin: transform(origin), color: color, lifetime: lifetime, age: age)
        case let .chevronStreak(origin, axis, direction, color, speed, lifetime, age):
            return .chevronStreak(origin: transform(origin), axis: axis, direction: direction, color: color, speed: speed, lifetime: lifetime, age: age)
        case let .puff(origin, drift, color, radius, lifetime, age):
            return .puff(origin: transform(origin), drift: drift, color: color, radius: radius, lifetime: lifetime, age: age)
        case let .glowPulse(origin, color, lifetime, age):
            return .glowPulse(origin: transform(origin), color: color, lifetime: lifetime, age: age)
        case let .sparkRing(origin, color, count, lifetime, age, rngSeed):
            return .sparkRing(origin: transform(origin), color: color, count: count, lifetime: lifetime, age: age, rngSeed: rngSeed)
        }
    }
}

func normalizedCursorName(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    return String(trimmed.prefix(32))
}

func normalizedCursorID(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    return String(trimmed.prefix(64))
}

func normalizedCursorHex(_ value: String?) -> String? {
    guard let value else { return nil }
    let sanitized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard sanitized.count == 6, Int(sanitized, radix: 16) != nil else {
        return nil
    }
    return "#\(sanitized.uppercased())"
}

func cursorKeycapDisplayLabel(normalized: String) -> String {
    let parts = normalized
        .split(separator: "+")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
    guard parts.isEmpty == false else { return "K" }

    return parts.map { part in
        switch part.lowercased() {
        case "command":
            return "⌘"
        case "control":
            return "⌃"
        case "option":
            return "⌥"
        case "shift":
            return "⇧"
        case "return":
            return "↩"
        case "escape":
            return "⎋"
        case "tab":
            return "⇥"
        case "delete", "backspace":
            return "⌫"
        case "left":
            return "←"
        case "right":
            return "→"
        case "up":
            return "↑"
        case "down":
            return "↓"
        case "space":
            return "Space"
        default:
            return part.count == 1 ? part.uppercased() : part
        }
    }
    .joined()
}

func cursorCubicBezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
    let oneMinusT = 1 - t
    let a = oneMinusT * oneMinusT * oneMinusT
    let b = 3 * oneMinusT * oneMinusT * t
    let c = 3 * oneMinusT * t * t
    let d = t * t * t
    return CGPoint(
        x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
        y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
    )
}

func cursorCubicBezierDerivative(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGVector {
    let oneMinusT = 1 - t
    let a = 3 * oneMinusT * oneMinusT
    let b = 6 * oneMinusT * t
    let c = 3 * t * t
    return CGVector(
        dx: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
        dy: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y)
    )
}

func cursorSmoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / max(edge1 - edge0, 0.0001), 0), 1)
    return t * t * (3 - 2 * t)
}

func cursorEaseOutCubic(_ t: CGFloat) -> CGFloat {
    let x = 1 - t
    return 1 - x * x * x
}

func cursorEaseOutQuint(_ t: CGFloat) -> CGFloat {
    let x = 1 - t
    return 1 - x * x * x * x * x
}

func cursorAngularSpring(
    angle: inout CGFloat,
    velocity: inout CGFloat,
    target: CGFloat,
    stiffness: CGFloat,
    damping: CGFloat,
    dt: CGFloat
) {
    let acceleration = (target - angle) * stiffness - velocity * damping
    velocity += acceleration * dt
    angle += velocity * dt
}

func cursorScalarSpring(
    value: inout CGFloat,
    velocity: inout CGFloat,
    target: CGFloat,
    stiffness: CGFloat,
    damping: CGFloat,
    dt: CGFloat
) {
    let acceleration = (target - value) * stiffness - velocity * damping
    velocity += acceleration * dt
    value += velocity * dt
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }

    func distance(to other: CGPoint) -> CGFloat {
        (self - other).length
    }
}

extension CGVector {
    static let zero = CGVector(dx: 0, dy: 0)

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    var length: CGFloat {
        sqrt(dx * dx + dy * dy)
    }

    var perpendicular: CGVector {
        CGVector(dx: -dy, dy: dx)
    }

    var angle: CGFloat {
        atan2(dy, dx)
    }

    func normalizedOrFallback(_ fallback: CGVector) -> CGVector {
        let magnitude = length
        guard magnitude > 0.0001 else { return fallback }
        return CGVector(dx: dx / magnitude, dy: dy / magnitude)
    }
}

extension NSScreen {
    var cursorOverlayID: String {
        let frame = self.frame
        return "\(localizedName)-\(Int(frame.origin.x))x\(Int(frame.origin.y))-\(Int(frame.width))x\(Int(frame.height))"
    }
}

extension NSColor {
    static func presenceCursorColor(hex: String) -> NSColor {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            return .systemTeal
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

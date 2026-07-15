import Foundation

struct RuntimeSessionDecision: Sendable {
    let allowed: Bool
    let reason: String?

    static let allowed = RuntimeSessionDecision(allowed: true, reason: nil)

    static func rejected(_ reason: String) -> RuntimeSessionDecision {
        RuntimeSessionDecision(allowed: false, reason: reason)
    }
}

final class RuntimeSessionLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSessionID: String?
    private var activeSessionRequestCount = 0
    private var maxActionsPerSecond: Double?
    private var lastActionAt: TimeInterval?

    func configure(maxActionsPerSecond: Double?) {
        lock.lock()
        defer { lock.unlock() }
        if let maxActionsPerSecond, maxActionsPerSecond > 0 {
            self.maxActionsPerSecond = maxActionsPerSecond
        } else {
            self.maxActionsPerSecond = nil
        }
    }

    func acquire(sessionID: String, now: TimeInterval = Date().timeIntervalSince1970) -> RuntimeSessionDecision {
        lock.lock()
        defer { lock.unlock() }
        if let activeSessionID, activeSessionID != sessionID {
            return .rejected("Runtime is already in use by session \(activeSessionID).")
        }
        activeSessionID = sessionID
        activeSessionRequestCount += 1
        _ = now
        return .allowed
    }

    func release(sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        if activeSessionID == sessionID {
            activeSessionRequestCount = max(0, activeSessionRequestCount - 1)
            if activeSessionRequestCount == 0 {
                activeSessionID = nil
            }
        }
    }

    func beforeAction(now: TimeInterval = Date().timeIntervalSince1970) -> RuntimeSessionDecision {
        lock.lock()
        defer { lock.unlock() }
        guard let maxActionsPerSecond else {
            lastActionAt = now
            return .allowed
        }
        let minimumInterval = 1 / maxActionsPerSecond
        if let lastActionAt,
           now - lastActionAt < minimumInterval {
            return .rejected(
                String(format: "Action rate exceeded %.2f actions/sec.", maxActionsPerSecond)
            )
        }
        lastActionAt = now
        return .allowed
    }
}

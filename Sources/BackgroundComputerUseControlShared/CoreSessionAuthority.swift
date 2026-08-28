import Foundation

public enum CoreSessionState: String, Codable, Sendable {
    case active
    case paused
    case stopped
}

public enum CoreOperationKind: String, Codable, Sendable {
    case read
    case mutation
}

public enum CoreAuthorizationDecision: String, Codable, Sendable {
    case allowed
    case paused
    case stopped
    case unavailable
    case sessionMismatch = "session_mismatch"
}

public final class CoreSessionAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionID: String?
    private var state: CoreSessionState?

    public init() {}

    @discardableResult
    public func configure(sessionID: String, state: CoreSessionState) -> Bool {
        guard sessionID.isEmpty == false else { return false }
        lock.lock()
        defer { lock.unlock() }
        if self.sessionID == sessionID, self.state == .stopped {
            return state == .stopped
        }
        self.sessionID = sessionID
        self.state = state
        return true
    }

    @discardableResult
    public func transition(sessionID: String, to next: CoreSessionState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.sessionID == sessionID, let state else { return false }
        let permitted = switch (state, next) {
        case (.active, .active), (.active, .paused), (.active, .stopped),
             (.paused, .paused), (.paused, .active), (.paused, .stopped),
             (.stopped, .stopped):
            true
        case (.stopped, .active), (.stopped, .paused):
            false
        }
        guard permitted else { return false }
        self.state = next
        return true
    }

    public func authorize(
        sessionID: String,
        operation: CoreOperationKind
    ) -> CoreAuthorizationDecision {
        lock.lock()
        defer { lock.unlock() }
        guard let configuredSession = self.sessionID, let state else { return .unavailable }
        guard configuredSession == sessionID else { return .sessionMismatch }
        switch (state, operation) {
        case (.active, _), (.paused, .read):
            return .allowed
        case (.paused, .mutation):
            return .paused
        case (.stopped, _):
            return .stopped
        }
    }
}

@objc public protocol BackgroundComputerUseCoreXPCProtocol: NSObjectProtocol {
    func configureSession(sessionID: String, state: String, reply: @escaping (Bool) -> Void)
    func transitionSession(sessionID: String, state: String, reply: @escaping (Bool) -> Void)
    func authorize(sessionID: String, operation: String, reply: @escaping (String) -> Void)
    func ping(reply: @escaping (Bool) -> Void)
}

public enum BackgroundComputerUseCoreXPCService {
    public static let bundleID = "xyz.dubdub.backgroundcomputeruse.CoreXPC"
    public static let serviceName = bundleID
}

import Foundation

public enum SessionControlState: String, Sendable {
    case active
    case paused
    case stopped
}

public enum SessionOperationKind: Sendable {
    case read
    case mutation
}

public final class SessionControls: @unchecked Sendable {
    private let lock = NSLock()
    private var storedState: SessionControlState = .active
    private let onStop: () -> Void
    private let onStateChange: (SessionControlState) -> Void

    public convenience init(onStop: @escaping () -> Void = {}) {
        self.init(onStop: onStop, onStateChange: { _ in })
    }

    public convenience init(onStateChange: @escaping (SessionControlState) -> Void) {
        self.init(onStop: {}, onStateChange: onStateChange)
    }

    public init(
        onStop: @escaping () -> Void,
        onStateChange: @escaping (SessionControlState) -> Void
    ) {
        self.onStop = onStop
        self.onStateChange = onStateChange
    }

    public var state: SessionControlState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    public func allows(_ operation: SessionOperationKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch (storedState, operation) {
        case (.active, _), (.paused, .read):
            return true
        case (.paused, .mutation), (.stopped, _):
            return false
        }
    }

    public func pause() {
        lock.lock()
        let changed = storedState == .active
        if storedState == .active {
            storedState = .paused
        }
        lock.unlock()
        if changed {
            onStateChange(.paused)
        }
    }

    public func resume() {
        lock.lock()
        let changed = storedState == .paused
        if storedState == .paused {
            storedState = .active
        }
        lock.unlock()
        if changed {
            onStateChange(.active)
        }
    }

    public func stop() {
        lock.lock()
        let shouldNotify = storedState != .stopped
        storedState = .stopped
        lock.unlock()
        if shouldNotify {
            onStateChange(.stopped)
            onStop()
        }
    }
}

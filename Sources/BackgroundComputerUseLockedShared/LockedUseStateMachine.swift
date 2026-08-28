import Foundation

public enum LockedUseState: String, Codable, Sendable {
    case disabled
    case armed
    case locked
    case authorizing
    case shieldedActive
    case relocking
}

public enum LockedUseEvent: String, Codable, Sendable {
    case enable
    case lockObserved
    case leasePresented
    case unlockAllowed
    case localInput
    case leaseExpired
    case dependencyLost
    case relocked
    case relockFailed = "relock_failed"
    case manualUnlockObserved
    case disable
}

public enum LockedUseTransitionError: Error, Equatable, Sendable {
    case invalidTransition
    case manualUnlockRequired
}

public struct LockedUseStateMachine: Sendable {
    public private(set) var state: LockedUseState
    public private(set) var manualUnlockRequired: Bool

    public init(
        state: LockedUseState = .disabled,
        manualUnlockRequired: Bool = false
    ) {
        self.state = state
        self.manualUnlockRequired = manualUnlockRequired
    }

    public mutating func handle(_ event: LockedUseEvent) throws {
        if event == .disable {
            state = .disabled
            manualUnlockRequired = false
            return
        }
        if event == .leasePresented, manualUnlockRequired {
            throw LockedUseTransitionError.manualUnlockRequired
        }

        switch (state, event) {
        case (.disabled, .enable):
            state = .armed
        case (.armed, .lockObserved):
            state = .locked
        case (.locked, .leasePresented):
            state = .authorizing
        case (.authorizing, .unlockAllowed):
            state = .shieldedActive
        case (.armed, .localInput), (.locked, .localInput),
             (.authorizing, .localInput), (.shieldedActive, .localInput):
            state = .relocking
            manualUnlockRequired = true
        case (.authorizing, .leaseExpired), (.shieldedActive, .leaseExpired),
             (.authorizing, .dependencyLost), (.shieldedActive, .dependencyLost),
             (.locked, .dependencyLost), (.armed, .dependencyLost):
            state = .relocking
        case (.relocking, .relocked):
            state = .armed
        case (.relocking, .relockFailed):
            state = .armed
        case (.armed, .manualUnlockObserved):
            manualUnlockRequired = false
        case (.armed, .enable), (.disabled, .disable):
            break
        default:
            throw LockedUseTransitionError.invalidTransition
        }
    }
}

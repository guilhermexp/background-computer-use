import BackgroundComputerUseLockedShared
import Foundation

public protocol LockedUseShielding: AnyObject {
    func activeDisplayIDs() -> Set<UInt32>
    func installShields() -> Set<UInt32>
    func removeShields()
}

public protocol LockedUseBrokerControlling: AnyObject {
    func arm(_ lease: LockedUseLease) -> Bool
    func revoke(taskSessionID: String)
    func relock(reason: String) -> Bool
    func manualUnlockObserved()
}

public final class LockedUseCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let shield: any LockedUseShielding
    private let broker: any LockedUseBrokerControlling
    private var machine = LockedUseStateMachine()
    private var lease: LockedUseLease?
    private var coveredDisplays: Set<UInt32> = []

    public init(shield: any LockedUseShielding, broker: any LockedUseBrokerControlling) {
        self.shield = shield
        self.broker = broker
    }

    public var state: LockedUseState {
        lock.lock()
        defer { lock.unlock() }
        return machine.state
    }

    @discardableResult
    public func enable(lease: LockedUseLease) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let active = shield.activeDisplayIDs()
        let covered = shield.installShields()
        guard active.isEmpty == false, active == covered else {
            shield.removeShields()
            return false
        }
        guard broker.arm(lease) else {
            shield.removeShields()
            return false
        }
        do {
            try machine.handle(.enable)
            self.lease = lease
            coveredDisplays = covered
            return true
        } catch {
            broker.revoke(taskSessionID: lease.taskSessionID)
            shield.removeShields()
            return false
        }
    }

    public func observeLock() {
        lock.lock()
        defer { lock.unlock() }
        try? machine.handle(.lockObserved)
    }

    public func observeSafetyRelock() {
        lock.lock()
        defer { lock.unlock() }
        guard machine.state != .disabled, machine.state != .relocking else { return }
        try? machine.handle(.dependencyLost)
    }

    public func observeUnlockAllowed() {
        lock.lock()
        if machine.state == .relocking {
            let sessionID = lease?.taskSessionID
            try? machine.handle(.relocked)
            try? machine.handle(.manualUnlockObserved)
            try? machine.handle(.disable)
            lease = nil
            coveredDisplays = []
            lock.unlock()
            broker.manualUnlockObserved()
            if let sessionID {
                broker.revoke(taskSessionID: sessionID)
            }
            shield.removeShields()
            return
        }
        if machine.state == .locked {
            try? machine.handle(.leasePresented)
        }
        try? machine.handle(.unlockAllowed)
        lock.unlock()
    }

    public func displayConfigurationChanged() {
        lock.lock()
        let coverageValid = shield.activeDisplayIDs() == coveredDisplays
        if coverageValid == false {
            try? machine.handle(.dependencyLost)
        }
        lock.unlock()
        if coverageValid == false {
            _ = broker.relock(reason: "display_coverage_lost")
        }
    }

    public func localInputDetected() {
        lock.lock()
        try? machine.handle(.localInput)
        lock.unlock()
        _ = broker.relock(reason: "local_input")
    }

    public func stop() {
        lock.lock()
        let sessionID = lease?.taskSessionID
        try? machine.handle(.disable)
        lease = nil
        coveredDisplays = []
        lock.unlock()
        if let sessionID {
            broker.revoke(taskSessionID: sessionID)
        }
        shield.removeShields()
    }
}

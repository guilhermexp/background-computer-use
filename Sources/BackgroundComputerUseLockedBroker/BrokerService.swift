import BackgroundComputerUseLockedShared
import Foundation

public final class LockedUseBrokerService: NSObject, @unchecked Sendable {
    private struct TrustedLeaseBinding {
        let taskSessionID: String
        let coreDesignatedRequirement: String
        let controlDesignatedRequirement: String
    }

    private let lock = NSLock()
    private let leases = LockedUseLeaseStore()
    private let trustedCoreDesignatedRequirement: String
    private let uidProvider: () -> UInt32?
    private let bootSessionProvider: () -> String?
    private let relockOperation: (String) -> Bool
    private var machine = LockedUseStateMachine()
    private var heartbeatAt: [String: Date] = [:]
    private var bindingsByNonce: [Data: TrustedLeaseBinding] = [:]
    private var relockFailureCount = 0
    private let maximumRelockAttempts = 3

    public init(
        trustedCoreDesignatedRequirement: String,
        uidProvider: @escaping () -> UInt32?,
        bootSessionProvider: @escaping () -> String?,
        relock: @escaping (String) -> Bool
    ) {
        self.trustedCoreDesignatedRequirement = trustedCoreDesignatedRequirement
        self.uidProvider = uidProvider
        self.bootSessionProvider = bootSessionProvider
        relockOperation = relock
    }

    public var state: LockedUseState {
        lock.lock()
        defer { lock.unlock() }
        return machine.state
    }

    public var manualUnlockRequired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return machine.manualUnlockRequired
    }

    @discardableResult
    public func arm(
        _ lease: LockedUseLease,
        authenticatedControlDesignatedRequirement: String,
        now: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard lease.coreDesignatedRequirement == trustedCoreDesignatedRequirement,
              lease.controlDesignatedRequirement == authenticatedControlDesignatedRequirement
        else {
            return false
        }
        do {
            try leases.arm(lease)
            if machine.state == .disabled {
                try machine.handle(.enable)
            }
            heartbeatAt[lease.taskSessionID] = now
            bindingsByNonce[lease.nonce] = TrustedLeaseBinding(
                taskSessionID: lease.taskSessionID,
                coreDesignatedRequirement: trustedCoreDesignatedRequirement,
                controlDesignatedRequirement: authenticatedControlDesignatedRequirement
            )
            relockFailureCount = 0
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func consumeCurrentLease(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lease = leases.soleActiveLease,
              let binding = bindingsByNonce[lease.nonce],
              let uid = uidProvider(),
              let bootSession = bootSessionProvider()
        else {
            return false
        }
        do {
            defer { bindingsByNonce.removeValue(forKey: lease.nonce) }
            if machine.state == .armed {
                try machine.handle(.lockObserved)
            }
            try machine.handle(.leasePresented)
            let consumed = try leases.consume(
                nonce: lease.nonce,
                context: LockedUseConsumptionContext(
                    uid: uid,
                    bootSessionID: bootSession,
                    taskSessionID: binding.taskSessionID,
                    coreDesignatedRequirement: binding.coreDesignatedRequirement,
                    controlDesignatedRequirement: binding.controlDesignatedRequirement,
                    now: now
                )
            )
            guard consumed.taskSessionID == lease.taskSessionID else { return false }
            try machine.handle(.unlockAllowed)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func heartbeat(taskSessionID: String, now: Date = Date()) -> Bool {
        lock.lock()
        guard heartbeatAt[taskSessionID] != nil else {
            lock.unlock()
            return false
        }
        heartbeatAt[taskSessionID] = now
        lock.unlock()
        return true
    }

    public func checkDependencies(
        now: Date = Date(),
        maximumHeartbeatGap: TimeInterval = 3
    ) {
        lock.lock()
        let expiredSession = heartbeatAt.first { now.timeIntervalSince($0.value) > maximumHeartbeatGap }?.key
        lock.unlock()
        if let expiredSession {
            leases.revoke(taskSessionID: expiredSession)
            performRelock(reason: "heartbeat_lost", event: .dependencyLost)
        }
    }

    public func handleLocalInput() {
        _ = performRelock(reason: "local_input", event: .localInput)
    }

    @discardableResult
    public func manualUnlockObserved() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            try machine.handle(.manualUnlockObserved)
            return true
        } catch {
            return false
        }
    }

    public func revoke(taskSessionID: String) {
        leases.revoke(taskSessionID: taskSessionID)
        lock.lock()
        bindingsByNonce = bindingsByNonce.filter { $0.value.taskSessionID != taskSessionID }
        heartbeatAt.removeValue(forKey: taskSessionID)
        lock.unlock()
    }

    @discardableResult
    private func performRelock(reason: String, event: LockedUseEvent) -> Bool {
        lock.lock()
        guard machine.state != .relocking else {
            lock.unlock()
            return false
        }
        do {
            try machine.handle(event)
        } catch {
            lock.unlock()
            return false
        }
        heartbeatAt.removeAll(keepingCapacity: true)
        bindingsByNonce.removeAll(keepingCapacity: true)
        lock.unlock()
        leases.revokeAll()
        while true {
            let succeeded = relockOperation(reason)
            lock.lock()
            if succeeded {
                relockFailureCount = 0
                try? machine.handle(.relocked)
                lock.unlock()
                return true
            }
            relockFailureCount += 1
            guard relockFailureCount < maximumRelockAttempts else {
                lock.unlock()
                return false
            }
            try? machine.handle(.relockFailed)
            try? machine.handle(.dependencyLost)
            lock.unlock()
        }
    }

    public func relock(reason: String) -> Bool {
        performRelock(reason: reason, event: .dependencyLost)
    }
}

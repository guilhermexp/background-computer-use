import BackgroundComputerUseLockedShared
import Foundation

public final class LockedUseLeaseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var active: [Data: LockedUseLease] = [:]
    private var consumed: Set<Data> = []
    private var revoked: Set<Data> = []

    public init() {}

    public var activeLeaseCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return active.count
    }

    public var soleActiveLease: LockedUseLease? {
        lock.lock()
        defer { lock.unlock() }
        guard active.count == 1 else { return nil }
        return active.values.first
    }

    public func arm(_ lease: LockedUseLease) throws {
        lock.lock()
        defer { lock.unlock() }
        guard lease.version == 1 else { throw LockedUseLeaseError.invalidVersion }
        guard lease.oneUse else { throw LockedUseLeaseError.notOneUse }
        guard lease.expiresAt > lease.issuedAt,
              lease.expiresAt.timeIntervalSince(lease.issuedAt) <= 60
        else {
            throw LockedUseLeaseError.invalidLifetime
        }
        guard active[lease.nonce] == nil,
              consumed.contains(lease.nonce) == false,
              revoked.contains(lease.nonce) == false
        else {
            throw LockedUseLeaseError.duplicateNonce
        }
        active[lease.nonce] = lease
    }

    public func consume(
        nonce: Data,
        context: LockedUseConsumptionContext
    ) throws -> LockedUseLease {
        lock.lock()
        defer { lock.unlock() }
        if consumed.contains(nonce) {
            throw LockedUseLeaseError.replayed
        }
        if revoked.contains(nonce) {
            throw LockedUseLeaseError.revoked
        }
        guard let lease = active.removeValue(forKey: nonce) else {
            throw LockedUseLeaseError.unknownNonce
        }
        guard context.now >= lease.issuedAt, context.now < lease.expiresAt else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.expired
        }
        guard context.uid == lease.uid else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.uidMismatch
        }
        guard context.bootSessionID == lease.bootSessionID else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.bootSessionMismatch
        }
        guard context.taskSessionID == lease.taskSessionID else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.taskSessionMismatch
        }
        guard context.coreDesignatedRequirement == lease.coreDesignatedRequirement else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.coreSignerMismatch
        }
        guard context.controlDesignatedRequirement == lease.controlDesignatedRequirement else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.controlSignerMismatch
        }
        guard lease.oneUse else {
            revoked.insert(nonce)
            throw LockedUseLeaseError.notOneUse
        }
        consumed.insert(nonce)
        trimTombstonesIfNeeded()
        return lease
    }

    public func revoke(taskSessionID: String) {
        lock.lock()
        let matching = active.values.filter { $0.taskSessionID == taskSessionID }
        for lease in matching {
            active.removeValue(forKey: lease.nonce)
            revoked.insert(lease.nonce)
        }
        trimTombstonesIfNeeded()
        lock.unlock()
    }

    public func revokeAll() {
        lock.lock()
        for lease in active.values {
            revoked.insert(lease.nonce)
        }
        active.removeAll(keepingCapacity: true)
        trimTombstonesIfNeeded()
        lock.unlock()
    }

    private func trimTombstonesIfNeeded() {
        if consumed.count > 4096 {
            consumed.removeAll(keepingCapacity: true)
        }
        if revoked.count > 4096 {
            revoked.removeAll(keepingCapacity: true)
        }
    }
}

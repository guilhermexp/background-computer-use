import BackgroundComputerUseControlShared
import BackgroundComputerUseLockedBroker
import BackgroundComputerUseLockedShared
import Foundation
import Testing

struct LockedUseLeaseTests {
    private func lease(now: Date = Date(timeIntervalSince1970: 100)) throws -> LockedUseLease {
        try LockedUseLease.issue(
            taskSessionID: "task",
            uid: 501,
            bootSessionID: "boot",
            issuedAt: now,
            expiresAt: now.addingTimeInterval(30),
            coreDesignatedRequirement: "core-req",
            controlDesignatedRequirement: "control-req"
        )
    }

    @Test
    func nonceHas256BitsAndLeaseConsumesOnce() throws {
        let lease = try lease()
        #expect(lease.nonce.count == 32)
        let store = LockedUseLeaseStore()
        try store.arm(lease)
        let context = LockedUseConsumptionContext(
            uid: 501,
            bootSessionID: "boot",
            taskSessionID: "task",
            coreDesignatedRequirement: "core-req",
            controlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 110)
        )
        #expect(try store.consume(nonce: lease.nonce, context: context).taskSessionID == "task")
        #expect(throws: LockedUseLeaseError.replayed) {
            _ = try store.consume(nonce: lease.nonce, context: context)
        }
    }

    @Test
    func expiryAndEveryBindingMismatchDeny() throws {
        let lease = try lease()
        let variants = [
            LockedUseConsumptionContext(uid: 502, bootSessionID: "boot", taskSessionID: "task", coreDesignatedRequirement: "core-req", controlDesignatedRequirement: "control-req", now: Date(timeIntervalSince1970: 110)),
            LockedUseConsumptionContext(uid: 501, bootSessionID: "other", taskSessionID: "task", coreDesignatedRequirement: "core-req", controlDesignatedRequirement: "control-req", now: Date(timeIntervalSince1970: 110)),
            LockedUseConsumptionContext(uid: 501, bootSessionID: "boot", taskSessionID: "other", coreDesignatedRequirement: "core-req", controlDesignatedRequirement: "control-req", now: Date(timeIntervalSince1970: 110)),
            LockedUseConsumptionContext(uid: 501, bootSessionID: "boot", taskSessionID: "task", coreDesignatedRequirement: "wrong", controlDesignatedRequirement: "control-req", now: Date(timeIntervalSince1970: 110)),
            LockedUseConsumptionContext(uid: 501, bootSessionID: "boot", taskSessionID: "task", coreDesignatedRequirement: "core-req", controlDesignatedRequirement: "wrong", now: Date(timeIntervalSince1970: 110)),
            LockedUseConsumptionContext(uid: 501, bootSessionID: "boot", taskSessionID: "task", coreDesignatedRequirement: "core-req", controlDesignatedRequirement: "control-req", now: Date(timeIntervalSince1970: 131)),
        ]
        for context in variants {
            let store = LockedUseLeaseStore()
            try store.arm(lease)
            #expect(throws: LockedUseLeaseError.self) {
                _ = try store.consume(nonce: lease.nonce, context: context)
            }
        }
    }

    @Test
    func concurrentConsumeHasExactlyOneWinner() async throws {
        let lease = try lease()
        let store = LockedUseLeaseStore()
        try store.arm(lease)
        let context = LockedUseConsumptionContext(
            uid: 501,
            bootSessionID: "boot",
            taskSessionID: "task",
            coreDesignatedRequirement: "core-req",
            controlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 110)
        )
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0 ..< 12 {
                group.addTask { (try? store.consume(nonce: lease.nonce, context: context)) != nil }
            }
            var count = 0
            for await success in group where success {
                count += 1
            }
            return count
        }
        #expect(successes == 1)
    }

    @Test
    func revokeRemovesEveryLeaseForSession() throws {
        let store = LockedUseLeaseStore()
        let lease = try lease()
        try store.arm(lease)
        store.revoke(taskSessionID: "task")
        #expect(store.activeLeaseCount == 0)
    }

    @Test
    func brokerRelocksWhenHeartbeatExpires() throws {
        var relockReasons: [String] = []
        let broker = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { reason in relockReasons.append(reason); return true }
        )
        let lease = try lease(now: Date(timeIntervalSince1970: 100))
        #expect(broker.arm(
            lease,
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))
        broker.heartbeat(taskSessionID: "task", now: Date(timeIntervalSince1970: 101))
        broker.checkDependencies(now: Date(timeIntervalSince1970: 106), maximumHeartbeatGap: 3)
        broker.checkDependencies(now: Date(timeIntervalSince1970: 107), maximumHeartbeatGap: 3)

        #expect(relockReasons == ["heartbeat_lost"])
        #expect(broker.state == .armed)
    }

    @Test
    func brokerConsumesSoleLeaseAgainstLiveUIDAndBoot() throws {
        let broker = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { _ in true }
        )
        let lease = try lease()
        #expect(broker.arm(
            lease,
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))
        #expect(broker.consumeCurrentLease(now: Date(timeIntervalSince1970: 110)))
        #expect(broker.consumeCurrentLease(now: Date(timeIntervalSince1970: 111)) == false)
    }

    @Test
    func xpcPeerRolesSeparateArmFromConsume() throws {
        let broker = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { _ in true }
        )
        let encoded = try JSONEncoder().encode(lease(now: Date()))
        let control = LockedUseBrokerConnectionService(
            broker: broker,
            role: .control,
            identity: AppIdentity(
                bundleID: "xyz.dubdub.backgroundcomputeruse",
                teamID: "TEAM123",
                designatedRequirement: "control-req"
            )
        )
        let host = LockedUseBrokerConnectionService(
            broker: broker,
            role: .authorizationHost,
            identity: AppIdentity(
                bundleID: "com.apple.SecurityAgent",
                teamID: "apple-platform:1",
                designatedRequirement: "host-req"
            )
        )
        var controlArm = false
        var hostArm = true
        control.armLease(encoded) { controlArm = $0 }
        host.armLease(encoded) { hostArm = $0 }
        var controlConsume = true
        var hostConsume = false
        control.consumeCurrentLease { controlConsume = $0 }
        host.consumeCurrentLease { hostConsume = $0 }

        #expect(controlArm)
        #expect(hostArm == false)
        #expect(controlConsume == false)
        #expect(hostConsume)
    }

    @Test
    func brokerRejectsLeaseBindingsNotAnchoredInAuthenticatedPeers() throws {
        let broker = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { _ in true }
        )
        let valid = try lease()
        let wrongCore = try LockedUseLease.issue(
            taskSessionID: "task",
            uid: 501,
            bootSessionID: "boot",
            issuedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 130),
            coreDesignatedRequirement: "attacker-core",
            controlDesignatedRequirement: "control-req"
        )

        #expect(broker.arm(
            wrongCore,
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ) == false)
        #expect(broker.arm(
            valid,
            authenticatedControlDesignatedRequirement: "attacker-control",
            now: Date(timeIntervalSince1970: 100)
        ) == false)
        #expect(broker.arm(
            valid,
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))
    }

    @Test
    func physicalInputBeforeConsumeRevokesLeaseUntilManualUnlock() throws {
        var relockReasons: [String] = []
        let broker = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { reason in relockReasons.append(reason); return true }
        )
        #expect(try broker.arm(
            lease(),
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))

        broker.handleLocalInput()

        #expect(relockReasons == ["local_input"])
        #expect(broker.state == .armed)
        #expect(broker.manualUnlockRequired)
        #expect(broker.consumeCurrentLease(now: Date(timeIntervalSince1970: 110)) == false)
        #expect(broker.manualUnlockObserved())
        #expect(broker.manualUnlockRequired == false)
    }

    @Test
    func relockRetriesAreBoundedAndTransientFailureCanRecover() throws {
        var outcomes = [false, true]
        var calls = 0
        let recovering = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { _ in calls += 1; return outcomes.removeFirst() }
        )
        #expect(try recovering.arm(
            lease(),
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))

        recovering.handleLocalInput()
        #expect(recovering.state == .armed)
        #expect(calls == 2)

        var failedCalls = 0
        let failing = LockedUseBrokerService(
            trustedCoreDesignatedRequirement: "core-req",
            uidProvider: { 501 },
            bootSessionProvider: { "boot" },
            relock: { _ in failedCalls += 1; return false }
        )
        #expect(try failing.arm(
            lease(),
            authenticatedControlDesignatedRequirement: "control-req",
            now: Date(timeIntervalSince1970: 100)
        ))
        failing.handleLocalInput()
        #expect(failedCalls == 3)
        for _ in 0 ..< 5 {
            _ = failing.relock(reason: "retry")
        }
        #expect(failedCalls == 3)
        #expect(failing.state == .relocking)
    }
}

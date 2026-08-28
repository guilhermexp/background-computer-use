import BackgroundComputerUseControl
import BackgroundComputerUseLockedBroker
import BackgroundComputerUseLockedShared
import Foundation
import Testing

struct LockedUseCoordinatorTests {
    private func lease() throws -> LockedUseLease {
        try LockedUseLease.issue(
            taskSessionID: "task",
            uid: 501,
            bootSessionID: "boot",
            issuedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 130),
            coreDesignatedRequirement: "core",
            controlDesignatedRequirement: "control"
        )
    }

    @Test
    func armRequiresCompleteMultiDisplayCoverageAndBrokerAck() throws {
        let shield = FakeShield(active: [1, 2], covered: [1, 2])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)

        #expect(try coordinator.enable(lease: lease()))
        #expect(coordinator.state == .armed)
        #expect(broker.armCalls == 1)
    }

    @Test
    func missingCoverageFailsClosedBeforeBroker() throws {
        let shield = FakeShield(active: [1, 2], covered: [1])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)

        #expect(try coordinator.enable(lease: lease()) == false)
        #expect(broker.armCalls == 0)
    }

    @Test
    func displayHotPlugAndLocalInputRelock() throws {
        let shield = FakeShield(active: [1], covered: [1])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)
        #expect(try coordinator.enable(lease: lease()))
        coordinator.observeLock()
        shield.active = [1, 2]
        coordinator.displayConfigurationChanged()

        #expect(broker.relockReasons == ["display_coverage_lost"])
        #expect(coordinator.state == .relocking)
    }

    @Test
    func stopRevokesLeaseAndRemovesShields() throws {
        let shield = FakeShield(active: [1], covered: [1])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)
        #expect(try coordinator.enable(lease: lease()))
        coordinator.stop()

        #expect(broker.revokedSessions == ["task"])
        #expect(shield.removeCalls == 1)
        #expect(coordinator.state == .disabled)
    }

    @Test
    func manualUnlockAfterRelockEndsLockedUseAndRemovesShields() throws {
        let shield = FakeShield(active: [1], covered: [1])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)
        #expect(try coordinator.enable(lease: lease()))
        coordinator.observeLock()
        shield.active = [1, 2]
        coordinator.displayConfigurationChanged()

        coordinator.observeUnlockAllowed()

        #expect(coordinator.state == .disabled)
        #expect(shield.removeCalls == 1)
        #expect(broker.manualUnlockCalls == 1)
        #expect(broker.revokedSessions == ["task"])
    }

    @Test
    func brokerInitiatedSafetyLockSynchronizesBeforeManualUnlock() throws {
        let shield = FakeShield(active: [1], covered: [1])
        let broker = FakeLockedBroker(armResult: true)
        let coordinator = LockedUseCoordinator(shield: shield, broker: broker)
        #expect(try coordinator.enable(lease: lease()))
        coordinator.observeLock()
        coordinator.observeUnlockAllowed()
        #expect(coordinator.state == .shieldedActive)

        coordinator.observeSafetyRelock()
        coordinator.observeUnlockAllowed()

        #expect(coordinator.state == .disabled)
        #expect(shield.removeCalls == 1)
        #expect(broker.manualUnlockCalls == 1)
    }

    @Test
    func physicalHIDInputRelocksButProcessDirectedSyntheticInputDoesNot() {
        #expect(LocalInputClassifier.shouldRelock(sourceUnixPID: 0))
        #expect(LocalInputClassifier.shouldRelock(sourceUnixPID: -1))
        #expect(LocalInputClassifier.shouldRelock(sourceUnixPID: 1234) == false)
    }
}

private final class FakeShield: LockedUseShielding, @unchecked Sendable {
    var active: Set<UInt32>
    var covered: Set<UInt32>
    private(set) var removeCalls = 0
    init(active: Set<UInt32>, covered: Set<UInt32>) {
        self.active = active
        self.covered = covered
    }

    func activeDisplayIDs() -> Set<UInt32> {
        active
    }

    func installShields() -> Set<UInt32> {
        covered
    }

    func removeShields() {
        removeCalls += 1
    }
}

private final class FakeLockedBroker: LockedUseBrokerControlling, @unchecked Sendable {
    let armResult: Bool
    private(set) var armCalls = 0
    private(set) var relockReasons: [String] = []
    private(set) var revokedSessions: [String] = []
    private(set) var manualUnlockCalls = 0
    init(armResult: Bool) {
        self.armResult = armResult
    }

    func arm(_: LockedUseLease) -> Bool {
        armCalls += 1; return armResult
    }

    func revoke(taskSessionID: String) {
        revokedSessions.append(taskSessionID)
    }

    func relock(reason: String) -> Bool {
        relockReasons.append(reason); return true
    }

    func manualUnlockObserved() {
        manualUnlockCalls += 1
    }
}

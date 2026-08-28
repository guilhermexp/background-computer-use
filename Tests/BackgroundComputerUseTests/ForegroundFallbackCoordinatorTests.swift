@testable import BackgroundComputerUse
import Foundation
import Testing

struct ForegroundFallbackCoordinatorTests {
    @Test
    func preservedForegroundStaysInBackground() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let harness = ForegroundHarness(current: original)

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: 20,
            backgroundPrepared: true
        )

        #expect(outcome.mode == .background)
        #expect(outcome.foregroundBeforeDispatch == original)
        #expect(harness.activatedPIDs.isEmpty)
    }

    @Test
    func alreadyFrontmostTargetUsesFallbackWithoutActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(current: target)

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: true
        )

        #expect(outcome.mode == .foregroundFallback)
        #expect(outcome.foregroundBeforeDispatch == target)
        #expect(harness.activatedPIDs.isEmpty)
    }

    @Test
    func failedBackgroundPreparationActivatesExactTargetOnce() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(current: original, activatableApplications: [target])

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .foregroundFallback)
        #expect(outcome.foregroundBeforeDispatch == target)
        #expect(harness.activatedPIDs == [target.pid])
    }

    @Test
    func delayedTargetActivationUsesFallbackAfterOneAttempt() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(
            current: original,
            activatableApplications: [target],
            activationDelaySamples: 1
        )

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .foregroundFallback)
        #expect(outcome.foregroundBeforeDispatch == target)
        #expect(harness.activatedPIDs == [target.pid])
    }

    @Test
    func targetAppearingWithinSynchronousDeadlineUsesFallbackAfterOneAttempt() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(
            current: original,
            activatableApplications: [target],
            activationDelaySamples: 20
        )

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .foregroundFallback)
        #expect(outcome.foregroundBeforeDispatch == target)
        #expect(harness.activatedPIDs == [target.pid])
    }

    @Test
    func nilForegroundEvidenceWaitsForDelayedTarget() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(
            current: original,
            activatableApplications: [target],
            foregroundSamplesAfterActivation: [nil, nil]
        )

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .foregroundFallback)
        #expect(outcome.foregroundBeforeDispatch == target)
        #expect(harness.activatedPIDs == [target.pid])
    }

    @Test
    func targetActivationTimeoutArmsRecoveryWithoutSecondTargetAttempt() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let recovery = LateRecoverySpy()
        let harness = ForegroundHarness(
            current: original,
            activatableApplications: [target],
            completesActivation: false,
            lateRecovery: recovery
        )

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .blockedByUserChange)
        #expect(outcome.foregroundBeforeDispatch == original)
        #expect(harness.activatedPIDs == [target.pid])
        #expect(recovery.requests == [
            RecoveryRequest(desired: original, targetPID: target.pid),
        ])
    }

    @Test
    func thirdAppDuringTargetActivationArmsRecoveryWithoutSecondTargetActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let recovery = LateRecoverySpy()
        let harness = ForegroundHarness(
            current: original,
            activatableApplications: [target],
            foregroundSamplesAfterActivation: [third],
            lateRecovery: recovery
        )

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: target.pid,
            backgroundPrepared: false
        )

        #expect(outcome.mode == .blockedByUserChange)
        #expect(outcome.foregroundBeforeDispatch == third)
        #expect(harness.activatedPIDs == [target.pid])
        #expect(recovery.requests == [
            RecoveryRequest(desired: third, targetPID: target.pid),
        ])
    }

    @Test
    func thirdAppTransitionBlocksWithoutActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let harness = ForegroundHarness(current: third)

        let outcome = harness.makeCoordinator().prepare(
            original: original,
            targetPID: 20,
            backgroundPrepared: true
        )

        #expect(outcome.mode == .blockedByUserChange)
        #expect(outcome.foregroundBeforeDispatch == third)
        #expect(harness.activatedPIDs.isEmpty)
    }

    @Test
    func missingOriginalForegroundEvidenceBlocksPreparation() {
        let harness = ForegroundHarness(current: nil)

        let outcome = harness.makeCoordinator().prepare(
            original: nil,
            targetPID: 20,
            backgroundPrepared: true
        )

        #expect(outcome.mode == .blockedByUserChange)
        #expect(outcome.foregroundBeforeDispatch == nil)
        #expect(harness.activatedPIDs.isEmpty)
    }

    @Test
    func restoreRequiresForegroundFallback() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(current: target, activatableApplications: [original])

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: target.pid,
            fallbackUsed: false
        )

        #expect(restored == false)
        #expect(harness.activatedPIDs.isEmpty)
        #expect(harness.current == target)
    }

    @Test
    func restoreActivatesOriginalWhileTargetRemainsFrontmost() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(current: target, activatableApplications: [original])

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: target.pid,
            fallbackUsed: true
        )

        #expect(restored)
        #expect(harness.activatedPIDs == [original.pid])
        #expect(harness.current == original)
    }

    @Test
    func restoreWaitsForDelayedOriginalAfterOneActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(
            current: target,
            activatableApplications: [original],
            activationDelaySamples: 1
        )

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: target.pid,
            fallbackUsed: true
        )

        #expect(restored)
        #expect(harness.activatedPIDs == [original.pid])
        #expect(harness.current == original)
    }

    @Test
    func restoreTimeoutReturnsFalseAfterOneActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(
            current: target,
            activatableApplications: [original],
            completesActivation: false
        )

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: target.pid,
            fallbackUsed: true
        )

        #expect(restored == false)
        #expect(harness.activatedPIDs == [original.pid])
        #expect(harness.current == target)
    }

    @Test
    func thirdAppDuringRestoreWinsWithoutSecondActivation() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let harness = ForegroundHarness(
            current: target,
            activatableApplications: [original],
            foregroundSamplesAfterActivation: [third]
        )

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: target.pid,
            fallbackUsed: true
        )

        #expect(restored == false)
        #expect(harness.activatedPIDs == [original.pid])
    }

    @Test
    func restoreDoesNotOverrideThirdApp() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let harness = ForegroundHarness(current: third, activatableApplications: [original])

        let restored = harness.makeCoordinator().restore(
            original: original,
            targetPID: 20,
            fallbackUsed: true
        )

        #expect(restored == false)
        #expect(harness.activatedPIDs.isEmpty)
        #expect(harness.current == third)
    }

    @Test
    func restoreDoesNotClaimWorkWhenOriginalWasTarget() {
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = ForegroundHarness(current: target, activatableApplications: [target])

        let restored = harness.makeCoordinator().restore(
            original: target,
            targetPID: target.pid,
            fallbackUsed: true
        )

        #expect(restored == false)
        #expect(harness.activatedPIDs.isEmpty)
    }

    @Test
    func lateTargetActivationRestoresOriginalAndReleasesRecovery() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = LateRecoveryHarness(current: original)
        let registry = harness.makeRegistry()

        registry.arm(desired: original, targetPID: target.pid)
        #expect(registry.activeRecoveryCount == 1)
        #expect(harness.scheduledLifetime == 5)

        harness.emit(target)
        #expect(harness.activatedPIDs == [original.pid])
        #expect(registry.activeRecoveryCount == 1)

        harness.emit(original)
        #expect(registry.activeRecoveryCount == 0)
        #expect(harness.observerActive == false)
        #expect(harness.expiryActive == false)
    }

    @Test
    func thirdAppUpdatesDesiredAndKeepsLateRecoveryArmed() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let harness = LateRecoveryHarness(current: original)
        let registry = harness.makeRegistry()

        registry.arm(desired: original, targetPID: 20)
        harness.emit(third)

        #expect(harness.activatedPIDs.isEmpty)
        #expect(registry.activeRecoveryCount == 1)
        #expect(harness.observerActive)
        #expect(harness.expiryActive)

        harness.expire()
        #expect(registry.activeRecoveryCount == 0)
    }

    @Test
    func latestThirdSelectionWinsWhenTargetAppearsLate() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let firstThird = ForegroundApplicationSnapshot(pid: 30, bundleID: "third.one")
        let latestThird = ForegroundApplicationSnapshot(pid: 40, bundleID: "third.two")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = LateRecoveryHarness(current: original)
        let registry = harness.makeRegistry()

        registry.arm(desired: original, targetPID: target.pid)
        harness.emit(firstThird)
        harness.emit(latestThird)
        harness.emit(target)

        #expect(harness.activatedPIDs == [latestThird.pid])
        #expect(registry.activeRecoveryCount == 1)

        harness.emit(latestThird)
        #expect(registry.activeRecoveryCount == 0)
        #expect(harness.observerActive == false)
        #expect(harness.expiryActive == false)
    }

    @Test
    func queuedTargetNotificationDoesNotOverrideCurrentThirdApp() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")
        let harness = LateRecoveryHarness(current: original)
        let registry = harness.makeRegistry()

        registry.arm(desired: original, targetPID: target.pid)
        harness.emit(target, current: third)

        #expect(harness.activatedPIDs.isEmpty)
        #expect(registry.activeRecoveryCount == 0)
        #expect(harness.observerActive == false)
        #expect(harness.expiryActive == false)
    }

    @Test
    func expiryReleasesLateRecoveryAndIgnoresLaterTarget() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")
        let harness = LateRecoveryHarness(current: original)
        let registry = harness.makeRegistry()

        registry.arm(desired: original, targetPID: target.pid)
        harness.expire()

        #expect(registry.activeRecoveryCount == 0)
        #expect(harness.observerActive == false)
        #expect(harness.expiryActive == false)

        harness.emit(target)
        #expect(harness.activatedPIDs.isEmpty)
    }
}

private final class ForegroundHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var currentSnapshot: ForegroundApplicationSnapshot?
    private var applicationsByPID: [pid_t: ForegroundApplicationSnapshot]
    private var storedActivatedPIDs: [pid_t] = []
    private let activationDelaySamples: Int
    private let completesActivation: Bool
    private let foregroundSamplesAfterActivation: [ForegroundApplicationSnapshot?]
    private let lateRecovery: any ForegroundLateRecoveryArming
    private var pendingApplication: ForegroundApplicationSnapshot?
    private var remainingDelaySamples = 0
    private var queuedForegroundSamples: [ForegroundApplicationSnapshot?] = []

    init(
        current: ForegroundApplicationSnapshot?,
        activatableApplications: [ForegroundApplicationSnapshot] = [],
        activationDelaySamples: Int = 0,
        completesActivation: Bool = true,
        foregroundSamplesAfterActivation: [ForegroundApplicationSnapshot?] = [],
        lateRecovery: any ForegroundLateRecoveryArming = NoopLateRecovery()
    ) {
        currentSnapshot = current
        applicationsByPID = Dictionary(
            uniqueKeysWithValues: activatableApplications.map { ($0.pid, $0) }
        )
        self.activationDelaySamples = activationDelaySamples
        self.completesActivation = completesActivation
        self.foregroundSamplesAfterActivation = foregroundSamplesAfterActivation
        self.lateRecovery = lateRecovery
    }

    var current: ForegroundApplicationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        if queuedForegroundSamples.isEmpty == false {
            currentSnapshot = queuedForegroundSamples.removeFirst()
            return currentSnapshot
        }
        if let pendingApplication {
            if remainingDelaySamples == 0 {
                currentSnapshot = pendingApplication
                self.pendingApplication = nil
            } else {
                remainingDelaySamples -= 1
            }
        }
        return currentSnapshot
    }

    var activatedPIDs: [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return storedActivatedPIDs
    }

    func makeCoordinator() -> ForegroundFallbackCoordinator {
        ForegroundFallbackCoordinator(
            foregroundApplication: { [weak self] in self?.current },
            activateApplication: { [weak self] pid in self?.activate(pid: pid) ?? false },
            lateRecovery: lateRecovery
        )
    }

    private func activate(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedActivatedPIDs.append(pid)
        guard let application = applicationsByPID[pid] else {
            return false
        }
        if completesActivation {
            pendingApplication = application
            remainingDelaySamples = activationDelaySamples
            queuedForegroundSamples = foregroundSamplesAfterActivation
        }
        return true
    }
}

private struct RecoveryRequest: Equatable {
    let desired: ForegroundApplicationSnapshot
    let targetPID: pid_t
}

private final class LateRecoverySpy: ForegroundLateRecoveryArming, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [RecoveryRequest] = []

    var requests: [RecoveryRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func arm(desired: ForegroundApplicationSnapshot, targetPID: pid_t) {
        lock.lock()
        storedRequests.append(RecoveryRequest(desired: desired, targetPID: targetPID))
        lock.unlock()
    }
}

private struct NoopLateRecovery: ForegroundLateRecoveryArming {
    func arm(desired _: ForegroundApplicationSnapshot, targetPID _: pid_t) {}
}

private final class LateRecoveryHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var currentSnapshot: ForegroundApplicationSnapshot?
    private var observer: (@Sendable (ForegroundApplicationSnapshot?) -> Void)?
    private var expiry: (@Sendable () -> Void)?
    private var storedActivatedPIDs: [pid_t] = []
    private var storedScheduledLifetime: TimeInterval?

    init(current: ForegroundApplicationSnapshot?) {
        currentSnapshot = current
    }

    var activatedPIDs: [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return storedActivatedPIDs
    }

    var scheduledLifetime: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return storedScheduledLifetime
    }

    var observerActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    var expiryActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expiry != nil
    }

    func makeRegistry() -> ForegroundLateRecoveryRegistry {
        ForegroundLateRecoveryRegistry(
            lifetime: 5,
            foregroundApplication: { [weak self] in self?.current() },
            activateApplication: { [weak self] pid in self?.activate(pid: pid) ?? false },
            observeActivations: { [weak self] handler in
                self?.installObserver(handler) ?? ForegroundLateRecoveryCancellation {}
            },
            scheduleExpiry: { [weak self] lifetime, handler in
                self?.installExpiry(after: lifetime, handler: handler)
                    ?? ForegroundLateRecoveryCancellation {}
            }
        )
    }

    func emit(
        _ snapshot: ForegroundApplicationSnapshot?,
        current: ForegroundApplicationSnapshot? = nil
    ) {
        let handler: (@Sendable (ForegroundApplicationSnapshot?) -> Void)?
        lock.lock()
        currentSnapshot = current ?? snapshot
        handler = observer
        lock.unlock()
        handler?(snapshot)
    }

    func expire() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        handler = expiry
        lock.unlock()
        handler?()
    }

    private func current() -> ForegroundApplicationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshot
    }

    private func activate(pid: pid_t) -> Bool {
        lock.lock()
        storedActivatedPIDs.append(pid)
        lock.unlock()
        return true
    }

    private func installObserver(
        _ handler: @escaping @Sendable (ForegroundApplicationSnapshot?) -> Void
    ) -> ForegroundLateRecoveryCancellation {
        lock.lock()
        observer = handler
        lock.unlock()
        return ForegroundLateRecoveryCancellation { [weak self] in
            self?.clearObserver()
        }
    }

    private func installExpiry(
        after lifetime: TimeInterval,
        handler: @escaping @Sendable () -> Void
    ) -> ForegroundLateRecoveryCancellation {
        lock.lock()
        storedScheduledLifetime = lifetime
        expiry = handler
        lock.unlock()
        return ForegroundLateRecoveryCancellation { [weak self] in
            self?.clearExpiry()
        }
    }

    private func clearObserver() {
        lock.lock()
        observer = nil
        lock.unlock()
    }

    private func clearExpiry() {
        lock.lock()
        expiry = nil
        lock.unlock()
    }
}

import Foundation

enum ForegroundPreparationMode: Equatable, Sendable {
    case background
    case foregroundFallback
    case blockedByUserChange
}

struct ForegroundPreparationOutcome: Equatable, Sendable {
    let mode: ForegroundPreparationMode
    let foregroundBeforeDispatch: ForegroundApplicationSnapshot?
}

struct ForegroundFallbackCoordinator: Sendable {
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let activateApplication: @Sendable (pid_t) -> Bool
    private let lateRecovery: any ForegroundLateRecoveryArming

    init(
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot? =
            ForegroundApplicationSnapshot.capture,
        activateApplication: @escaping @Sendable (pid_t) -> Bool = {
            ForegroundApplicationSnapshot.activate(pid: $0)
        },
        lateRecovery: any ForegroundLateRecoveryArming = ForegroundLateRecoveryRegistry.shared
    ) {
        self.foregroundApplication = foregroundApplication
        self.activateApplication = activateApplication
        self.lateRecovery = lateRecovery
    }

    func prepare(
        original: ForegroundApplicationSnapshot?,
        targetPID: pid_t,
        backgroundPrepared: Bool
    ) -> ForegroundPreparationOutcome {
        let current = foregroundApplication()
        if current?.pid == targetPID {
            return ForegroundPreparationOutcome(
                mode: .foregroundFallback,
                foregroundBeforeDispatch: current
            )
        }

        guard let original, current == original else {
            return ForegroundPreparationOutcome(
                mode: .blockedByUserChange,
                foregroundBeforeDispatch: current
            )
        }

        if backgroundPrepared {
            return ForegroundPreparationOutcome(
                mode: .background,
                foregroundBeforeDispatch: current
            )
        }

        guard activateApplication(targetPID) else {
            return ForegroundPreparationOutcome(
                mode: .blockedByUserChange,
                foregroundBeforeDispatch: foregroundApplication()
            )
        }

        switch waitForForeground(
            pid: targetPID,
            whilePID: original.pid
        ) {
        case let .reached(foregroundBeforeDispatch):
            return ForegroundPreparationOutcome(
                mode: .foregroundFallback,
                foregroundBeforeDispatch: foregroundBeforeDispatch
            )
        case let .blockedByThirdApp(foregroundBeforeDispatch):
            lateRecovery.arm(desired: foregroundBeforeDispatch, targetPID: targetPID)
            return ForegroundPreparationOutcome(
                mode: .blockedByUserChange,
                foregroundBeforeDispatch: foregroundBeforeDispatch
            )
        case let .timedOut(foregroundBeforeDispatch):
            lateRecovery.arm(desired: original, targetPID: targetPID)
            return ForegroundPreparationOutcome(
                mode: .blockedByUserChange,
                foregroundBeforeDispatch: foregroundBeforeDispatch
            )
        }
    }

    func restore(
        original: ForegroundApplicationSnapshot?,
        targetPID: pid_t,
        fallbackUsed: Bool
    ) -> Bool {
        guard fallbackUsed,
              let original,
              original.pid != targetPID,
              foregroundApplication()?.pid == targetPID,
              activateApplication(original.pid)
        else {
            return false
        }
        switch waitForForeground(
            pid: original.pid,
            whilePID: targetPID
        ) {
        case .reached:
            return true
        case .blockedByThirdApp, .timedOut:
            return false
        }
    }

    private func waitForForeground(
        pid: pid_t,
        whilePID: pid_t
    ) -> ForegroundWaitOutcome {
        let waited = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: 2000,
            sample: foregroundApplication,
            isSatisfied: { snapshot in
                guard let observedPID = snapshot?.pid else {
                    return false
                }
                return observedPID == pid || observedPID != whilePID
            }
        )
        if waited.sample?.pid == pid, let snapshot = waited.sample {
            return .reached(snapshot)
        }
        if waited.satisfied, let snapshot = waited.sample {
            return .blockedByThirdApp(snapshot)
        }
        return .timedOut(waited.sample)
    }
}

private enum ForegroundWaitOutcome: Sendable {
    case reached(ForegroundApplicationSnapshot)
    case blockedByThirdApp(ForegroundApplicationSnapshot)
    case timedOut(ForegroundApplicationSnapshot?)
}

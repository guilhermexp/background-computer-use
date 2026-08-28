import AppKit
import Foundation

protocol ForegroundLateRecoveryArming: Sendable {
    func arm(desired: ForegroundApplicationSnapshot, targetPID: pid_t)
}

final class ForegroundLateRecoveryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?

    init(_ cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let action: (@Sendable () -> Void)?
        lock.lock()
        action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }

    deinit {
        cancel()
    }
}

final class ForegroundLateRecoveryRegistry: ForegroundLateRecoveryArming, @unchecked Sendable {
    typealias ObserveActivations = @Sendable (
        @escaping @Sendable (ForegroundApplicationSnapshot?) -> Void
    ) -> ForegroundLateRecoveryCancellation
    typealias ScheduleExpiry = @Sendable (
        TimeInterval,
        @escaping @Sendable () -> Void
    ) -> ForegroundLateRecoveryCancellation

    static let shared = makeLive()

    private let lock = NSLock()
    private let lifetime: TimeInterval
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let activateApplication: @Sendable (pid_t) -> Bool
    private let observeActivations: ObserveActivations
    private let scheduleExpiry: ScheduleExpiry
    private var sessions: [UUID: ForegroundLateRecoverySession] = [:]

    init(
        lifetime: TimeInterval,
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot?,
        activateApplication: @escaping @Sendable (pid_t) -> Bool,
        observeActivations: @escaping ObserveActivations,
        scheduleExpiry: @escaping ScheduleExpiry
    ) {
        self.lifetime = lifetime
        self.foregroundApplication = foregroundApplication
        self.activateApplication = activateApplication
        self.observeActivations = observeActivations
        self.scheduleExpiry = scheduleExpiry
    }

    var activeRecoveryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    func arm(desired: ForegroundApplicationSnapshot, targetPID: pid_t) {
        let id = UUID()
        let session = ForegroundLateRecoverySession(
            id: id,
            desired: desired,
            targetPID: targetPID,
            foregroundApplication: foregroundApplication,
            activateApplication: activateApplication,
            onFinish: { [weak self] id in
                self?.remove(id: id)
            }
        )

        lock.lock()
        sessions[id] = session
        lock.unlock()

        session.start(
            lifetime: lifetime,
            observeActivations: observeActivations,
            scheduleExpiry: scheduleExpiry
        )
        session.observe(foregroundApplication())
    }

    deinit {
        let activeSessions: [ForegroundLateRecoverySession]
        lock.lock()
        activeSessions = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for session in activeSessions {
            session.cancel()
        }
    }

    private func remove(id: UUID) {
        lock.lock()
        sessions.removeValue(forKey: id)
        lock.unlock()
    }

    private static func makeLive() -> ForegroundLateRecoveryRegistry {
        ForegroundLateRecoveryRegistry(
            lifetime: 5,
            foregroundApplication: ForegroundApplicationSnapshot.capture,
            activateApplication: { ForegroundApplicationSnapshot.activate(pid: $0) },
            observeActivations: { handler in
                let center = NSWorkspace.shared.notificationCenter
                let token = center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                    handler(application.map {
                        ForegroundApplicationSnapshot(
                            pid: $0.processIdentifier,
                            bundleID: $0.bundleIdentifier
                        )
                    })
                }
                let observer = ForegroundWorkspaceObserver(center: center, token: token)
                return ForegroundLateRecoveryCancellation {
                    observer.cancel()
                }
            },
            scheduleExpiry: { lifetime, handler in
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(
                    deadline: .now() + .milliseconds(Int((lifetime * 1000).rounded()))
                )
                timer.setEventHandler(handler: handler)
                timer.resume()
                return ForegroundLateRecoveryCancellation {
                    timer.setEventHandler {}
                    timer.cancel()
                }
            }
        )
    }
}

private final class ForegroundWorkspaceObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func cancel() {
        let token: NSObjectProtocol?
        lock.lock()
        token = self.token
        self.token = nil
        lock.unlock()
        if let token {
            center.removeObserver(token)
        }
    }
}

private final class ForegroundLateRecoverySession: @unchecked Sendable {
    private enum State {
        case waitingTarget
        case restorationRequested
        case finished
    }

    private let lock = NSRecursiveLock()
    private let id: UUID
    private var desiredApplication: ForegroundApplicationSnapshot
    private let targetPID: pid_t
    private let foregroundApplication: @Sendable () -> ForegroundApplicationSnapshot?
    private let activateApplication: @Sendable (pid_t) -> Bool
    private let onFinish: @Sendable (UUID) -> Void
    private var state: State = .waitingTarget
    private var observerCancellation: ForegroundLateRecoveryCancellation?
    private var expiryCancellation: ForegroundLateRecoveryCancellation?
    private var didCleanUp = false

    init(
        id: UUID,
        desired: ForegroundApplicationSnapshot,
        targetPID: pid_t,
        foregroundApplication: @escaping @Sendable () -> ForegroundApplicationSnapshot?,
        activateApplication: @escaping @Sendable (pid_t) -> Bool,
        onFinish: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        desiredApplication = desired
        self.targetPID = targetPID
        self.foregroundApplication = foregroundApplication
        self.activateApplication = activateApplication
        self.onFinish = onFinish
    }

    func start(
        lifetime: TimeInterval,
        observeActivations: ForegroundLateRecoveryRegistry.ObserveActivations,
        scheduleExpiry: ForegroundLateRecoveryRegistry.ScheduleExpiry
    ) {
        let observer = observeActivations { [weak self] snapshot in
            self?.observe(snapshot)
        }
        let expiry = scheduleExpiry(lifetime) { [weak self] in
            self?.cancel()
        }

        lock.lock()
        let alreadyFinished = didCleanUp
        if alreadyFinished == false {
            observerCancellation = observer
            expiryCancellation = expiry
        }
        lock.unlock()

        if alreadyFinished {
            observer.cancel()
            expiry.cancel()
        }
    }

    func observe(_ snapshot: ForegroundApplicationSnapshot?) {
        guard let snapshot else {
            return
        }
        let pid = snapshot.pid

        var shouldCleanUp = false
        lock.lock()
        switch state {
        case .waitingTarget:
            if pid == targetPID {
                let current = foregroundApplication()
                if current?.pid == targetPID {
                    state = .restorationRequested
                    if activateApplication(desiredApplication.pid) == false {
                        state = .finished
                        shouldCleanUp = true
                    }
                } else if let current {
                    desiredApplication = current
                    state = .finished
                    shouldCleanUp = true
                }
            } else {
                desiredApplication = snapshot
            }
        case .restorationRequested:
            if pid != targetPID {
                state = .finished
                shouldCleanUp = true
            }
        case .finished:
            break
        }
        lock.unlock()

        if shouldCleanUp {
            cleanUp()
        }
    }

    func cancel() {
        lock.lock()
        state = .finished
        lock.unlock()
        cleanUp()
    }

    private func cleanUp() {
        let observer: ForegroundLateRecoveryCancellation?
        let expiry: ForegroundLateRecoveryCancellation?
        lock.lock()
        guard didCleanUp == false else {
            lock.unlock()
            return
        }
        didCleanUp = true
        observer = observerCancellation
        expiry = expiryCancellation
        observerCancellation = nil
        expiryCancellation = nil
        lock.unlock()

        observer?.cancel()
        expiry?.cancel()
        onFinish(id)
    }
}

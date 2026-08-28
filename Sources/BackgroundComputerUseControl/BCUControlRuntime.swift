import AppKit
import BackgroundComputerUseControlShared
import BackgroundComputerUseLockedShared
import Darwin
import Foundation

public final class BCUControlRuntime: @unchecked Sendable {
    public let policyStore: AppPolicyStore
    public let controls: SessionControls
    public let history: ActivityHistoryStore
    private let queue = ApprovalQueue()
    private let approvalPresentationLock = NSLock()
    private let presenter: ApprovalWindowPresenter
    private var menuBarController: MenuBarController?
    private var viewModel: ControlViewModel?
    private var pipController: PiPWindowController?
    private let lockedBroker: LockedBrokerControlClient
    private let lockedCoordinator: LockedUseCoordinator
    private let coreClient: CoreXPCClient
    private let taskSessionID: String
    private var observers: [NSObjectProtocol] = []
    private var heartbeatTimer: DispatchSourceTimer?
    private let lockedUsePreferenceKey = "BCULockedUseOptIn"

    public init(
        policyFileURL: URL? = nil,
        approvalTimeout: TimeInterval = 30
    ) throws {
        let fileURL = policyFileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundComputerUse", isDirectory: true)
            .appendingPathComponent("policies.json")
        policyStore = try AppPolicyStore(fileURL: fileURL)
        let sessionID = UUID().uuidString
        taskSessionID = sessionID
        let core = CoreXPCClient(sessionID: sessionID)
        coreClient = core
        let broker = LockedBrokerControlClient()
        lockedBroker = broker
        let coordinator = LockedUseCoordinator(
            shield: DisplayShieldController(),
            broker: broker
        )
        lockedCoordinator = coordinator
        let store = policyStore
        controls = SessionControls(onStop: {
            coordinator.stop()
            store.endAllSessions()
        }, onStateChange: { state in
            guard let coreState = CoreSessionState(rawValue: state.rawValue) else { return }
            _ = core.setState(coreState)
        })
        history = ActivityHistoryStore()
        presenter = ApprovalWindowPresenter(timeout: approvalTimeout)
    }

    public func start() {
        let work = { @MainActor in
            _ = NSApplication.shared
            NSApplication.shared.setActivationPolicy(.accessory)
            _ = self.coreClient.start()
            let defaults = UserDefaults.standard
            let activityCardEnabled = ActivityCardPreference.isEnabled(in: defaults)
            let pipController = PiPWindowController(isEnabled: activityCardEnabled)
            let model = ControlViewModel(
                store: self.policyStore,
                controls: self.controls,
                lockedUseOptIn: defaults.bool(forKey: self.lockedUsePreferenceKey),
                onLockedUsePreferenceChanged: { enabled in
                    defaults.set(enabled, forKey: self.lockedUsePreferenceKey)
                    if enabled == false {
                        self.lockedCoordinator.stop()
                    }
                },
                activityCardEnabled: activityCardEnabled,
                onActivityCardPreferenceChanged: { enabled in
                    defaults.set(enabled, forKey: ActivityCardPreference.key)
                    pipController.setEnabled(enabled)
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            self.pipController = pipController
            self.viewModel = model
            self.menuBarController = MenuBarController(model: model)
            self.installLockedUseObservers()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { @MainActor in work() }
        }
    }

    public func prompt(
        identity: AppIdentity,
        pid: pid_t?,
        sessionID: String
    ) -> AppPolicyDecision {
        approvalPresentationLock.lock()
        defer { approvalPresentationLock.unlock() }
        let request = ApprovalRequest(
            id: UUID().uuidString,
            identity: identity,
            pid: pid,
            sessionID: sessionID,
            operation: "Abrir e controlar este app em segundo plano"
        )
        queue.enqueue(request)
        let decision = presenter.present(request)
        queue.resolveActive(decision)
        return decision
    }

    public func allowsMutations() -> Bool {
        coreClient.allows(.mutation)
    }

    public func allowsReads() -> Bool {
        coreClient.allows(.read)
    }

    public func publishActivity(_ activity: ActivityEnvelope) {
        history.append(activity)
        DispatchQueue.main.async { @MainActor in
            self.pipController?.update(activity)
        }
    }

    @MainActor
    private func installLockedUseObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if lockedCoordinator.state == .disabled {
                beginLockedActivityIfEnabled()
            } else {
                lockedCoordinator.observeSafetyRelock()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lockedCoordinator.observeUnlockAllowed()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lockedCoordinator.displayConfigurationChanged()
        })
        startHeartbeatTimer()
    }

    private func startHeartbeatTimer() {
        guard heartbeatTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, lockedCoordinator.state != .disabled else { return }
            if lockedBroker.heartbeat(taskSessionID: taskSessionID) == false {
                _ = lockedBroker.relock(reason: "control_heartbeat_failed")
            }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func beginLockedActivityIfEnabled() {
        guard UserDefaults.standard.bool(forKey: lockedUsePreferenceKey),
              controls.state != .stopped,
              lockedCoordinator.state == .disabled,
              let controlIdentity = try? CodeSignatureIdentity().resolve(pid: getpid()),
              let coreIdentity = try? CodeSignatureIdentity().resolve(
                  url: Bundle.main.bundleURL
                      .appendingPathComponent("Contents/XPCServices", isDirectory: true)
                      .appendingPathComponent("BackgroundComputerUseCoreXPCService.xpc", isDirectory: true)
              ),
              EmbeddedCoreIdentityPolicy.accepts(control: controlIdentity, core: coreIdentity),
              let bootSession = Self.bootSessionID()
        else {
            return
        }
        let now = Date()
        guard let lease = try? LockedUseLease.issue(
            taskSessionID: taskSessionID,
            uid: getuid(),
            bootSessionID: bootSession,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(30),
            coreDesignatedRequirement: coreIdentity.designatedRequirement,
            controlDesignatedRequirement: controlIdentity.designatedRequirement
        ), lockedCoordinator.enable(lease: lease) else {
            return
        }
        lockedCoordinator.observeLock()
    }

    private static func bootSessionID() -> String? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
    }
}

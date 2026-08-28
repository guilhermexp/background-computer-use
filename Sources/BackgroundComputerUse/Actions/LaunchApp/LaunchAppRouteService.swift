import AppKit
import BackgroundComputerUseControlShared
import Foundation

struct LaunchAppCandidate {
    let url: URL
    let identity: AppIdentity
    let existingPID: pid_t?
}

protocol LaunchAppResolving {
    func resolve(request: LaunchAppRequest) throws -> LaunchAppCandidate
}

protocol LaunchAppAuthorizing {
    func authorize(identity: AppIdentity, pid: pid_t?, sessionID: String) -> AppPolicyDecision
}

protocol LaunchAppTransporting: AnyObject {
    func launch(url: URL, activates: Bool) throws -> pid_t
}

enum LaunchAppError: Error {
    case invalidTarget
    case appNotFound
    case bundleIDMismatch
    case launchTimedOut
    case launchFailed(String)
}

struct WorkspaceLaunchAppResolver: LaunchAppResolving {
    private let identityResolver = CodeSignatureIdentity()

    func resolve(request: LaunchAppRequest) throws -> LaunchAppCandidate {
        let bundleID = request.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appPath = request.appPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (bundleID?.isEmpty == false) != (appPath?.isEmpty == false) else {
            throw LaunchAppError.invalidTarget
        }

        let url: URL
        if let bundleID, bundleID.isEmpty == false {
            guard let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw LaunchAppError.appNotFound
            }
            url = resolved.resolvingSymlinksInPath().standardizedFileURL
        } else if let appPath, appPath.isEmpty == false {
            url = URL(fileURLWithPath: appPath).resolvingSymlinksInPath().standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path), url.pathExtension == "app" else {
                throw LaunchAppError.appNotFound
            }
        } else {
            throw LaunchAppError.invalidTarget
        }

        let requestedBundleID = bundleID
        let running = NSWorkspace.shared.runningApplications.first { app in
            if let requestedBundleID {
                return app.bundleIdentifier == requestedBundleID
            }
            return app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == url
        }
        let identity = try running.map { try identityResolver.resolve(pid: $0.processIdentifier) }
            ?? identityResolver.resolve(url: url)
        if let requestedBundleID, identity.bundleID != requestedBundleID {
            throw LaunchAppError.bundleIDMismatch
        }
        return LaunchAppCandidate(
            url: url,
            identity: identity,
            existingPID: running?.processIdentifier
        )
    }
}

struct DenyLaunchAppAuthorizer: LaunchAppAuthorizing {
    func authorize(identity _: AppIdentity, pid _: pid_t?, sessionID _: String) -> AppPolicyDecision {
        .deny
    }
}

final class WorkspaceLaunchTransport: LaunchAppTransporting, @unchecked Sendable {
    func launch(url: URL, activates: Bool) throws -> pid_t {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        let result = LaunchResultBox()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            if let application {
                result.set(.success(application.processIdentifier))
            } else {
                result.set(.failure(LaunchAppError.launchFailed(error?.localizedDescription ?? "unknown error")))
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while result.value == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard let value = result.value else { throw LaunchAppError.launchTimedOut }
        return try value.get()
    }
}

private final class LaunchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<pid_t, Error>?

    var value: Result<pid_t, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Result<pid_t, Error>) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

struct LaunchAppRouteService {
    private let resolver: any LaunchAppResolving
    private let authorizer: any LaunchAppAuthorizing
    private let launcher: any LaunchAppTransporting
    private let windowProvider: (pid_t) -> [String]
    private let foregroundPID: @Sendable () -> pid_t?
    private let foregroundCoordinator: ForegroundFallbackCoordinator
    private let controlPID: pid_t

    init(
        resolver: any LaunchAppResolving = WorkspaceLaunchAppResolver(),
        authorizer: any LaunchAppAuthorizing = DenyLaunchAppAuthorizer(),
        launcher: any LaunchAppTransporting = WorkspaceLaunchTransport(),
        windowProvider: @escaping (pid_t) -> [String] = { pid in
            (try? WindowListService().listWindows(pid: pid).windows.map(\.windowID)) ?? []
        },
        foregroundPID: @escaping @Sendable () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        activatePID: @escaping @Sendable (pid_t) -> Bool = {
            ForegroundApplicationSnapshot.activate(pid: $0)
        },
        controlPID: pid_t = getpid()
    ) {
        self.resolver = resolver
        self.authorizer = authorizer
        self.launcher = launcher
        self.windowProvider = windowProvider
        self.foregroundPID = foregroundPID
        self.controlPID = controlPID
        foregroundCoordinator = ForegroundFallbackCoordinator(
            foregroundApplication: {
                foregroundPID().map {
                    ForegroundApplicationSnapshot(pid: $0, bundleID: nil)
                }
            },
            activateApplication: activatePID
        )
    }

    func launchApp(request: LaunchAppRequest) throws -> LaunchAppResponse {
        let foregroundBefore = foregroundPID()
        var foregroundObservation = LaunchForegroundObservation(
            originalPID: foregroundBefore,
            controlPID: controlPID
        )
        func observeForeground(targetPID: pid_t?) {
            foregroundObservation.record(currentPID: foregroundPID(), targetPID: targetPID)
        }

        let candidate = try resolver.resolve(request: request)
        observeForeground(targetPID: candidate.existingPID)
        let decision = authorizer.authorize(
            identity: candidate.identity,
            pid: candidate.existingPID,
            sessionID: request.sessionID
        )
        observeForeground(targetPID: candidate.existingPID)
        guard decision == .allowOnce || decision == .alwaysAllow else {
            let foregroundAfter = foregroundPID()
            return LaunchAppResponse(
                contractVersion: ContractVersion.current,
                ok: false,
                classification: .unsupported,
                failureDomain: .unsupported,
                summary: decision == .ask
                    ? "Control approval is required before this app can be launched."
                    : "Control denied access to this app.",
                identity: candidate.identity,
                policyDecision: decision,
                pid: candidate.existingPID,
                launchState: .blocked,
                windows: [],
                activates: false,
                foregroundPIDBefore: foregroundBefore,
                foregroundPIDAfter: foregroundAfter,
                foregroundPreserved: foregroundBefore == foregroundAfter,
                foregroundFallbackUsed: false,
                foregroundRestored: false
            )
        }

        let launchState: LaunchAppStateDTO
        let pid: pid_t
        if let existingPID = candidate.existingPID {
            launchState = .alreadyRunning
            pid = existingPID
        } else {
            launchState = .launched
            pid = try launcher.launch(url: candidate.url, activates: false)
        }
        observeForeground(targetPID: pid)
        let sampleWindows = {
            observeForeground(targetPID: pid)
            let windows = windowProvider(pid)
            observeForeground(targetPID: pid)
            return windows
        }
        let windows: [String] = if case .launched = launchState {
            ConditionedActionWait.poll(
                intervalMs: 50,
                deadlineMs: 1000,
                sample: sampleWindows,
                isSatisfied: { $0.isEmpty == false }
            ).sample
        } else {
            sampleWindows()
        }
        observeForeground(targetPID: pid)
        let foregroundFallbackUsed = foregroundObservation.targetBecameForeground
        let restorationPID = foregroundObservation.latestNonTransientPID
        let restorationSourcePID: pid_t? = if foregroundObservation.currentPID == pid,
                                              foregroundFallbackUsed
        {
            pid
        } else if foregroundObservation.currentPID == controlPID {
            controlPID
        } else {
            nil
        }
        let foregroundSelectionRestored = if let restorationSourcePID {
            foregroundCoordinator.restore(
                original: restorationPID.map {
                    ForegroundApplicationSnapshot(pid: $0, bundleID: nil)
                },
                targetPID: restorationSourcePID,
                fallbackUsed: true
            )
        } else {
            false
        }
        let foregroundRestored = foregroundSelectionRestored && restorationPID == foregroundBefore
        let foregroundAfter = foregroundPID()
        let foregroundPreserved = foregroundBefore == foregroundAfter
        let summary = if foregroundRestored {
            "The authorized app is running and BCU restored the previous foreground application."
        } else if foregroundSelectionRestored {
            "The authorized app is running and BCU restored the newer foreground selection."
        } else if foregroundPreserved {
            "The authorized app is running and the foreground application is unchanged."
        } else if foregroundAfter == restorationPID {
            "The authorized app is running and the latest foreground selection is active."
        } else if foregroundFallbackUsed {
            "The authorized app is running, but the previous foreground application was not restored."
        } else {
            "The authorized app is running and an unrelated foreground change was preserved."
        }
        return LaunchAppResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            classification: .success,
            failureDomain: nil,
            summary: summary,
            identity: candidate.identity,
            policyDecision: decision,
            pid: pid,
            launchState: launchState,
            windows: windows,
            activates: false,
            foregroundPIDBefore: foregroundBefore,
            foregroundPIDAfter: foregroundAfter,
            foregroundPreserved: foregroundPreserved,
            foregroundFallbackUsed: foregroundFallbackUsed,
            foregroundRestored: foregroundRestored
        )
    }
}

private struct LaunchForegroundObservation {
    let originalPID: pid_t?
    let controlPID: pid_t
    private(set) var targetBecameForeground = false
    private(set) var latestNonTransientPID: pid_t?
    private(set) var currentPID: pid_t?

    init(originalPID: pid_t?, controlPID: pid_t) {
        self.originalPID = originalPID
        self.controlPID = controlPID
        latestNonTransientPID = originalPID
        currentPID = originalPID
    }

    mutating func record(currentPID: pid_t?, targetPID: pid_t?) {
        self.currentPID = currentPID
        guard let currentPID else { return }
        if let targetPID, currentPID == targetPID {
            if originalPID != targetPID {
                targetBecameForeground = true
            }
            return
        }
        guard currentPID != controlPID else { return }
        latestNonTransientPID = currentPID
    }
}

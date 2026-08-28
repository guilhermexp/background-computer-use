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
    private let foregroundPID: () -> pid_t?

    init(
        resolver: any LaunchAppResolving = WorkspaceLaunchAppResolver(),
        authorizer: any LaunchAppAuthorizing = DenyLaunchAppAuthorizer(),
        launcher: any LaunchAppTransporting = WorkspaceLaunchTransport(),
        windowProvider: @escaping (pid_t) -> [String] = { pid in
            (try? WindowListService().listWindows(pid: pid).windows.map(\.windowID)) ?? []
        },
        foregroundPID: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.resolver = resolver
        self.authorizer = authorizer
        self.launcher = launcher
        self.windowProvider = windowProvider
        self.foregroundPID = foregroundPID
    }

    func launchApp(request: LaunchAppRequest) throws -> LaunchAppResponse {
        let foregroundBefore = foregroundPID()
        let candidate = try resolver.resolve(request: request)
        let decision = authorizer.authorize(
            identity: candidate.identity,
            pid: candidate.existingPID,
            sessionID: request.sessionID
        )
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
                foregroundPreserved: foregroundBefore == foregroundAfter
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
        let windows: [String] = if case .launched = launchState {
            ConditionedActionWait.poll(
                intervalMs: 50,
                deadlineMs: 1000,
                sample: { windowProvider(pid) },
                isSatisfied: { $0.isEmpty == false }
            ).sample
        } else {
            windowProvider(pid)
        }
        let foregroundAfter = foregroundPID()
        let foregroundPreserved = foregroundBefore == foregroundAfter
        return LaunchAppResponse(
            contractVersion: ContractVersion.current,
            ok: foregroundPreserved,
            classification: foregroundPreserved ? .success : .effectNotVerified,
            failureDomain: foregroundPreserved ? nil : .backgroundSafety,
            summary: foregroundPreserved
                ? "The authorized app is running without foreground activation."
                : "The app launched, but the foreground application changed.",
            identity: candidate.identity,
            policyDecision: decision,
            pid: pid,
            launchState: launchState,
            windows: windows,
            activates: false,
            foregroundPIDBefore: foregroundBefore,
            foregroundPIDAfter: foregroundAfter,
            foregroundPreserved: foregroundPreserved
        )
    }
}

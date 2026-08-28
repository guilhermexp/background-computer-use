@testable import BackgroundComputerUse
import BackgroundComputerUseControlShared
import Foundation
import Testing

struct LaunchAppPolicyTests {
    private let identity = AppIdentity(
        bundleID: "com.example.Target",
        teamID: "TEAM123",
        designatedRequirement: "identifier \"com.example.Target\" and certificate leaf[subject.OU] = \"TEAM123\""
    )

    @Test
    func launchAppRouteDocumentsForegroundFallback() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.launchApp.rawValue }
        )
        let fields = route.response.fields

        #expect(fields.contains {
            $0.name == "foregroundFallbackUsed" && $0.type == "boolean" && $0.required
        })
        #expect(fields.contains {
            $0.name == "foregroundRestored" && $0.type == "boolean" && $0.required
        })
    }

    @Test
    func askAndDenyNeverInvokeWorkspaceLaunch() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .ask),
            launcher: launcher,
            windowProvider: { _ in [] },
            foregroundPID: { 100 }
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )
        #expect(response.ok == false)
        #expect(response.policyDecision == .ask)
        #expect(launcher.calls == 0)
    }

    @Test
    func allowedLaunchDisablesActivationAndReturnsExactPID() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .allowOnce),
            launcher: launcher,
            windowProvider: { pid in ["w_\(pid)"] },
            foregroundPID: { 100 }
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )
        #expect(response.ok)
        #expect(response.pid == 800)
        #expect(response.launchState == .launched)
        #expect(response.windows == ["w_800"])
        #expect(launcher.activationFlags == [false])
    }

    @Test
    func existingProcessForegroundChangeRestoresWithoutRelaunch() throws {
        let launcher = StubLaunchTransport(resultPID: 999)
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: 321),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                foreground.setCurrentPID(321)
                return []
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )
        #expect(response.ok)
        #expect(response.pid == 321)
        #expect(response.launchState == .alreadyRunning)
        #expect(launcher.calls == 0)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored)
        #expect(response.foregroundPIDAfter == 100)
    }

    @Test
    func newLaunchWaitsForFirstWindowWithoutActivation() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        var reads = 0
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                reads += 1
                return reads < 2 ? [] : ["w_800"]
            },
            foregroundPID: { 100 }
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )
        #expect(response.windows == ["w_800"])
        #expect(reads >= 2)
        #expect(launcher.activationFlags == [false])
    }

    @Test
    func completedLaunchRestoresOriginalForegroundAndRemainsSuccess() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        var reads = 0
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                reads += 1
                if reads == 2 {
                    foreground.setCurrentPID(800)
                    return ["w_800"]
                }
                return []
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.classification == .success)
        #expect(response.failureDomain == nil)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored)
        #expect(response.foregroundPreserved)
        #expect(response.foregroundPIDAfter == 100)
        #expect(foreground.activatedPIDs == [100])
    }

    @Test
    func thirdAppTransitionAfterTargetActivationIsPreserved() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                foreground.setCurrentPID(800)
                foreground.enqueueCapturePIDs([800, 900])
                return ["w_800"]
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.classification == .success)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored == false)
        #expect(response.foregroundPreserved == false)
        #expect(response.foregroundPIDAfter == 900)
        #expect(foreground.activatedPIDs.isEmpty)
    }

    @Test
    func thirdAppObservedBeforeTargetActivationPreventsOriginalRestoration() throws {
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100, 900])
        let launcher = StubLaunchTransport(resultPID: 800, onLaunch: {
            foreground.setCurrentPID(800)
        })
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow, onAuthorize: {
                foreground.setCurrentPID(900)
            }),
            launcher: launcher,
            windowProvider: { _ in ["w_800"] },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored == false)
        #expect(response.foregroundPIDAfter == 900)
        #expect(foreground.activatedPIDs == [900])
    }

    @Test
    func targetThenThirdAppBeforeWindowDiscoveryKeepsFallbackEvidence() throws {
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        let launcher = StubLaunchTransport(resultPID: 800, onLaunch: {
            foreground.setCurrentPID(800)
        })
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                foreground.setCurrentPID(900)
                return ["w_800"]
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored == false)
        #expect(response.foregroundPIDAfter == 900)
        #expect(foreground.activatedPIDs.isEmpty)
    }

    @Test
    func approvalControlThenTargetRestoresOriginalForeground() throws {
        let controlPID: pid_t = 500
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        let launcher = StubLaunchTransport(resultPID: 800, onLaunch: {
            foreground.setCurrentPID(800)
        })
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow, onAuthorize: {
                foreground.setCurrentPID(controlPID)
            }),
            launcher: launcher,
            windowProvider: { _ in ["w_800"] },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate,
            controlPID: controlPID
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundFallbackUsed)
        #expect(response.foregroundRestored)
        #expect(response.foregroundPIDAfter == 100)
        #expect(foreground.activatedPIDs == [100])
    }

    @Test
    func approvalControlWithoutTargetForegroundRestoresOriginalAsynchronously() throws {
        let controlPID: pid_t = 500
        let foreground = LaunchForegroundHarness(
            currentPID: 100,
            activatablePIDs: [100],
            activationDelaySamples: 1
        )
        let launcher = StubLaunchTransport(resultPID: 800)
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow, onAuthorize: {
                foreground.setCurrentPID(controlPID)
            }),
            launcher: launcher,
            windowProvider: { _ in ["w_800"] },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate,
            controlPID: controlPID
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundFallbackUsed == false)
        #expect(response.foregroundRestored)
        #expect(response.foregroundPreserved)
        #expect(response.foregroundPIDAfter == 100)
        #expect(foreground.activatedPIDs == [100])
    }

    @Test
    func approvalControlThenThirdAppPreservesThirdApp() throws {
        let controlPID: pid_t = 500
        let foreground = LaunchForegroundHarness(currentPID: 100, activatablePIDs: [100])
        let launcher = StubLaunchTransport(resultPID: 800)
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow, onAuthorize: {
                foreground.setCurrentPID(controlPID)
            }),
            launcher: launcher,
            windowProvider: { _ in
                foreground.setCurrentPID(900)
                return ["w_800"]
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate,
            controlPID: controlPID
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundFallbackUsed == false)
        #expect(response.foregroundRestored == false)
        #expect(response.foregroundPIDAfter == 900)
        #expect(foreground.activatedPIDs.isEmpty)
    }

    @Test
    func completedLaunchWaitsForAsynchronousForegroundRestoration() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        let foreground = LaunchForegroundHarness(
            currentPID: 100,
            activatablePIDs: [100],
            activationDelaySamples: 1
        )
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                foreground.setCurrentPID(800)
                return ["w_800"]
            },
            foregroundPID: foreground.capturePID,
            activatePID: foreground.activate
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok)
        #expect(response.foregroundRestored)
        #expect(response.foregroundPIDAfter == 100)
        #expect(foreground.activatedPIDs == [100])
    }
}

private struct StubLaunchResolver: LaunchAppResolving {
    let identity: AppIdentity
    let existingPID: pid_t?

    func resolve(request _: LaunchAppRequest) throws -> LaunchAppCandidate {
        LaunchAppCandidate(
            url: URL(fileURLWithPath: "/Applications/Target.app"),
            identity: identity,
            existingPID: existingPID
        )
    }
}

private struct StubLaunchAuthorizer: LaunchAppAuthorizing {
    let decision: AppPolicyDecision
    var onAuthorize: () -> Void = {}

    func authorize(identity _: AppIdentity, pid _: pid_t?, sessionID _: String) -> AppPolicyDecision {
        onAuthorize()
        return decision
    }
}

private final class StubLaunchTransport: LaunchAppTransporting, @unchecked Sendable {
    let resultPID: pid_t
    let onLaunch: () -> Void
    private(set) var activationFlags: [Bool] = []
    var calls: Int {
        activationFlags.count
    }

    init(resultPID: pid_t, onLaunch: @escaping () -> Void = {}) {
        self.resultPID = resultPID
        self.onLaunch = onLaunch
    }

    func launch(url _: URL, activates: Bool) throws -> pid_t {
        activationFlags.append(activates)
        onLaunch()
        return resultPID
    }
}

private final class LaunchForegroundHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var currentPID: pid_t?
    private let activatablePIDs: Set<pid_t>
    private let activationDelaySamples: Int
    private var storedActivatedPIDs: [pid_t] = []
    private var queuedCapturePIDs: [pid_t?] = []
    private var pendingPID: pid_t?
    private var remainingDelaySamples = 0

    init(
        currentPID: pid_t?,
        activatablePIDs: Set<pid_t>,
        activationDelaySamples: Int = 0
    ) {
        self.currentPID = currentPID
        self.activatablePIDs = activatablePIDs
        self.activationDelaySamples = activationDelaySamples
    }

    var activatedPIDs: [pid_t] {
        lock.withLock { storedActivatedPIDs }
    }

    func capturePID() -> pid_t? {
        lock.withLock {
            if queuedCapturePIDs.isEmpty == false {
                currentPID = queuedCapturePIDs.removeFirst()
                return currentPID
            }
            if let pendingPID {
                if remainingDelaySamples == 0 {
                    currentPID = pendingPID
                    self.pendingPID = nil
                } else {
                    remainingDelaySamples -= 1
                }
            }
            return currentPID
        }
    }

    func setCurrentPID(_ pid: pid_t?) {
        lock.withLock {
            currentPID = pid
        }
    }

    func enqueueCapturePIDs(_ pids: [pid_t?]) {
        lock.withLock {
            queuedCapturePIDs.append(contentsOf: pids)
        }
    }

    func activate(_ pid: pid_t) -> Bool {
        lock.withLock {
            storedActivatedPIDs.append(pid)
            guard activatablePIDs.contains(pid) else {
                return false
            }
            pendingPID = pid
            remainingDelaySamples = activationDelaySamples
            return true
        }
    }
}

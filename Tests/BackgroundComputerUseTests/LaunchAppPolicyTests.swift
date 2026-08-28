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
    func existingProcessReturnsItsPIDWithoutRelaunch() throws {
        let launcher = StubLaunchTransport(resultPID: 999)
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: 321),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in [] },
            foregroundPID: { 100 }
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )
        #expect(response.ok)
        #expect(response.pid == 321)
        #expect(response.launchState == .alreadyRunning)
        #expect(launcher.calls == 0)
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
    func foregroundSafetyIsSampledAfterWindowDiscoverySettles() throws {
        let launcher = StubLaunchTransport(resultPID: 800)
        var foregroundPID: pid_t? = 100
        var reads = 0
        let service = LaunchAppRouteService(
            resolver: StubLaunchResolver(identity: identity, existingPID: nil),
            authorizer: StubLaunchAuthorizer(decision: .alwaysAllow),
            launcher: launcher,
            windowProvider: { _ in
                reads += 1
                if reads == 2 {
                    foregroundPID = 800
                    return ["w_800"]
                }
                return []
            },
            foregroundPID: { foregroundPID }
        )

        let response = try service.launchApp(
            request: LaunchAppRequest(bundleID: identity.bundleID, appPath: nil, sessionID: "session")
        )

        #expect(response.ok == false)
        #expect(response.foregroundPreserved == false)
        #expect(response.foregroundPIDAfter == 800)
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

    func authorize(identity _: AppIdentity, pid _: pid_t?, sessionID _: String) -> AppPolicyDecision {
        decision
    }
}

private final class StubLaunchTransport: LaunchAppTransporting, @unchecked Sendable {
    let resultPID: pid_t
    private(set) var activationFlags: [Bool] = []
    var calls: Int {
        activationFlags.count
    }

    init(resultPID: pid_t) {
        self.resultPID = resultPID
    }

    func launch(url _: URL, activates: Bool) throws -> pid_t {
        activationFlags.append(activates)
        return resultPID
    }
}

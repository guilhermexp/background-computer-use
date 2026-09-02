import BackgroundComputerUseControlShared
import Foundation

private final class ControlIntegrationState: @unchecked Sendable {
    let lock = NSLock()
    var allowsMutations: (@Sendable () -> Bool)?
    var allowsReads: (@Sendable () -> Bool)?
    var allowsArbitraryScripts: (@Sendable () -> Bool)?
    var activitySink: (@Sendable (String, String, String?, String?, String, String, String?) -> Void)?
}

public enum BackgroundComputerUseControlBridge {
    private static let state = ControlIntegrationState()

    public static func configure(
        store: AppPolicyStore,
        prompt: @escaping @Sendable (AppIdentity, pid_t?, String) -> AppPolicyDecision,
        allowsMutations: @escaping @Sendable () -> Bool = { true },
        allowsReads: @escaping @Sendable () -> Bool = { true },
        allowsArbitraryScripts: @escaping @Sendable () -> Bool = { false },
        publishActivity: @escaping @Sendable (String, String, String?, String?, String, String, String?) -> Void = { _, _, _, _, _, _, _ in }
    ) {
        ControlAuthorizationCenter.shared.configure(store: store, prompt: prompt)
        state.lock.lock()
        state.allowsMutations = allowsMutations
        state.allowsReads = allowsReads
        state.allowsArbitraryScripts = allowsArbitraryScripts
        state.activitySink = publishActivity
        state.lock.unlock()
    }

    public static func disconnect() {
        ControlAuthorizationCenter.shared.disconnect()
        state.lock.lock()
        state.allowsMutations = nil
        state.allowsReads = nil
        state.allowsArbitraryScripts = nil
        state.activitySink = nil
        state.lock.unlock()
    }

    static func mutationAllowed(required: Bool = false) -> Bool {
        state.lock.lock()
        let callback = state.allowsMutations
        state.lock.unlock()
        return callback?() ?? (required == false)
    }

    static func readAllowed(required: Bool = false) -> Bool {
        state.lock.lock()
        let callback = state.allowsReads
        state.lock.unlock()
        return callback?() ?? (required == false)
    }

    static func arbitraryScriptAllowed(required: Bool = false) -> Bool {
        state.lock.lock()
        let callback = state.allowsArbitraryScripts
        state.lock.unlock()
        return callback?() ?? (required == false)
    }

    static func authorizeWindow(
        windowID: String,
        sessionID: String
    ) -> WindowAuthorization? {
        guard ControlAuthorizationCenter.shared.isConnected else { return nil }
        let resolved: ResolvedWindowTarget
        do {
            resolved = try WindowTargetResolver().resolve(windowID: windowID)
        } catch {
            return .identityUnresolvable(reason: "window could not be resolved to a process (\(error))")
        }
        let identity: AppIdentity
        do {
            identity = try CodeSignatureIdentity().resolve(pid: resolved.app.processIdentifier)
        } catch {
            return .identityUnresolvable(reason: "code signature of pid \(resolved.app.processIdentifier) is unusable (\(error))")
        }
        return .decision(ControlAuthorizationCenter.shared.authorize(
            identity: identity,
            pid: resolved.app.processIdentifier,
            sessionID: sessionID
        ))
    }

    static func publishActivity(
        sessionID: String,
        action: String,
        appBundleID: String?,
        windowID: String?,
        verdict: String,
        summary: String,
        screenshotPath: String?
    ) {
        state.lock.lock()
        let sink = state.activitySink
        state.lock.unlock()
        sink?(sessionID, action, appBundleID, windowID, verdict, summary, screenshotPath)
    }
}

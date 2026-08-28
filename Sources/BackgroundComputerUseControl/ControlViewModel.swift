import BackgroundComputerUseControlShared
import Combine
import Foundation

public struct ApprovalRequest: Identifiable, Sendable {
    public let id: String
    public let identity: AppIdentity
    public let pid: pid_t?
    public let sessionID: String
    public let operation: String

    public init(
        id: String,
        identity: AppIdentity,
        pid: pid_t?,
        sessionID: String,
        operation: String
    ) {
        self.id = id
        self.identity = identity
        self.pid = pid
        self.sessionID = sessionID
        self.operation = operation
    }
}

public final class ApprovalQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [ApprovalRequest] = []
    private var decisions: [String: AppPolicyDecision] = [:]

    public init() {}

    public var active: ApprovalRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(requests.count - 1, 0)
    }

    public func enqueue(_ request: ApprovalRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    public func resolveActive(_ decision: AppPolicyDecision) {
        lock.lock()
        if requests.isEmpty == false {
            decisions[requests.removeFirst().id] = decision
        }
        lock.unlock()
    }

    public func decision(for requestID: String) -> AppPolicyDecision? {
        lock.lock()
        defer { lock.unlock() }
        return decisions[requestID]
    }
}

public enum ApprovalDecisionPolicy {
    public static func sanitize(
        _ decision: AppPolicyDecision?,
        timedOut: Bool
    ) -> AppPolicyDecision {
        guard timedOut == false,
              let decision,
              decision == .allowOnce || decision == .alwaysAllow || decision == .deny
        else {
            return .deny
        }
        return decision
    }
}

public struct ApprovalPresentationCopy: Sendable {
    public let title: String
    public let message: String
    public let accessibilityLabel: String
    public let allowOnceLabel: String
    public let alwaysAllowLabel: String
    public let denyLabel: String

    public static func make(for request: ApprovalRequest) -> ApprovalPresentationCopy {
        let scope = request.operation
        let signer = request.identity.teamID
        let identity = request.identity.bundleID
        return ApprovalPresentationCopy(
            title: "Permitir acesso ao app?",
            message: "\(identity)\nAssinante verificado: \(signer)\nEscopo: \(scope)",
            accessibilityLabel: "Aplicativo \(identity), assinante verificado \(signer), escopo \(scope)",
            allowOnceLabel: "Permitir uma vez",
            alwaysAllowLabel: "Sempre permitir",
            denyLabel: "Negar"
        )
    }
}

public struct AppPolicyRow: Identifiable, Sendable {
    public var id: AppIdentity {
        identity
    }

    public let identity: AppIdentity
    public let decision: AppPolicyDecision
}

@MainActor
public final class ControlViewModel: ObservableObject {
    @Published public private(set) var policies: [AppPolicyRow] = []
    @Published public var isPaused = false
    @Published public private(set) var isStopped = false
    @Published public private(set) var lockedUseOptIn: Bool
    @Published public private(set) var activityCardEnabled: Bool
    @Published public private(set) var permissionSnapshot: ControlPermissionSnapshot

    private let store: AppPolicyStore
    private let controls: SessionControls
    private let onLockedUsePreferenceChanged: (Bool) -> Void
    private let onActivityCardPreferenceChanged: (Bool) -> Void
    private let onQuit: () -> Void

    public init(
        store: AppPolicyStore,
        controls: SessionControls = SessionControls(),
        lockedUseOptIn: Bool = false,
        onLockedUsePreferenceChanged: @escaping (Bool) -> Void = { _ in },
        activityCardEnabled: Bool = true,
        onActivityCardPreferenceChanged: @escaping (Bool) -> Void = { _ in },
        onQuit: @escaping () -> Void = {}
    ) {
        self.store = store
        self.controls = controls
        self.lockedUseOptIn = lockedUseOptIn
        self.onLockedUsePreferenceChanged = onLockedUsePreferenceChanged
        self.activityCardEnabled = activityCardEnabled
        self.onActivityCardPreferenceChanged = onActivityCardPreferenceChanged
        self.onQuit = onQuit
        permissionSnapshot = .current()
        isPaused = controls.state == .paused
        isStopped = controls.state == .stopped
        refreshPolicies()
    }

    public func refreshPolicies() {
        policies = store.persistedPolicies().map(AppPolicyRow.init)
    }

    public func revoke(_ identity: AppIdentity) {
        try? store.revoke(identity: identity)
        refreshPolicies()
    }

    public func togglePause() {
        guard isStopped == false else { return }
        if isPaused {
            controls.resume()
        } else {
            controls.pause()
        }
        isPaused = controls.state == .paused
    }

    public func stop() {
        controls.stop()
        isStopped = true
        isPaused = true
    }

    public func quit() {
        stop()
        onQuit()
    }

    public func setLockedUseOptIn(_ enabled: Bool) {
        lockedUseOptIn = enabled
        onLockedUsePreferenceChanged(enabled)
    }

    public func setActivityCardEnabled(_ enabled: Bool) {
        activityCardEnabled = enabled
        onActivityCardPreferenceChanged(enabled)
    }

    public func refreshPermissions() {
        permissionSnapshot = .current()
    }
}

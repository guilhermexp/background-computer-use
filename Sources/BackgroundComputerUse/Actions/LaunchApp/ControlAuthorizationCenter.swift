import BackgroundComputerUseControlShared
import Foundation

final class ControlAuthorizationCenter: LaunchAppAuthorizing, @unchecked Sendable {
    typealias Prompt = @Sendable (AppIdentity, pid_t?, String) -> AppPolicyDecision

    static let shared = ControlAuthorizationCenter()

    private let lock = NSLock()
    private var store: AppPolicyStore?
    private var prompt: Prompt?

    private init() {}

    func configure(store: AppPolicyStore, prompt: @escaping Prompt) {
        lock.lock()
        self.store = store
        self.prompt = prompt
        lock.unlock()
    }

    func disconnect() {
        lock.lock()
        store = nil
        prompt = nil
        lock.unlock()
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return store != nil && prompt != nil
    }

    func authorize(identity: AppIdentity, pid: pid_t?, sessionID: String) -> AppPolicyDecision {
        lock.lock()
        let store = store
        let prompt = prompt
        lock.unlock()

        guard let store else { return .deny }
        let current = store.evaluate(identity: identity, sessionID: sessionID)
        guard current == .ask else { return current }
        guard let prompt else { return .deny }
        let requested = prompt(identity, pid, sessionID)
        guard requested == .allowOnce || requested == .alwaysAllow || requested == .deny else {
            return .deny
        }
        do {
            try store.set(requested, for: identity, sessionID: sessionID)
            return store.evaluate(identity: identity, sessionID: sessionID)
        } catch {
            return .deny
        }
    }
}

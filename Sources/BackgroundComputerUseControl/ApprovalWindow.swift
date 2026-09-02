import AppKit
import BackgroundComputerUseControlShared
import Foundation

/// Hand-off between the request thread that needs an approval decision and the main
/// thread that owns the modal alert.
///
/// The request thread must never wait without a bound: `NSAlert.runModal()` runs a
/// nested run loop that does not drain the main dispatch queue, so a second approval
/// arriving while one alert is already up would otherwise block its request forever
/// (measured 2026-09-02: a request thread parked in `DispatchQueue.main.sync` for the
/// entire 5m56s life of the process). When the bound elapses the waiter gives up and
/// the presentation is abandoned, so no dialog is shown that nobody is waiting for.
final class ApprovalHandoff: @unchecked Sendable {
    private enum State {
        case pending
        case presenting
        case abandoned
    }

    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var state: State = .pending
    private var decision: AppPolicyDecision?

    /// Returns false when the waiter already gave up, so the caller must not present.
    func beginPresentation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .pending = state else { return false }
        state = .presenting
        return true
    }

    func finish(_ decision: AppPolicyDecision) {
        lock.lock()
        if case .abandoned = state {
            lock.unlock()
            return
        }
        self.decision = decision
        lock.unlock()
        ready.signal()
    }

    /// Waits for a decision, failing closed on `deny` when the bound elapses.
    func wait(timeout: TimeInterval) -> AppPolicyDecision {
        guard ready.wait(timeout: .now() + timeout) == .success else {
            lock.lock()
            state = .abandoned
            lock.unlock()
            return .deny
        }
        lock.lock()
        defer { lock.unlock() }
        return decision ?? .deny
    }
}

public final class ApprovalWindowPresenter: @unchecked Sendable {
    /// How a presentation reaches the main thread. Injectable so a starved main queue
    /// is reproducible without a real modal loop.
    public typealias MainDispatch = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let timeout: TimeInterval
    private let waitGrace: TimeInterval
    private let dispatchToMain: MainDispatch

    public init(
        timeout: TimeInterval = 30,
        waitGrace: TimeInterval = 5,
        dispatchToMain: @escaping MainDispatch = { work in DispatchQueue.main.async(execute: work) }
    ) {
        self.timeout = timeout
        self.waitGrace = waitGrace
        self.dispatchToMain = dispatchToMain
    }

    /// Bound the request thread waits for a decision: the modal's own timeout plus
    /// enough slack for AppKit to tear the alert down.
    var waitBound: TimeInterval {
        timeout + waitGrace
    }

    public func present(_ request: ApprovalRequest) -> AppPolicyDecision {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { presentOnMain(request) }
        }
        let handoff = ApprovalHandoff()
        dispatchToMain { [self] in
            guard handoff.beginPresentation() else { return }
            let decision = MainActor.assumeIsolated { presentOnMain(request) }
            handoff.finish(decision)
        }
        return handoff.wait(timeout: waitBound)
    }

    @MainActor
    private func presentOnMain(_ request: ApprovalRequest) -> AppPolicyDecision {
        let foregroundBeforeApproval = NSWorkspace.shared.frontmostApplication
        let copy = ApprovalPresentationCopy.make(for: request)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.addButton(withTitle: copy.allowOnceLabel)
            .identifier = NSUserInterfaceItemIdentifier("bcu.approval.allow-once")
        alert.addButton(withTitle: copy.alwaysAllowLabel)
            .identifier = NSUserInterfaceItemIdentifier("bcu.approval.always-allow")
        alert.addButton(withTitle: copy.denyLabel)
            .identifier = NSUserInterfaceItemIdentifier("bcu.approval.deny")
        alert.window.identifier = NSUserInterfaceItemIdentifier("bcu.approval.window")
        alert.window.setAccessibilityLabel(copy.accessibilityLabel)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.identity.bundleID) {
            alert.icon = NSWorkspace.shared.icon(forFile: appURL.path)
        }

        let expiry = ApprovalModalExpiry()
        // The dismissal must be driven by a run-loop timer registered in the modal mode.
        // A main-queue block (asyncAfter/DispatchWorkItem) is never drained while
        // `runModal()` owns the run loop, so scheduling the timeout there leaves the
        // alert up indefinitely.
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated {
                expiry.expired = true
                guard NSApp.modalWindow == alert.window else { return }
                NSApp.abortModal()
                alert.window.orderOut(nil)
            }
        }
        for mode in [RunLoop.Mode.modalPanel, .common] {
            RunLoop.main.add(timer, forMode: mode)
        }
        let response = alert.runModal()
        timer.invalidate()

        let decision: AppPolicyDecision? = switch response {
        case .alertFirstButtonReturn:
            .allowOnce
        case .alertSecondButtonReturn:
            .alwaysAllow
        case .alertThirdButtonReturn:
            .deny
        default:
            nil
        }
        if let foregroundBeforeApproval,
           foregroundBeforeApproval.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            _ = foregroundBeforeApproval.activate(options: [])
        }
        return ApprovalDecisionPolicy.sanitize(decision, timedOut: expiry.expired)
    }
}

@MainActor
private final class ApprovalModalExpiry {
    var expired = false
}

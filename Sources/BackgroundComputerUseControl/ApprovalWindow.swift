import AppKit
import BackgroundComputerUseControlShared
import Foundation

/// Hand-off between the request thread that needs an approval decision and the main
/// thread that owns the approval panel.
///
/// The request thread must never wait without a bound. Measured 2026-09-02 with the
/// previous app-modal `NSAlert.runModal()`: a second approval arriving while one alert
/// was up parked its request thread in `DispatchQueue.main.sync` for the whole 5m56s
/// life of the runtime, and the alert's own main-queue timeout never drained either.
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

/// Floating approval surface that never becomes key and never activates the runtime.
///
/// A background automation tool must not take over the screen to ask a question: an
/// app-modal alert steals focus from whatever the user is doing, interrupts typing, and
/// runs a nested run loop that starves the main queue. This panel is ordered in front
/// without activation, so the user keeps working and answers when they choose to.
final class ApprovalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ApprovalPanelController {
    private var panel: ApprovalPanel?
    private var timer: Timer?
    private var respond: ((AppPolicyDecision) -> Void)?

    func present(
        _ request: ApprovalRequest,
        timeout: TimeInterval,
        respond: @escaping (AppPolicyDecision) -> Void
    ) {
        let copy = ApprovalPresentationCopy.make(for: request)
        self.respond = respond

        let panel = ApprovalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("bcu.approval.window")
        panel.title = copy.title
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.setAccessibilityLabel(copy.accessibilityLabel)

        let title = NSTextField(labelWithString: copy.title)
        title.font = .preferredFont(forTextStyle: .headline)
        let message = NSTextField(wrappingLabelWithString: copy.message)
        message.font = .preferredFont(forTextStyle: .callout)

        let buttons = [
            (copy.allowOnceLabel, "bcu.approval.allow-once", AppPolicyDecision.allowOnce),
            (copy.alwaysAllowLabel, "bcu.approval.always-allow", AppPolicyDecision.alwaysAllow),
            (copy.denyLabel, "bcu.approval.deny", AppPolicyDecision.deny),
        ].map { label, identifier, decision -> NSButton in
            let button = NSButton(title: label, target: self, action: #selector(buttonPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
            button.setAccessibilityLabel(label)
            button.tag = Self.tag(for: decision)
            return button
        }

        let stack = NSStackView(views: [title, message] + buttons)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        panel.contentView = stack

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(x: frame.maxX - 380, y: frame.maxY - 220)
            )
        }
        self.panel = panel
        // Ordering front *regardless* shows the request without activating this app, so
        // the user's frontmost application and keyboard focus are untouched.
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resolve(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc
    private func buttonPressed(_ sender: NSButton) {
        resolve(Self.decision(for: sender.tag))
    }

    private func resolve(_ decision: AppPolicyDecision?) {
        guard let respond else { return }
        self.respond = nil
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        respond(ApprovalDecisionPolicy.sanitize(decision, timedOut: decision == nil))
    }

    private static func tag(for decision: AppPolicyDecision) -> Int {
        switch decision {
        case .allowOnce: 1
        case .alwaysAllow: 2
        case .deny: 3
        case .ask: 0
        }
    }

    private static func decision(for tag: Int) -> AppPolicyDecision? {
        switch tag {
        case 1: .allowOnce
        case 2: .alwaysAllow
        case 3: .deny
        default: nil
        }
    }
}

public final class ApprovalWindowPresenter: @unchecked Sendable {
    /// How a presentation reaches the main thread. Injectable so a starved main queue
    /// is reproducible without any UI.
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

    /// Bound the request thread waits for a decision: the panel's own timeout plus
    /// enough slack for AppKit to tear it down.
    var waitBound: TimeInterval {
        timeout + waitGrace
    }

    public func present(_ request: ApprovalRequest) -> AppPolicyDecision {
        let handoff = ApprovalHandoff()
        let show: @Sendable () -> Void = { [timeout] in
            MainActor.assumeIsolated {
                guard handoff.beginPresentation() else { return }
                let controller = ApprovalPanelController()
                ApprovalPanelRegistry.retain(controller)
                controller.present(request, timeout: timeout) { decision in
                    ApprovalPanelRegistry.release(controller)
                    handoff.finish(decision)
                }
            }
        }
        if Thread.isMainThread {
            // The panel is event-driven: the main thread has to stay free to deliver the
            // button click, so it cannot also block waiting for the answer. Report the
            // misuse instead of silently denying.
            FileHandle.standardError.write(Data(
                "BackgroundComputerUse: approval was requested on the main thread; denying because the approval panel cannot be answered while the main thread waits.\n".utf8
            ))
            return .deny
        }
        dispatchToMain(show)
        return handoff.wait(timeout: waitBound)
    }
}

/// Keeps a presenting controller alive while its panel is on screen.
@MainActor
private enum ApprovalPanelRegistry {
    private static var live: [ApprovalPanelController] = []

    static func retain(_ controller: ApprovalPanelController) {
        live.append(controller)
    }

    static func release(_ controller: ApprovalPanelController) {
        live.removeAll { $0 === controller }
    }
}

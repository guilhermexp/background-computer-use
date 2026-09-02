import AppKit
import BackgroundComputerUseControlShared
import Foundation

public final class ApprovalWindowPresenter: @unchecked Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    public func present(_ request: ApprovalRequest) -> AppPolicyDecision {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { presentOnMain(request) }
        }
        return DispatchQueue.main.sync { @MainActor in presentOnMain(request) }
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

        var timedOut = false
        let timeoutWork = DispatchWorkItem {
            timedOut = true
            if NSApp.modalWindow == alert.window {
                NSApp.abortModal()
                alert.window.orderOut(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        let response = alert.runModal()
        timeoutWork.cancel()
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
        return ApprovalDecisionPolicy.sanitize(decision, timedOut: timedOut)
    }
}

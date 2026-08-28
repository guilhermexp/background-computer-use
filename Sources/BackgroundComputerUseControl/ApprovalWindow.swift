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
        alert.addButton(withTitle: copy.alwaysAllowLabel)
        alert.addButton(withTitle: copy.denyLabel)
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
        let sanitized = ApprovalDecisionPolicy.sanitize(decision, timedOut: timedOut)
        if let foregroundBeforeApproval,
           foregroundBeforeApproval.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            _ = foregroundBeforeApproval.activate(options: [])
        }
        return sanitized
    }
}

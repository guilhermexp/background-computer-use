import ApplicationServices
import Foundation

package enum RendererAccessibilityWorkerMain {
    package static func pid(from arguments: [String]) -> pid_t? {
        guard let raw = arguments.first,
              let value = Int32(raw), value > 0
        else {
            return nil
        }
        return value
    }

    package static func run(arguments: [String]) -> Never {
        guard let pid = pid(from: arguments) else { Foundation.exit(64) }
        let application = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        if AXObserverCreate(pid, { _, _, _, _ in }, &observer) == .success,
           let observer
        {
            _ = AXObserverAddNotification(
                observer,
                application,
                kAXFocusedUIElementChangedNotification as CFString,
                nil
            )
            CFRunLoopAddSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        _ = AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        sleepRunLoop(3.0)
        _ = AXActionRuntimeSupport.copyAttributeValue(
            application,
            attribute: kAXWindowsAttribute as CFString
        )
        _ = AXActionRuntimeSupport.childElements(application)
        Foundation.exit(0)
    }
}

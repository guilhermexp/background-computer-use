import ApplicationServices
import Foundation

enum RendererAccessibilityBootstrap {
    static let attributeNames = [
        "AXManualAccessibility",
        "AXEnhancedUserInterface",
    ]

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var preparedProcessKeys: Set<String> = []
        var observersByProcessKey: [String: AXObserver] = [:]
    }

    private static let state = State()

    static func shouldTryEnhanced(after manualStatus: AXError) -> Bool {
        manualStatus == .attributeUnsupported || manualStatus == .notImplemented
    }

    static func isLikelyRenderer(
        bundleID: String,
        frameworkNames: [String]
    ) -> Bool {
        let bundle = bundleID.lowercased()
        if bundle.contains("chrome") || bundle.contains("chromium") || bundle.contains("electron") {
            return true
        }
        return frameworkNames.contains { name in
            let framework = name.lowercased()
            return framework.contains("electron framework")
                || framework.contains("chrome framework")
                || framework.contains("chromium framework")
        }
    }

    typealias WorkerEnqueue = @Sendable (@escaping @Sendable () -> Void) -> Void

    static func dispatchWorker(
        _ work: @escaping @Sendable () -> Void,
        enqueue: WorkerEnqueue = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    ) {
        enqueue(work)
    }

    static func prepare(
        application: AXUIElement,
        pid: pid_t,
        launchDate: Date?,
        bundleID: String,
        bundleURL: URL?
    ) {
        let processKey = "\(pid):\(launchDate?.timeIntervalSince1970 ?? 0)"
        state.lock.lock()
        let firstAttempt = state.preparedProcessKeys.insert(processKey).inserted
        state.lock.unlock()
        guard firstAttempt else { return }

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
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            state.lock.lock()
            state.observersByProcessKey[processKey] = observer
            state.lock.unlock()
        }

        let manual = AXActionRuntimeSupport.setBoolAttributeResult(
            application,
            attribute: attributeNames[0] as CFString,
            value: true
        )
        var enabled = manual == .success
        if shouldTryEnhanced(after: manual) {
            let enhanced = AXActionRuntimeSupport.setBoolAttributeResult(
                application,
                attribute: attributeNames[1] as CFString,
                value: true
            )
            enabled = enhanced == .success
                || AXActionRuntimeSupport.boolAttribute(
                    application,
                    attribute: attributeNames[1] as CFString
                ) == true
        }
        let frameworkNames = bundleURL.flatMap { url in
            try? FileManager.default.contentsOfDirectory(
                atPath: url.appendingPathComponent("Contents/Frameworks", isDirectory: true).path
            )
        } ?? []
        let likelyRenderer = isLikelyRenderer(bundleID: bundleID, frameworkNames: frameworkNames)
        if likelyRenderer {
            runBootstrapWorker(pid: pid)
            _ = ConditionedActionWait.poll(
                intervalMs: 100,
                deadlineMs: 5000,
                sample: { contentRendererTreeReady(application: application) },
                isSatisfied: { $0 }
            )
        } else if enabled {
            sleepRunLoop(0.5)
        }
    }

    private static func runBootstrapWorker(pid: pid_t) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app",
              let executableURL = Bundle.main.executableURL
        else {
            return
        }
        dispatchWorker {
            let result = try? BoundedProcessRunner().run(
                BoundedProcessInvocation(
                    executableURL: executableURL,
                    arguments: ["--ax-bootstrap-worker", String(pid)],
                    stdin: Data(),
                    timeoutMs: 5000
                )
            )
            guard result?.status == 0, result?.timedOut == false else { return }
        }
    }

    private static func contentRendererTreeReady(application: AXUIElement) -> Bool {
        _ = AXActionRuntimeSupport.copyAttributeValue(
            application,
            attribute: kAXWindowsAttribute as CFString
        )
        var queue = AXActionRuntimeSupport.childElements(application).map { ($0, 0, false) }
        var visited = 0
        while queue.isEmpty == false, visited < 500 {
            let (element, depth, insideContentWebArea) = queue.removeFirst()
            visited += 1
            let role = AXActionRuntimeSupport.stringAttribute(
                element,
                attribute: kAXRoleAttribute as CFString
            )
            let url = role == "AXWebArea"
                ? AXActionRuntimeSupport.stringAttribute(element, attribute: "AXURL" as CFString)
                : nil
            let startsContentWebArea = role == "AXWebArea"
                && (url?.hasPrefix("file://") == true
                    || url?.hasPrefix("http://") == true
                    || url?.hasPrefix("https://") == true)
            let isInsideContent = insideContentWebArea || startsContentWebArea
            let domIdentifier = AXActionRuntimeSupport.stringAttribute(
                element,
                attribute: "AXDOMIdentifier" as CFString
            )
            if isInsideContent,
               let domIdentifier,
               domIdentifier.isEmpty == false,
               domIdentifier.hasPrefix("view_") == false
            {
                return true
            }
            if depth < 10 {
                queue.append(contentsOf: AXActionRuntimeSupport.childElements(element).map {
                    ($0, depth + 1, isInsideContent)
                })
            }
        }
        return false
    }
}

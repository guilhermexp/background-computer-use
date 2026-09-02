import Foundation

enum RuntimeExecutionScope {
    case sharedRead
    case windowRead(String)
    case windowWrite(String)
}

enum RuntimeExecutionQueue {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var windowQueues: [String: DispatchQueue] = [:]
    }

    private static let state = State()
    private static let sharedQueue = DispatchQueue(
        label: "BackgroundComputerUse.RuntimeExecutionQueue.Shared",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Deep Accessibility trees (Electron/Chromium content nests 60+ levels) are projected
    /// recursively. `DispatchQueue.sync` runs the block inline on the caller, which for HTTP
    /// requests is a Network.framework worker thread with a 512 KB stack — observed SIGBUS
    /// "Thread stack size exceeded" at ~70 frames of `projectCanonicalNode`. Every scoped
    /// unit of work therefore runs on a dedicated thread with a stack sized for that recursion.
    static let workerStackSize = 64 << 20

    static func sync<T>(
        scope: RuntimeExecutionScope,
        _ work: () throws -> T
    ) rethrows -> T {
        try sync(scope: scope, work, rethrow: { throw $0 })
    }

    private static func sync<T>(
        scope: RuntimeExecutionScope,
        _ work: () throws -> T,
        rethrow: (Error) throws -> Never
    ) rethrows -> T {
        let outcome: Result<T, Error>
        switch scope {
        case .sharedRead:
            outcome = sharedQueue.sync { onLargeStack(work) }
        case .windowRead(let windowID):
            outcome = queue(for: windowID).sync { onLargeStack(work) }
        case .windowWrite(let windowID):
            outcome = queue(for: windowID).sync(flags: .barrier) { onLargeStack(work) }
        }
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            try rethrow(error)
        }
    }

    private static func onLargeStack<T>(_ work: () throws -> T) -> Result<T, Error> {
        var outcome: Result<T, Error>?
        withoutActuallyEscaping(work) { escapableWork in
            // Type-erased so the @convention(c) thread entry needs no generic context.
            // `body` lives only inside this block; the thread is joined before it goes away,
            // so `escapableWork` never outlives the non-escaping guarantee.
            var body: () -> Void = { outcome = Result { try escapableWork() } }
            withUnsafeMutablePointer(to: &body) { bodyPointer in
                var attributes = pthread_attr_t()
                pthread_attr_init(&attributes)
                pthread_attr_setstacksize(&attributes, workerStackSize)
                var thread: pthread_t?
                let created = pthread_create(&thread, &attributes, { raw in
                    pthread_setname_np("BackgroundComputerUse.RuntimeExecutionQueue.Worker")
                    raw.assumingMemoryBound(to: (() -> Void).self).pointee()
                    return nil
                }, UnsafeMutableRawPointer(bodyPointer))
                pthread_attr_destroy(&attributes)
                precondition(created == 0, "pthread_create failed: \(created)")
                pthread_join(thread!, nil)
            }
        }
        return outcome!
    }

    private static func queue(for windowID: String) -> DispatchQueue {
        state.lock.lock()
        defer { state.lock.unlock() }

        if let existing = state.windowQueues[windowID] {
            return existing
        }

        let queue = DispatchQueue(
            label: "BackgroundComputerUse.RuntimeExecutionQueue.Window.\(windowID)",
            qos: .userInitiated,
            attributes: .concurrent
        )
        state.windowQueues[windowID] = queue
        return queue
    }
}

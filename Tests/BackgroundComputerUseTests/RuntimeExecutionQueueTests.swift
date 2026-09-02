import Foundation
import Testing
@testable import BackgroundComputerUse

struct RuntimeExecutionQueueTests {
    @Test
    func workRunsOnDedicatedLargeStackThreadForEveryScope() {
        for scope in [RuntimeExecutionScope.sharedRead, .windowRead("w_a"), .windowWrite("w_a")] {
            let observed = RuntimeExecutionQueue.sync(scope: scope) { pthread_get_stacksize_np(pthread_self()) }
            #expect(observed >= RuntimeExecutionQueue.workerStackSize)
        }
    }

    @Test
    func deepRecursionSurvivesWhenEnteredFromDispatchWorkerThread() {
        // 20_000 frames × 1 KiB touched per frame ≈ 20 MiB: overflows a 512 KiB dispatch
        // worker stack and the 8 MiB main stack, fits the runtime worker stack.
        let finished = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var depthReached = 0
        DispatchQueue.global().async {
            depthReached = RuntimeExecutionQueue.sync(scope: .windowRead("w_deep")) {
                recurse(remaining: 20_000)
            }
            finished.signal()
        }
        finished.wait()
        #expect(depthReached == 20_000)
    }

    @Test
    func errorsPropagateFromTheWorkerThread() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try RuntimeExecutionQueue.sync(scope: .sharedRead) { throw Boom() }
        }
    }
}

@inline(never)
private func recurse(remaining: Int) -> Int {
    guard remaining > 0 else { return 0 }
    return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 1024) { buffer in
        buffer.initialize(repeating: UInt8(truncatingIfNeeded: remaining))
        return Int(buffer[remaining % 1024] & 0) + 1 + recurse(remaining: remaining - 1)
    }
}

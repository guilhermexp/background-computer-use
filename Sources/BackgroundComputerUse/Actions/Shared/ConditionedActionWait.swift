import Foundation

enum ExactTextSettlePolicy {
    static func isSatisfied(expected: String?, observed: String?) -> Bool {
        guard let expected, let observed else { return false }
        return observed == expected
    }
}

struct ConditionedActionWaitResult<Sample> {
    let sample: Sample
    let satisfied: Bool
    let pollCount: Int
    let elapsedMs: Int
}

enum ConditionedActionWait {
    static func poll<Sample>(
        intervalMs: Int,
        deadlineMs: Int,
        nowMs: () -> Int = monotonicMilliseconds,
        sleepMs: (Int) -> Void = { sleepRunLoop(Double($0) / 1000) },
        sample: () -> Sample,
        isSatisfied: (Sample) -> Bool
    ) -> ConditionedActionWaitResult<Sample> {
        precondition(intervalMs > 0)
        precondition(deadlineMs >= 0)
        let started = nowMs()
        var pollCount = 0
        while true {
            let current = sample()
            pollCount += 1
            let elapsed = max(0, nowMs() - started)
            if isSatisfied(current) {
                return ConditionedActionWaitResult(
                    sample: current,
                    satisfied: true,
                    pollCount: pollCount,
                    elapsedMs: elapsed
                )
            }
            if elapsed >= deadlineMs {
                return ConditionedActionWaitResult(
                    sample: current,
                    satisfied: false,
                    pollCount: pollCount,
                    elapsedMs: elapsed
                )
            }
            sleepMs(min(intervalMs, deadlineMs - elapsed))
        }
    }

    private static func monotonicMilliseconds() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

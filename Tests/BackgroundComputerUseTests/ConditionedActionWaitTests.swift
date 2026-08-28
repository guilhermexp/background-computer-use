@testable import BackgroundComputerUse
import Testing

struct ConditionedActionWaitTests {
    @Test
    func immediateEvidenceReturnsWithoutSleeping() {
        var now = 0
        var sleeps: [Int] = []

        let result = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: 350,
            nowMs: { now },
            sleepMs: {
                sleeps.append($0)
                now += $0
            },
            sample: { "done" },
            isSatisfied: { $0 == "done" }
        )

        #expect(result.satisfied)
        #expect(result.pollCount == 1)
        #expect(result.elapsedMs == 0)
        #expect(sleeps.isEmpty)
    }

    @Test
    func pollingStopsOnFirstSatisfiedSample() {
        var now = 0
        var samples = ["pending", "pending", "done", "late"]

        let result = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: 350,
            nowMs: { now },
            sleepMs: { now += $0 },
            sample: { samples.removeFirst() },
            isSatisfied: { $0 == "done" }
        )

        #expect(result.satisfied)
        #expect(result.sample == "done")
        #expect(result.pollCount == 3)
        #expect(result.elapsedMs == 50)
        #expect(samples == ["late"])
    }

    @Test
    func timeoutUsesBoundedFinalSleepAndNeverBusyLoops() {
        var now = 0
        var sleeps: [Int] = []

        let result = ConditionedActionWait.poll(
            intervalMs: 25,
            deadlineMs: 70,
            nowMs: { now },
            sleepMs: {
                sleeps.append($0)
                now += $0
            },
            sample: { false },
            isSatisfied: { $0 }
        )

        #expect(result.satisfied == false)
        #expect(result.elapsedMs == 70)
        #expect(result.pollCount == 4)
        #expect(sleeps == [25, 25, 20])
    }

    @Test
    func exactTextSettleAcceptsOnlyTheCompleteExpectedValue() {
        #expect(ExactTextSettlePolicy.isSatisfied(expected: "hello", observed: "hello"))
        #expect(ExactTextSettlePolicy.isSatisfied(expected: "hello", observed: "hel") == false)
        #expect(ExactTextSettlePolicy.isSatisfied(expected: "hello", observed: nil) == false)
        #expect(ExactTextSettlePolicy.isSatisfied(expected: nil, observed: nil) == false)
    }
}

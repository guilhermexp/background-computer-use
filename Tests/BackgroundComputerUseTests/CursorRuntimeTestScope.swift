import Foundation
@testable import BackgroundComputerUse

/// `CursorRuntime` is process-global singleton state driven by a display link.
/// Swift Testing runs suites in parallel, so without a gate one suite's sessions
/// (and its main-thread traffic) leak into another suite's assertions — that is
/// what made the cursor suites fail intermittently only in full runs.
///
/// Declare it as a stored property of a cursor suite:
///
///     @Suite(.serialized)
///     struct MyCursorTests {
///         private let runtime = CursorRuntimeTestScope()
///     }
///
/// Swift Testing builds one suite value per test, so the scope acquires the gate
/// and clears the runtime before the test body and releases it when the test's
/// suite value is destroyed.
final class CursorRuntimeTestScope {
    private static let gate = DispatchSemaphore(value: 1)
    /// Bounded so a leaked scope degrades into interference, never a hung run.
    private static let acquireTimeout: TimeInterval = 120

    init() {
        _ = Self.gate.wait(timeout: .now() + Self.acquireTimeout)
        CursorRuntime.resetForTesting()
    }

    deinit {
        CursorRuntime.resetForTesting()
        Self.gate.signal()
    }
}

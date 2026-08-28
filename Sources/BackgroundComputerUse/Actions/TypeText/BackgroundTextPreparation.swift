import Foundation

struct BackgroundTextPreparation: Sendable {
    typealias Prepare = @Sendable (pid_t, Int) -> NativeWindowServerPreparationResult

    static let live = BackgroundTextPreparation(
        prepare: NativeWindowServerPreparation.targetOnlyFocusAndKeyWindow
    )

    private let prepareOperation: Prepare

    init(prepare: @escaping Prepare) {
        prepareOperation = prepare
    }

    func prepareUnicodeFallback(pid: pid_t, windowNumber: Int) -> NativeWindowServerPreparationResult {
        prepareOperation(pid, windowNumber)
    }

    static func foregroundAllowsTextDispatch(
        original: ForegroundApplicationSnapshot?,
        current: ForegroundApplicationSnapshot?,
        targetPID: pid_t
    ) -> Bool {
        if current?.pid == targetPID {
            return true
        }
        guard let original, let current else {
            return false
        }
        return current == original
    }
}

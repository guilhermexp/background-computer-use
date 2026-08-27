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

    func prepare(pid: pid_t, windowNumber: Int) -> NativeWindowServerPreparationResult {
        prepareOperation(pid, windowNumber)
    }
}

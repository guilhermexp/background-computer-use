import Foundation

enum ClickHitTestRetry {
    static func firstAvailable<Value>(
        maximumAttempts: Int,
        sleep: () -> Void,
        action: () -> Value?
    ) -> Value? {
        guard maximumAttempts > 0 else { return nil }
        for attempt in 0 ..< maximumAttempts {
            if let value = action() {
                return value
            }
            if attempt + 1 < maximumAttempts {
                sleep()
            }
        }
        return nil
    }
}

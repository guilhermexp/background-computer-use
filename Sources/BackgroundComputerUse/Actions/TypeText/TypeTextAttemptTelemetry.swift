import Foundation

struct TypeTextAttemptTelemetry: Equatable, Sendable {
    let dispatchSucceeded: Bool?
    let strategiesAttempted: [AdaptiveTextStrategy]

    var retrySafe: Bool {
        dispatchSucceeded != true && strategiesAttempted.isEmpty
    }
}

import Foundation

enum AdaptivePasteStrategy: String, Codable, Equatable, Sendable {
    case axTextOperation = "ax_text_operation"
    case temporaryClipboardCommandV = "temporary_clipboard_command_v"
}

struct AdaptivePasteDispatchResult: Equatable, Sendable {
    let transportSucceeded: Bool
    let strategiesAttempted: [AdaptivePasteStrategy]
    let observedValue: String?
}

enum AdaptivePasteDispatcher {
    static func dispatch(
        baseline: String?,
        expected: String?,
        targetBoundEligible: Bool,
        performTargetBoundOperation: () -> Bool,
        readValue: () -> String?,
        performClipboardPaste: () -> Bool
    ) -> AdaptivePasteDispatchResult {
        guard targetBoundEligible else {
            return AdaptivePasteDispatchResult(
                transportSucceeded: performClipboardPaste(),
                strategiesAttempted: [.temporaryClipboardCommandV],
                observedValue: nil
            )
        }

        guard performTargetBoundOperation() else {
            return AdaptivePasteDispatchResult(
                transportSucceeded: performClipboardPaste(),
                strategiesAttempted: [.axTextOperation, .temporaryClipboardCommandV],
                observedValue: nil
            )
        }

        let observed = readValue()
        if observed == expected {
            return AdaptivePasteDispatchResult(
                transportSucceeded: true,
                strategiesAttempted: [.axTextOperation],
                observedValue: observed
            )
        }
        guard observed == baseline else {
            return AdaptivePasteDispatchResult(
                transportSucceeded: false,
                strategiesAttempted: [.axTextOperation],
                observedValue: observed
            )
        }
        return AdaptivePasteDispatchResult(
            transportSucceeded: performClipboardPaste(),
            strategiesAttempted: [.axTextOperation, .temporaryClipboardCommandV],
            observedValue: observed
        )
    }
}

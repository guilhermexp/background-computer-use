import AppKit
import Foundation

struct PasteTransactionResult: Equatable, Sendable {
    let payloadWritten: Bool
    let dispatchSucceeded: Bool
    let restoreSucceeded: Bool
}

enum PasteTransaction {
    static func perform(
        content: String,
        format: PasteFormatDTO,
        pasteboard: NSPasteboard,
        dispatch: () -> Bool
    ) -> PasteTransactionResult {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let payloadWritten = PasteboardPayload.write(content, format: format, to: pasteboard)
        let dispatchSucceeded = payloadWritten ? dispatch() : false
        let restoreSucceeded = snapshot.restore(to: pasteboard)
        return PasteTransactionResult(
            payloadWritten: payloadWritten,
            dispatchSucceeded: dispatchSucceeded,
            restoreSucceeded: restoreSucceeded
        )
    }
}

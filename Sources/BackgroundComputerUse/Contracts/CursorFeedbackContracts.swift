import Foundation

struct CursorFeedbackResponse: Encodable, Sendable {
    let contractVersion: String
    let ok: Bool
    let operation: CursorFeedbackOperation
    let state: CursorFeedbackVisualState
    let message: String?
    let cursor: CursorResponseDTO
    let attachment: String
    let targetPointAppKit: PointDTO?
    let clamped: Bool
    let plannedDurationMs: Double?
    let warnings: [String]
}

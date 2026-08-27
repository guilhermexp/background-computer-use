import Foundation

package struct OCRWorkerRequest: Codable, Equatable, Sendable {
    package let imagePath: String
    package let interactionToken: String

    package init(imagePath: String, interactionToken: String) {
        self.imagePath = imagePath
        self.interactionToken = interactionToken
    }
}

package struct OCRWorkerResponse: Codable, Equatable, Sendable {
    package let summary: OCRAnchorSummaryDTO
    package let durationMs: Double

    package init(summary: OCRAnchorSummaryDTO, durationMs: Double) {
        self.summary = summary
        self.durationMs = durationMs
    }
}

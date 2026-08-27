import AppKit
import Foundation

struct OCRRecognitionOutcome {
    let summary: OCRAnchorSummaryDTO
    let durationMs: Double
}

struct OCRRecognitionService: Sendable {
    static let defaultDeadline: TimeInterval = 45
    static let live = OCRRecognitionService(client: .live)

    private let client: OCRWorkerClient

    init(client: OCRWorkerClient) {
        self.client = client
    }

    func recognize(
        imagePath: String,
        interactionToken: String = "legacy",
        deadline: TimeInterval = defaultDeadline
    ) -> OCRAnchorSummaryDTO {
        measure(
            imagePath: imagePath,
            interactionToken: interactionToken,
            deadline: deadline
        ).summary
    }

    func measure(
        imagePath: String,
        interactionToken: String = "legacy",
        deadline: TimeInterval = defaultDeadline
    ) -> OCRRecognitionOutcome {
        client.recognize(
            imagePath: imagePath,
            interactionToken: interactionToken,
            deadline: deadline
        )
    }

    func recognize(
        cgImage: CGImage,
        interactionToken: String,
        deadline: TimeInterval = defaultDeadline
    ) -> OCRAnchorSummaryDTO {
        measure(
            cgImage: cgImage,
            interactionToken: interactionToken,
            deadline: deadline
        ).summary
    }

    func measure(
        cgImage: CGImage,
        interactionToken: String,
        deadline: TimeInterval = defaultDeadline
    ) -> OCRRecognitionOutcome {
        guard let png = NSBitmapImageRep(cgImage: cgImage).representation(
            using: .png,
            properties: [:]
        ) else {
            return imageSerializationFailure()
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "background-computer-use", directoryHint: .isDirectory)
            .appending(path: "ocr-inputs", directoryHint: .isDirectory)
        let imageURL = directory.appending(path: "ocr-\(UUID().uuidString).png")
        do {
            try SecureFileWriter.write(png, to: imageURL)
        } catch {
            return imageSerializationFailure()
        }
        defer { try? FileManager.default.removeItem(at: imageURL) }

        return client.recognize(
            imagePath: imageURL.path,
            interactionToken: interactionToken,
            deadline: deadline
        )
    }

    private func imageSerializationFailure() -> OCRRecognitionOutcome {
        OCRRecognitionOutcome(
            summary: OCRAnchorSummaryBuilder.failure(
                status: .imageUnavailable,
                diagnostic: "OCR could not serialize the captured screenshot image."
            ),
            durationMs: 0
        )
    }
}

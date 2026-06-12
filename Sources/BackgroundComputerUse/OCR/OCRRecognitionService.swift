import AppKit
import Foundation
import Vision

enum OCRRecognitionService {
    static func recognize(imagePath: String) -> OCRAnchorSummaryDTO? {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let width = Double(cgImage.width)
        let height = Double(cgImage.height)
        let lines = (request.results ?? []).compactMap { observation -> OCRLineDTO? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let rect = observation.boundingBox
            return OCRLineDTO(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                box: OCRBoxDTO(
                    x: rect.minX * width,
                    y: (1 - rect.maxY) * height,
                    width: rect.width * width,
                    height: rect.height * height
                )
            )
        }

        return OCRAnchorSummaryBuilder.summary(lines: lines)
    }
}

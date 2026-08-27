import AppKit
import Foundation
import Vision

enum OCRVisionEngine {
    static func measure(
        imagePath: String,
        interactionToken: String
    ) -> OCRRecognitionOutcome {
        let started = DispatchTime.now().uptimeNanoseconds
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return OCRRecognitionOutcome(
                summary: OCRAnchorSummaryBuilder.failure(
                    status: .imageUnavailable,
                    diagnostic: "OCR could not read the captured screenshot image."
                ),
                durationMs: elapsedMilliseconds(since: started)
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return OCRRecognitionOutcome(
                summary: OCRAnchorSummaryBuilder.summary(
                    lines: lines(from: request, image: cgImage),
                    interactionToken: interactionToken
                ),
                durationMs: elapsedMilliseconds(since: started)
            )
        } catch {
            let nsError = error as NSError
            return OCRRecognitionOutcome(
                summary: OCRAnchorSummaryBuilder.failure(
                    status: .recognitionFailed,
                    diagnostic: "Apple Vision failed (domain=\(nsError.domain), code=\(nsError.code))."
                ),
                durationMs: elapsedMilliseconds(since: started)
            )
        }
    }

    private static func lines(
        from request: VNRecognizeTextRequest,
        image: CGImage
    ) -> [OCRLineDTO] {
        let width = Double(image.width)
        let height = Double(image.height)
        return (request.results ?? []).compactMap { observation -> OCRLineDTO? in
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
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

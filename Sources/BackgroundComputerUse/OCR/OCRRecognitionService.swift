import AppKit
import Foundation
import Vision

struct OCRRecognitionOutcome {
    let summary: OCRAnchorSummaryDTO
    let durationMs: Double
}

enum OCRRecognitionService {
    /// Upper bound for a single Apple Vision text recognition. Exceeding it fails closed instead of
    /// hanging the HTTP request behind a stalled recognizer.
    static let defaultDeadline: TimeInterval = 8

    static func recognize(
        imagePath: String,
        interactionToken: String = "legacy",
        deadline: TimeInterval = defaultDeadline
    ) -> OCRAnchorSummaryDTO {
        measure(imagePath: imagePath, interactionToken: interactionToken, deadline: deadline).summary
    }

    static func recognize(
        cgImage: CGImage,
        interactionToken: String,
        deadline: TimeInterval = defaultDeadline
    ) -> OCRAnchorSummaryDTO {
        measure(cgImage: cgImage, interactionToken: interactionToken, deadline: deadline).summary
    }

    static func measure(
        imagePath: String,
        interactionToken: String = "legacy",
        deadline: TimeInterval = defaultDeadline
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
        let outcome = measure(cgImage: cgImage, interactionToken: interactionToken, deadline: deadline)
        return OCRRecognitionOutcome(
            summary: outcome.summary,
            durationMs: elapsedMilliseconds(since: started)
        )
    }

    static func measure(
        cgImage: CGImage,
        interactionToken: String,
        deadline: TimeInterval = defaultDeadline
    ) -> OCRRecognitionOutcome {
        let started = DispatchTime.now().uptimeNanoseconds
        let lines = perform(cgImage: cgImage, deadline: deadline)
        let duration = elapsedMilliseconds(since: started)
        switch lines {
        case let .success(lines):
            return OCRRecognitionOutcome(
                summary: OCRAnchorSummaryBuilder.summary(lines: lines, interactionToken: interactionToken),
                durationMs: duration
            )
        case let .failure(diagnostic):
            return OCRRecognitionOutcome(
                summary: OCRAnchorSummaryBuilder.failure(status: .recognitionFailed, diagnostic: diagnostic),
                durationMs: duration
            )
        }
    }

    /// Runs one recognition pass on a warm-up image so the first real read does not pay Apple Vision's
    /// multi-second cold start. Safe to call repeatedly; callers run it off the bootstrap critical path.
    static func prewarm() {
        guard let image = warmupImage() else {
            return
        }
        _ = perform(cgImage: image, deadline: defaultDeadline)
    }

    private enum RecognitionResult {
        case success([OCRLineDTO])
        case failure(String)
    }

    /// Box that carries the non-Sendable Vision inputs across the worker queue. Ownership is handed to
    /// the worker for the duration of the call; the caller only reads the result after the semaphore.
    private final class RecognitionBox: @unchecked Sendable {
        let image: CGImage
        let request: VNRecognizeTextRequest
        var result: RecognitionResult?

        init(image: CGImage, request: VNRecognizeTextRequest) {
            self.image = image
            self.request = request
        }
    }

    private static func perform(cgImage: CGImage, deadline: TimeInterval) -> RecognitionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let box = RecognitionBox(image: cgImage, request: request)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: box.image, options: [:])
            do {
                try handler.perform([box.request])
                box.result = .success(lines(from: box.request, image: box.image))
            } catch {
                box.result = .failure("Apple Vision text recognition failed.")
            }
            finished.signal()
        }

        guard finished.wait(timeout: .now() + max(deadline, 0)) == .success else {
            request.cancel()
            return .failure(
                "Apple Vision text recognition exceeded the \(String(format: "%.1f", max(deadline, 0)))s recognition deadline and was cancelled."
            )
        }
        return box.result ?? .failure("Apple Vision text recognition produced no result.")
    }

    private static func lines(from request: VNRecognizeTextRequest, image: CGImage) -> [OCRLineDTO] {
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

    private static func warmupImage() -> CGImage? {
        let size = CGSize(width: 160, height: 48)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        ("warmup" as NSString).draw(
            at: CGPoint(x: 8, y: 10),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

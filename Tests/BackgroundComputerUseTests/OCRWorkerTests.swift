import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BackgroundComputerUse

@Suite(.serialized)
struct OCRWorkerTests {
    @Test
    func defaultWorkerDeadlineCoversTheObservedColdStart() {
        #expect(OCRRecognitionService.defaultDeadline == 45)
    }

    @Test
    func workerProtocolRoundTripsWithoutLosingAnchors() throws {
        let request = OCRWorkerRequest(
            imagePath: "/tmp/window.png",
            interactionToken: "it_worker"
        )
        let decodedRequest = try JSONDecoder().decode(
            OCRWorkerRequest.self,
            from: JSONEncoder().encode(request)
        )
        #expect(decodedRequest == request)

        let summary = OCRAnchorSummaryBuilder.summary(
            lines: [
                OCRLineDTO(
                    text: "BCU OCR worker",
                    confidence: 0.99,
                    box: OCRBoxDTO(x: 20, y: 30, width: 240, height: 48)
                ),
            ],
            interactionToken: request.interactionToken
        )
        let response = OCRWorkerResponse(summary: summary, durationMs: 12.5)
        let decodedResponse = try JSONDecoder().decode(
            OCRWorkerResponse.self,
            from: JSONEncoder().encode(response)
        )

        #expect(decodedResponse == response)
        #expect(decodedResponse.summary.anchors.first?.text == "BCU OCR worker")
    }

    @Test
    func visionEngineRecognizesARealTextFixture() throws {
        let imageURL = try OCRTextFixture.makePNG(text: "BCU OCR worker")
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let outcome = OCRVisionEngine.measure(
            imagePath: imageURL.path,
            interactionToken: "it_worker"
        )

        #expect(outcome.durationMs > 0)
        #expect(outcome.summary.status == .success)
        #expect(
            outcome.summary.anchors.contains {
                $0.text.localizedCaseInsensitiveContains("BCU")
            }
        )
    }

    @Test
    func workerTimeoutReturnsRecognitionFailed() {
        let client = makeClient(
            result: BoundedProcessResult(
                status: 124,
                stdout: Data(),
                stderr: Data(),
                stdoutTruncated: false,
                stderrTruncated: false,
                durationMs: 8_000,
                timedOut: true
            )
        )

        let outcome = client.recognize(
            imagePath: "/tmp/window.png",
            interactionToken: "it_1",
            deadline: 8
        )

        #expect(outcome.summary.status == .recognitionFailed)
        #expect(outcome.summary.diagnostic?.contains("timed out") == true)
        #expect(outcome.durationMs == 8_000)
    }

    @Test
    func workerNonZeroExitReturnsRecognitionFailed() {
        let client = makeClient(
            result: BoundedProcessResult(
                status: 2,
                stdout: Data(),
                stderr: Data("worker failed".utf8),
                stdoutTruncated: false,
                stderrTruncated: false,
                durationMs: 12,
                timedOut: false
            )
        )

        let outcome = client.recognize(
            imagePath: "/tmp/window.png",
            interactionToken: "it_1"
        )

        #expect(outcome.summary.status == .recognitionFailed)
        #expect(outcome.summary.diagnostic?.contains("status 2") == true)
    }

    @Test
    func workerTruncationAndInvalidJSONFailClosed() {
        let truncated = makeClient(
            result: BoundedProcessResult(
                status: 0,
                stdout: Data("{}".utf8),
                stderr: Data(),
                stdoutTruncated: true,
                stderrTruncated: false,
                durationMs: 10,
                timedOut: false
            )
        ).recognize(imagePath: "/tmp/window.png", interactionToken: "it_1")
        #expect(truncated.summary.status == .recognitionFailed)
        #expect(truncated.summary.diagnostic?.contains("truncated") == true)

        let invalid = makeClient(
            result: BoundedProcessResult(
                status: 0,
                stdout: Data("not-json".utf8),
                stderr: Data(),
                stdoutTruncated: false,
                stderrTruncated: false,
                durationMs: 11,
                timedOut: false
            )
        ).recognize(imagePath: "/tmp/window.png", interactionToken: "it_1")
        #expect(invalid.summary.status == .recognitionFailed)
        #expect(invalid.summary.diagnostic?.contains("invalid response") == true)
    }

    @Test
    func validWorkerResponsePreservesTheSummary() throws {
        let summary = OCRAnchorSummaryBuilder.summary(
            lines: [
                OCRLineDTO(
                    text: "BCU worker",
                    confidence: 0.98,
                    box: OCRBoxDTO(x: 10, y: 20, width: 160, height: 44)
                ),
            ],
            interactionToken: "it_1"
        )
        let response = OCRWorkerResponse(summary: summary, durationMs: 7)
        let client = makeClient(
            result: BoundedProcessResult(
                status: 0,
                stdout: try JSONEncoder().encode(response),
                stderr: Data(),
                stdoutTruncated: false,
                stderrTruncated: false,
                durationMs: 19,
                timedOut: false
            )
        )

        let outcome = client.recognize(
            imagePath: "/tmp/window.png",
            interactionToken: "it_1"
        )

        #expect(outcome.summary == summary)
        #expect(outcome.durationMs == 19)
    }

    private func makeClient(result: BoundedProcessResult) -> OCRWorkerClient {
        OCRWorkerClient(
            run: { _ in result },
            executableURL: URL(fileURLWithPath: "/tmp/BackgroundComputerUse")
        )
    }
}

private enum OCRTextFixture {
    static func makePNG(text: String) throws -> URL {
        let width = 800
        let height = 200
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 54, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        let attributed = try #require(
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 40, y: 80)
        CTLineDraw(line, context)

        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-ocr-worker-\(UUID().uuidString).png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}

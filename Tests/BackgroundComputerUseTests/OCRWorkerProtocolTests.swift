import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BackgroundComputerUse

@Suite(.serialized)
struct OCRWorkerProtocolTests {
    @Test
    func executableProcessesAValidRequestAndPreservesTheInteractionToken() throws {
        let executableURL = try workerExecutableURL()
        let imageURL = try OCRProtocolPNGFixture.makePNG(text: "BCU OCR PROTOCOL")
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let interactionToken = "it_protocol_42"
        let request = OCRWorkerRequest(
            imagePath: imageURL.path,
            interactionToken: interactionToken
        )
        let result = try runWorker(
            executableURL: executableURL,
            stdin: JSONEncoder().encode(request)
        )

        #expect(result.status == 0)
        #expect(result.timedOut == false)
        #expect(result.stderr.isEmpty)
        let response = try JSONDecoder().decode(OCRWorkerResponse.self, from: result.stdout)
        #expect(response.summary.status == .success)
        #expect(response.summary.anchors.isEmpty == false)

        let recognizedLines = response.summary.anchors.map {
            OCRLineDTO(text: $0.text, confidence: $0.confidence, box: $0.box)
        }
        let expected = OCRAnchorSummaryBuilder.summary(
            lines: recognizedLines,
            interactionToken: interactionToken
        )
        let wrongToken = OCRAnchorSummaryBuilder.summary(
            lines: recognizedLines,
            interactionToken: "it_different"
        )
        #expect(response.summary.anchors.map(\.id) == expected.anchors.map(\.id))
        #expect(response.summary.anchors.map(\.id) != wrongToken.anchors.map(\.id))
    }

    @Test
    func executableRejectsMalformedStandardInput() throws {
        let result = try runWorker(
            executableURL: workerExecutableURL(),
            stdin: Data("not-json".utf8)
        )

        #expect(result.status == 2)
        #expect(result.timedOut == false)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty == false)
    }

    private func workerExecutableURL() throws -> URL {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/BackgroundComputerUse")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        return url
    }

    private func runWorker(executableURL: URL, stdin: Data) throws -> BoundedProcessResult {
        try BoundedProcessRunner().run(
            BoundedProcessInvocation(
                executableURL: executableURL,
                arguments: ["--ocr-worker"],
                stdin: stdin,
                timeoutMs: 60_000
            )
        )
    }
}

private enum OCRProtocolPNGFixture {
    static func makePNG(text: String) throws -> URL {
        let width = 900
        let height = 220
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

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 58, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        let attributed = try #require(
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 35, y: 90)
        CTLineDraw(line, context)

        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-ocr-protocol-\(UUID().uuidString).png")
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

import Foundation

package enum OCRWorkerMain {
    package static func run() -> Never {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONSupport.decoder.decode(OCRWorkerRequest.self, from: input)
            let outcome = OCRVisionEngine.measure(
                imagePath: request.imagePath,
                interactionToken: request.interactionToken
            )
            let response = OCRWorkerResponse(
                summary: outcome.summary,
                durationMs: outcome.durationMs
            )
            FileHandle.standardOutput.write(try JSONSupport.encoder.encode(response))
            Foundation.exit(0)
        } catch {
            fputs("BackgroundComputerUse OCR worker failed to process its request.\n", stderr)
            Foundation.exit(2)
        }
    }
}

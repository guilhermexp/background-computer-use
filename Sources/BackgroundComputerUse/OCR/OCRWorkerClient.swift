import Foundation

struct OCRWorkerClient: Sendable {
    typealias RunProcess = @Sendable (BoundedProcessInvocation) throws -> BoundedProcessResult

    static var live: OCRWorkerClient {
        let executableURL = Bundle.main.executableURL ?? URL(
            fileURLWithPath: CommandLine.arguments.first ?? "BackgroundComputerUse"
        )
        let runner = BoundedProcessRunner()
        return OCRWorkerClient(run: runner.run, executableURL: executableURL)
    }

    private let run: RunProcess
    private let executableURL: URL

    init(
        run: @escaping RunProcess,
        executableURL: URL
    ) {
        self.run = run
        self.executableURL = executableURL
    }

    func recognize(
        imagePath: String,
        interactionToken: String,
        deadline: TimeInterval = OCRRecognitionService.defaultDeadline
    ) -> OCRRecognitionOutcome {
        let timeoutMs = max(0, Int((deadline * 1_000).rounded()))
        let invocation: BoundedProcessInvocation
        do {
            invocation = BoundedProcessInvocation(
                executableURL: executableURL,
                arguments: ["--ocr-worker"],
                stdin: try JSONSupport.encoder.encode(
                    OCRWorkerRequest(
                        imagePath: imagePath,
                        interactionToken: interactionToken
                    )
                ),
                timeoutMs: timeoutMs
            )
        } catch {
            return failure(
                "OCR worker request could not be encoded.",
                durationMs: 0
            )
        }

        let result: BoundedProcessResult
        do {
            result = try run(invocation)
        } catch {
            return failure(
                "OCR worker could not be launched.",
                durationMs: 0
            )
        }

        if result.timedOut {
            return failure(
                "OCR worker timed out after \(String(format: "%.1f", max(deadline, 0)))s and was terminated.",
                durationMs: result.durationMs
            )
        }
        guard result.status == 0 else {
            return failure(
                "OCR worker exited with status \(result.status).",
                durationMs: result.durationMs
            )
        }
        guard result.stdoutTruncated == false else {
            return failure(
                "OCR worker response was truncated.",
                durationMs: result.durationMs
            )
        }
        guard let response = try? JSONSupport.decoder.decode(
            OCRWorkerResponse.self,
            from: result.stdout
        ) else {
            return failure(
                "OCR worker returned an invalid response.",
                durationMs: result.durationMs
            )
        }
        return OCRRecognitionOutcome(
            summary: response.summary,
            durationMs: result.durationMs
        )
    }

    private func failure(
        _ diagnostic: String,
        durationMs: Double
    ) -> OCRRecognitionOutcome {
        OCRRecognitionOutcome(
            summary: OCRAnchorSummaryBuilder.failure(
                status: .recognitionFailed,
                diagnostic: diagnostic
            ),
            durationMs: durationMs
        )
    }
}

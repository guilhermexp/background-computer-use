import Foundation

typealias ScriptProcessExecutorError = BoundedProcessRunnerError

struct ScriptProcessResult: Sendable {
    let status: Int
    let stdout: String
    let stderr: String
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let durationMs: Double
    let timedOut: Bool
}

struct ScriptProcessExecutor {
    static let maximumCapturedOutputBytes = BoundedProcessRunner.maximumCapturedOutputBytes

    private let runner = BoundedProcessRunner()

    func execute(
        language: ScriptLanguageDTO,
        source: String,
        timeoutMs: Int
    ) throws -> ScriptProcessResult {
        let invocation = BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", language.osascriptName],
            stdin: Data((source + "\n").utf8),
            timeoutMs: timeoutMs
        )
        let result = try runner.run(invocation)
        return ScriptProcessResult(
            status: result.status,
            stdout: String(decoding: result.stdout, as: UTF8.self),
            stderr: String(decoding: result.stderr, as: UTF8.self),
            stdoutTruncated: result.stdoutTruncated,
            stderrTruncated: result.stderrTruncated,
            durationMs: result.durationMs,
            timedOut: result.timedOut
        )
    }
}

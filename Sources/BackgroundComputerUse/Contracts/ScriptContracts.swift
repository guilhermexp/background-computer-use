import Foundation

public enum ScriptLanguageDTO: String, Codable, Sendable {
    case appleScript = "applescript"
    case javaScript = "javascript"

    var osascriptName: String {
        switch self {
        case .appleScript: "AppleScript"
        case .javaScript: "JavaScript"
        }
    }
}

public struct RunScriptRequest: Codable, Sendable {
    public let language: String
    public let source: String
    public let timeoutMs: Int?

    public init(language: String, source: String, timeoutMs: Int? = nil) {
        self.language = language
        self.source = source
        self.timeoutMs = timeoutMs
    }
}

public struct RunScriptResponse: Encodable, Sendable {
    public let contractVersion: String
    public let language: ScriptLanguageDTO
    public let status: Int
    public let stdout: String
    public let stderr: String
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let durationMs: Double
    public let timedOut: Bool
    public let effectiveTimeoutMs: Int

    public init(
        contractVersion: String,
        language: ScriptLanguageDTO,
        status: Int,
        stdout: String,
        stderr: String,
        stdoutTruncated: Bool,
        stderrTruncated: Bool,
        durationMs: Double,
        timedOut: Bool,
        effectiveTimeoutMs: Int
    ) {
        self.contractVersion = contractVersion
        self.language = language
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.durationMs = durationMs
        self.timedOut = timedOut
        self.effectiveTimeoutMs = effectiveTimeoutMs
    }
}

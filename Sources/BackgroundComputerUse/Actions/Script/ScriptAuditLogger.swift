import Darwin
import Foundation

struct ScriptAuditEntry: Encodable, Sendable {
    let timestamp: String
    let language: String
    let source: String
    let durationMs: Double
    let status: Int?
    let outcome: String
    let timedOut: Bool
    let effectiveTimeoutMs: Int?
}

struct ScriptAuditLogger: Sendable {
    private static let appendLock = NSLock()

    let rootDirectory: URL

    init(rootDirectory: URL = ScriptAuditLogger.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    var auditDirectoryURL: URL {
        rootDirectory.appendingPathComponent("audit", isDirectory: true)
    }

    var auditLogURL: URL {
        auditDirectoryURL.appendingPathComponent("script-executions.jsonl")
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("background-computer-use", isDirectory: true)
    }

    func prepare() throws {
        try SecureFileWriter.prepareDirectory(auditDirectoryURL)
        let descriptor = Darwin.open(
            auditLogURL.path,
            O_WRONLY | O_CREAT | O_APPEND,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func record(
        request: RunScriptRequest,
        outcome: String,
        durationMs: Double,
        status: Int?,
        timedOut: Bool,
        effectiveTimeoutMs: Int?
    ) throws {
        try prepare()
        let entry = ScriptAuditEntry(
            timestamp: Time.iso8601String(from: Date()),
            language: request.language,
            source: request.source,
            durationMs: durationMs,
            status: status,
            outcome: outcome,
            timedOut: timedOut,
            effectiveTimeoutMs: effectiveTimeoutMs
        )
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)

        let descriptor = Darwin.open(auditLogURL.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        Self.appendLock.lock()
        defer { Self.appendLock.unlock() }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    buffer.count - written
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += result
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

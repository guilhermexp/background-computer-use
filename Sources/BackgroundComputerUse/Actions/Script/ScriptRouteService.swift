import Foundation

enum ScriptRouteError: Error, Equatable {
    case invalidRequest(String)
    case auditFailed(String)
}

struct ScriptRouteService {
    static let defaultTimeoutMs = 10_000
    static let maximumTimeoutMs = 30_000

    private let auditLogger: ScriptAuditLogger
    private let executor = ScriptProcessExecutor()

    init(auditLogger: ScriptAuditLogger = ScriptAuditLogger()) {
        self.auditLogger = auditLogger
    }

    func runScript(request: RunScriptRequest) throws -> RunScriptResponse {
        let validationStarted = DispatchTime.now().uptimeNanoseconds
        let language: ScriptLanguageDTO
        do {
            language = try validatedLanguage(request.language)
            try validateSource(request.source)
            try validateTimeout(request.timeoutMs)
        } catch {
            let durationMs = elapsedMilliseconds(since: validationStarted)
            do {
                try auditLogger.record(
                    request: request,
                    outcome: "rejected",
                    durationMs: durationMs,
                    status: nil,
                    timedOut: false,
                    effectiveTimeoutMs: nil
                )
            } catch {
                throw ScriptRouteError.auditFailed(
                    "The run_script request was rejected before dispatch, but its audit record could not be persisted."
                )
            }
            throw error
        }

        let effectiveTimeoutMs = min(request.timeoutMs ?? Self.defaultTimeoutMs, Self.maximumTimeoutMs)
        do {
            try auditLogger.prepare()
        } catch {
            throw ScriptRouteError.auditFailed(
                "The owner-only run_script audit log could not be prepared, so the script was not dispatched."
            )
        }
        let result: ScriptProcessResult
        do {
            result = try executor.execute(
                language: language,
                source: request.source,
                timeoutMs: effectiveTimeoutMs
            )
        } catch {
            do {
                try auditLogger.record(
                    request: request,
                    outcome: "transport_failed",
                    durationMs: elapsedMilliseconds(since: validationStarted),
                    status: nil,
                    timedOut: false,
                    effectiveTimeoutMs: effectiveTimeoutMs
                )
            } catch {
                throw ScriptRouteError.auditFailed(
                    "run_script transport failed and the owner-only audit outcome could not be persisted."
                )
            }
            throw error
        }
        do {
            try auditLogger.record(
                request: request,
                outcome: result.timedOut ? "timed_out" : "executed",
                durationMs: result.durationMs,
                status: result.status,
                timedOut: result.timedOut,
                effectiveTimeoutMs: effectiveTimeoutMs
            )
        } catch {
            throw ScriptRouteError.auditFailed(
                "The script process finished, but its owner-only final audit record could not be persisted."
            )
        }
        return RunScriptResponse(
            contractVersion: ContractVersion.current,
            language: language,
            status: result.status,
            stdout: result.stdout,
            stderr: result.stderr,
            stdoutTruncated: result.stdoutTruncated,
            stderrTruncated: result.stderrTruncated,
            durationMs: result.durationMs,
            timedOut: result.timedOut,
            effectiveTimeoutMs: effectiveTimeoutMs
        )
    }

    private func validatedLanguage(_ raw: String) throws -> ScriptLanguageDTO {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = ScriptLanguageDTO(rawValue: normalized) else {
            throw ScriptRouteError.invalidRequest("Unsupported script language '\(raw)'.")
        }
        return language
    }

    private func validateSource(_ source: String) throws {
        guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ScriptRouteError.invalidRequest("run_script requires a non-empty source string.")
        }
    }

    private func validateTimeout(_ timeoutMs: Int?) throws {
        guard let timeoutMs else { return }
        guard timeoutMs > 0 else {
            throw ScriptRouteError.invalidRequest("timeoutMs must be greater than zero.")
        }
    }

    private func elapsedMilliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }
}

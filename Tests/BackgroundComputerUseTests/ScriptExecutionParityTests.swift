import Darwin
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite(.serialized)
struct ScriptExecutionParityTests {
    @Test
    func appleScriptSuccessReturnsProcessOutput() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "applescript",
                source: "return \"hello from AppleScript\"",
                timeoutMs: 2_000
            )
        )

        #expect(response.status == 0)
        #expect(response.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello from AppleScript")
        #expect(response.stderr.isEmpty)
        #expect(response.durationMs >= 0)
        #expect(response.timedOut == false)
        #expect(response.effectiveTimeoutMs == 2_000)
    }

    @Test
    func javaScriptSuccessReturnsProcessOutput() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "javascript",
                source: "'hello from JXA'",
                timeoutMs: 2_000
            )
        )

        #expect(response.status == 0)
        #expect(response.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello from JXA")
        #expect(response.timedOut == false)
    }

    @Test
    func failingScriptReturnsStderrWithoutTransportError() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "applescript",
                source: "this is not valid AppleScript source",
                timeoutMs: 2_000
            )
        )

        #expect(response.status != 0)
        #expect(response.stderr.isEmpty == false)
        #expect(response.timedOut == false)
    }

    @Test
    func scriptResponseContainsNoClassificationField() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }
        let response = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: "return 1", timeoutMs: 2_000)
        )

        let data = try JSONSupport.encoder.encode(response)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["status"] as? Int == 0)
        #expect(json["classification"] == nil)
    }

    @Test
    func timedOutScriptLeavesNoSurvivingChildProcess() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }
        let childPIDFile = scope.root.appendingPathComponent("child.pid")
        let shell = "sleep 30 & child=$!; echo $child > '\(childPIDFile.path)'; wait $child"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\\"", with: "\\\\\\\""))\""

        let response = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: source, timeoutMs: 500)
        )

        #expect(response.timedOut)
        #expect(response.status != 0)
        #expect(response.effectiveTimeoutMs == 500)
        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try #require(pid_t(childPIDText))
        errno = 0
        #expect(Darwin.kill(childPID, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test
    func timedOutScriptKillsChildThatCreatesNewSession() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }
        let childPIDFile = scope.root.appendingPathComponent("detached-child.pid")
        let shell = "/usr/bin/perl -MPOSIX -e 'POSIX::setsid(); sleep 30' & child=$!; echo $child > '\(childPIDFile.path)'; wait $child"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\\"", with: "\\\\\\\""))\""
        var childPID: pid_t?
        defer {
            if let childPID, Darwin.kill(childPID, 0) == 0 {
                _ = Darwin.kill(childPID, SIGKILL)
            }
        }

        let response = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: source, timeoutMs: 500)
        )
        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        childPID = pid_t(try #require(Int(childPIDText)))

        #expect(response.timedOut)
        errno = 0
        #expect(Darwin.kill(childPID!, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test
    func largeSourceTimeoutDoesNotRaiseSIGPIPE() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }
        let source = "delay 30\n" + String(repeating: "-- padding to keep stdin writer active\n", count: 100_000)

        let response = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: source, timeoutMs: 1)
        )

        #expect(response.timedOut)
        #expect(response.status != 0)
    }

    @Test
    func oversizedStdoutIsDrainedTruncatedAndReported() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "javascript",
                source: "Array(1500000).fill('x').join('')",
                timeoutMs: 5_000
            )
        )

        #expect(response.status == 0)
        #expect(response.stdoutTruncated)
        #expect(response.stdout.utf8.count == ScriptProcessExecutor.maximumCapturedOutputBytes)
        #expect(response.stderrTruncated == false)
    }

    @Test
    func truncatedMultibyteStdoutPreservesCapturedPrefix() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "javascript",
                source: "Array(1048575).fill('a').join('') + '😀'",
                timeoutMs: 5_000
            )
        )

        #expect(response.status == 0)
        #expect(response.stdoutTruncated)
        #expect(response.stdout.hasPrefix("aaa"))
        #expect(response.stdout.isEmpty == false)
    }

    @Test
    func excessiveTimeoutIsCappedAndReported() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let response = try scope.service.runScript(
            request: RunScriptRequest(
                language: "applescript",
                source: "return \"capped\"",
                timeoutMs: ScriptRouteService.maximumTimeoutMs * 10
            )
        )

        #expect(response.status == 0)
        #expect(response.effectiveTimeoutMs == ScriptRouteService.maximumTimeoutMs)
    }

    @Test
    func auditLogUsesOwnerOnlyPermissionsAndRecordsOutcomes() throws {
        let scope = try makeScope()
        defer { try? FileManager.default.removeItem(at: scope.root) }

        let successSource = "return \"audit-success\""
        _ = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: successSource, timeoutMs: 2_000)
        )
        #expect(throws: ScriptRouteError.invalidRequest("Unsupported script language 'ruby'.")) {
            _ = try scope.service.runScript(
                request: RunScriptRequest(language: "ruby", source: "puts 'rejected'", timeoutMs: 2_000)
            )
        }
        _ = try scope.service.runScript(
            request: RunScriptRequest(language: "applescript", source: "delay 2", timeoutMs: 200)
        )

        #expect(try posixMode(scope.logger.auditDirectoryURL) == 0o700)
        #expect(try posixMode(scope.logger.auditLogURL) == 0o600)
        let log = try String(contentsOf: scope.logger.auditLogURL, encoding: .utf8)
        let entries = try log.split(separator: "\n").map { line in
            try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
        }
        #expect(entries.contains { $0["source"] as? String == successSource })
        #expect(entries.contains { $0["outcome"] as? String == "executed" })
        #expect(entries.contains { $0["outcome"] as? String == "rejected" })
        #expect(entries.contains { $0["outcome"] as? String == "timed_out" })
    }

    private func makeScope() throws -> (
        root: URL,
        logger: ScriptAuditLogger,
        service: ScriptRouteService
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-script-test-\(UUID().uuidString)", isDirectory: true)
        let logger = ScriptAuditLogger(rootDirectory: root)
        return (root, logger, ScriptRouteService(auditLogger: logger))
    }

    private func posixMode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}

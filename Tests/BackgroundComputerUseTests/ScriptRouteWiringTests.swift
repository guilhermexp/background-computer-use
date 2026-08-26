import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite(.serialized)
struct ScriptRouteWiringTests {
    @Test
    func runScriptRouteDocumentsUngatedContractAndDTOFields() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.runScript.rawValue }
        )

        #expect(route.method == "POST")
        #expect(route.path == "/v1/run_script")
        #expect(route.execution.lane == .windowWrite)
        #expect(route.usage.whenToUse.contains("without effect verification"))
        #expect(route.usage.nextSteps.contains { $0.contains("get_window_state") })

        let requestData = try JSONSupport.encoder.encode(
            RunScriptRequest(language: "javascript", source: "1 + 1", timeoutMs: 1_000)
        )
        let requestJSON = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        let requestSchema = try #require(route.request)
        #expect(Set(requestSchema.fields.map(\.name)) == Set(requestJSON.keys))

        let response = RunScriptResponse(
            contractVersion: ContractVersion.current,
            language: .javaScript,
            status: 0,
            stdout: "2\n",
            stderr: "",
            stdoutTruncated: false,
            stderrTruncated: false,
            durationMs: 12,
            timedOut: false,
            effectiveTimeoutMs: 1_000
        )
        let responseData = try JSONSupport.encoder.encode(response)
        let responseJSON = try #require(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        #expect(Set(route.response.fields.map(\.name)) == Set(responseJSON.keys))
        #expect(responseJSON["classification"] == nil)
    }

    @Test
    func runScriptIsActionRouteAndAuditsSessionRejection() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = ScriptAuditLogger(rootDirectory: root)
        let limiter = RuntimeSessionLimiter()
        #expect(limiter.acquire(sessionID: "holder").allowed)
        defer { limiter.release(sessionID: "holder") }
        let router = Router(
            auth: .disabled,
            sessionLimiter: limiter,
            scriptAuditLogger: logger
        )
        let source = "return \"session-rejected\""
        let request = try makeRequest(
            body: #"{"language":"applescript","source":"return \"session-rejected\"","timeoutMs":1000}"#,
            headers: ["X-Background-Computer-Use-Session": "other"]
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 409)
        let log = try String(contentsOf: logger.auditLogURL, encoding: .utf8)
        let entry = try #require(
            JSONSerialization.jsonObject(with: Data(log.utf8)) as? [String: Any]
        )
        #expect(entry["source"] as? String == source)
        #expect(entry["outcome"] as? String == "session_busy")
    }

    @Test
    func runScriptDebugArtifactsNeverContainSourceEvenWithRawOverride() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = ScriptAuditLogger(rootDirectory: root.appendingPathComponent("runtime"))
        let recorder = DebugArtifactRecorder(
            rootDirectory: root.appendingPathComponent("debug"),
            enabled: true,
            rawArtifactsEnabled: true
        )
        let router = Router(
            auth: .disabled,
            debugArtifactRecorder: recorder,
            scriptAuditLogger: logger
        )
        let secretSource = "return \"SCRIPT_SOURCE_SENTINEL\""
        let request = try makeRequest(
            body: #"{"language":"applescript","source":"return \"SCRIPT_SOURCE_SENTINEL\"","timeoutMs":1000}"#
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 200)
        let artifactFiles = try FileManager.default.subpathsOfDirectory(atPath: recorder.rootDirectory.path)
            .filter { $0.hasSuffix(".json") }
        #expect(artifactFiles.isEmpty == false)
        for relativePath in artifactFiles {
            let contents = try String(
                contentsOf: recorder.rootDirectory.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(contents.contains(secretSource) == false)
            #expect(contents.contains("SCRIPT_SOURCE_SENTINEL") == false)
        }
    }

    @Test
    func runScriptDecodeRejectionIsAuditLogged() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = ScriptAuditLogger(rootDirectory: root)
        let router = Router(auth: .disabled, scriptAuditLogger: logger)
        let source = "return \"decode-rejected\""
        let request = try makeRequest(
            body: #"{"language":"applescript","source":"return \"decode-rejected\"","timeoutMs":"wrong-type"}"#
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 400)
        let log = try String(contentsOf: logger.auditLogURL, encoding: .utf8)
        let entry = try #require(
            JSONSerialization.jsonObject(with: Data(log.utf8)) as? [String: Any]
        )
        #expect(entry["source"] as? String == source)
        #expect(entry["outcome"] as? String == "invalid_request")
    }

    @Test
    func runScriptRefusalFailsClosedWhenAuditIsUnavailable() throws {
        let logger = ScriptAuditLogger(
            rootDirectory: URL(fileURLWithPath: "/dev/null/bcu-audit-unavailable", isDirectory: true)
        )
        let limiter = RuntimeSessionLimiter()
        #expect(limiter.acquire(sessionID: "holder").allowed)
        defer { limiter.release(sessionID: "holder") }
        let router = Router(
            auth: .disabled,
            sessionLimiter: limiter,
            scriptAuditLogger: logger
        )
        let request = try makeRequest(
            body: #"{"language":"applescript","source":"return 1","timeoutMs":1000}"#,
            headers: ["X-Background-Computer-Use-Session": "other"]
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])

        #expect(response.statusCode == 500)
        #expect(json["error"] as? String == "audit_failed")
    }

    @Test
    func runScriptInvalidLanguageTypeStillAuditsSubmittedSource() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = ScriptAuditLogger(rootDirectory: root)
        let router = Router(auth: .disabled, scriptAuditLogger: logger)
        let source = "return \"invalid-language-type\""
        let request = try makeRequest(
            body: #"{"language":1,"source":"return \"invalid-language-type\"","timeoutMs":1000}"#
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 400)
        let log = try String(contentsOf: logger.auditLogURL, encoding: .utf8)
        let entry = try #require(
            JSONSerialization.jsonObject(with: Data(log.utf8)) as? [String: Any]
        )
        #expect(entry["source"] as? String == source)
        #expect(entry["language"] as? String == "<invalid>")
        #expect(entry["outcome"] as? String == "invalid_request")
    }

    @Test
    func runScriptServiceAuditFailureUsesAuditFailedError() throws {
        let logger = ScriptAuditLogger(
            rootDirectory: URL(fileURLWithPath: "/dev/null/bcu-service-audit-unavailable", isDirectory: true)
        )
        let router = Router(auth: .disabled, scriptAuditLogger: logger)
        let request = try makeRequest(
            body: #"{"language":"applescript","source":"return 1","timeoutMs":1000}"#
        )

        let response = router.response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])

        #expect(response.statusCode == 500)
        #expect(json["error"] as? String == "audit_failed")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-script-route-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeRequest(
        body: String,
        headers: [String: String] = [:]
    ) throws -> HTTPRequest {
        let bodyData = Data(body.utf8)
        var request = "POST /v1/run_script HTTP/1.1\r\n"
        request += "Host: 127.0.0.1\r\n"
        request += "Content-Type: application/json\r\n"
        for (name, value) in headers {
            request += "\(name): \(value)\r\n"
        }
        request += "Content-Length: \(bodyData.count)\r\n\r\n"
        var data = Data(request.utf8)
        data.append(bodyData)

        switch HTTPRequest.parse(data) {
        case .complete(let parsed): return parsed
        case .incomplete, .invalid, .tooLarge: throw ScriptRouteTestError.requestParseFailed
        }
    }
}

private enum ScriptRouteTestError: Error {
    case requestParseFailed
}

import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct RunLoopSupportCorrectnessTests {
    @Test
    func backgroundQueueSleepActuallyElapses() async {
        let interval = 0.05
        let elapsed = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startedAt = Date()
                sleepRunLoop(interval)
                continuation.resume(returning: Date().timeIntervalSince(startedAt))
            }
        }

        #expect(elapsed >= interval * 0.9)
    }
}

@Suite
struct RouteSelfDocumentationCorrectnessTests {
    @Test
    func documentedMenuBarDefaultsMatchServices() throws {
        let routes = RouteRegistry.publicRoutes()

        let getState = try #require(routes.first { $0.id == RouteID.getWindowState.rawValue })
        let annotate = try #require(routes.first { $0.id == RouteID.annotateWindow.rawValue })
        let getStateField = try #require(getState.request?.fields.first { $0.name == "includeMenuBar" })
        let annotateField = try #require(annotate.request?.fields.first { $0.name == "includeMenuBar" })

        #expect(getStateField.defaultValue == "true")
        #expect(annotateField.defaultValue == "false")
        #expect(getStateField.description?.contains("state capture") == true)
    }

    @Test
    func motionCoordinatesAndPressKeyChordAreDocumented() throws {
        let routes = RouteRegistry.publicRoutes()
        let drag = try #require(routes.first { $0.id == RouteID.drag.rawValue })
        let resize = try #require(routes.first { $0.id == RouteID.resize.rawValue })
        let pressKey = try #require(routes.first { $0.id == RouteID.pressKey.rawValue })

        for route in [drag, resize] {
            for name in ["toX", "toY"] {
                let field = try #require(route.request?.fields.first { $0.name == name })
                #expect(field.description?.contains("AppKit-global") == true)
                #expect(field.description?.contains("bottom-left") == true)
                #expect(field.description?.contains("logical points") == true)
            }
        }

        let key = try #require(pressKey.request?.fields.first { $0.name == "key" })
        #expect(key.description?.contains("command/cmd/meta/super") == true)
        #expect(key.description?.contains("control/ctrl") == true)
        #expect(key.description?.contains("option/alt") == true)
        #expect(key.description?.contains("command+f") == true)
    }

    @Test
    func guideExplainsSessionsAndCoordinates() throws {
        let concepts = APIDocumentation.guide.concepts
        let session = try #require(concepts.first { $0.name == "session" })
        let coordinates = try #require(concepts.first { $0.name == "coordinates" })

        #expect(session.description.contains("X-Background-Computer-Use-Session"))
        #expect(session.description.contains("409"))
        #expect(session.description.contains("429"))
        #expect(coordinates.description.contains("AppKit-global"))
        #expect(coordinates.description.contains("bottom-left"))
    }
}

@Suite
struct SharedWindowResolutionCorrectnessTests {
    @Test
    func pressKeyAndClickSharedHeuristicPrefersFocusedWindowWithoutWindowNumber() {
        let target = ResolvedWindowDTO(
            windowID: "fixture-window",
            title: "Document",
            bundleID: "com.example.fixture",
            pid: 123,
            launchDate: nil,
            windowNumber: 42,
            frameAppKit: RectDTO(x: 20, y: 30, width: 800, height: 600),
            resolutionStrategy: "fixture"
        )
        let unfocused = AXWindowMatchAttributes(
            title: "Document",
            frame: CGRect(x: 20, y: 30, width: 800, height: 600),
            windowNumber: nil,
            isMain: false,
            isFocused: false
        )
        let focused = AXWindowMatchAttributes(
            title: "Document",
            frame: CGRect(x: 20, y: 30, width: 800, height: 600),
            windowNumber: nil,
            isMain: false,
            isFocused: true
        )
        let resolver = AXActionTargetResolver()

        #expect(resolver.scoreWindow(focused, target: target) > resolver.scoreWindow(unfocused, target: target))
    }
}

@Suite
struct WaitForClosureCorrectnessTests {
    @Test
    func goneWaitTreatsClosureDuringPollingAsMet() {
        let outcome = WaitForRouteService.closedWindowOutcome(waitForGone: true, stage: .poll)

        #expect(outcome.conditionMet)
        #expect(outcome.note.contains("target window closed"))
    }

    @Test
    func goneWaitSurvivesClosureBeforeFinalCapture() {
        let outcome = WaitForRouteService.closedWindowOutcome(waitForGone: true, stage: .finalCapture)

        #expect(outcome.conditionMet)
        #expect(outcome.note.contains("final capture"))
    }

    @Test
    func nonGoneWaitTreatsClosureAsUnmet() {
        let outcome = WaitForRouteService.closedWindowOutcome(waitForGone: false, stage: .poll)

        #expect(!outcome.conditionMet)
        #expect(outcome.note.contains("target window closed"))
    }
}

@Suite
struct RuntimeCorrectnessTests {
    private enum FixtureError: Error, CustomStringConvertible {
        case exploded

        var description: String { "fixture exploded" }
    }

    @Test
    func sessionLimiterKeepsExclusionUntilAllSameSessionRequestsRelease() {
        let limiter = RuntimeSessionLimiter()

        #expect(limiter.acquire(sessionID: "a").allowed)
        #expect(limiter.acquire(sessionID: "a").allowed)
        limiter.release(sessionID: "a")
        #expect(!limiter.acquire(sessionID: "b").allowed)
        limiter.release(sessionID: "a")
        #expect(limiter.acquire(sessionID: "b").allowed)
    }

    @Test
    func internalErrorCarriesCauseAndOriginalRequestID() throws {
        let response = Router(auth: .disabled).errorResponse(
            for: FixtureError.exploded,
            routeID: .listApps,
            requestID: "request-fixture"
        )
        let json = try decodeJSON(response.body)

        #expect(json["error"] as? String == "internal_error")
        #expect((json["message"] as? String)?.contains("fixture exploded") == true)
        #expect(json["requestID"] as? String == "request-fixture")
    }

    @Test
    func screenshotErrorGetsSpecificCodeAndRecovery() throws {
        let response = Router(auth: .disabled).errorResponse(
            for: CGWindowCaptureError.permissionDenied,
            routeID: .getWindowState,
            requestID: "screenshot-request"
        )
        let json = try decodeJSON(response.body)

        #expect(json["error"] as? String == "screenshot_failed")
        #expect(json["requestID"] as? String == "screenshot-request")
        #expect((json["message"] as? String)?.contains("Screen Recording") == true)
        #expect((json["recovery"] as? [String])?.isEmpty == false)
    }

    @Test
    func deadFieldsAreAbsentAndCapturingActionsExposePostScreenshot() throws {
        for routeID in [RouteID.scroll, .typeText, .setValue] {
            #expect(!RouteRegistry.requestFieldNames(for: routeID).contains("imageMode"))
        }
        #expect(!RouteRegistry.requestFieldNames(for: .scroll).contains("verificationMode"))

        let routes = RouteRegistry.publicRoutes()
        for routeID in [RouteID.click, .pressKey, .selectText, .performSecondaryAction] {
            let route = try #require(routes.first { $0.id == routeID.rawValue })
            #expect(route.response.fields.contains { $0.name == "postScreenshot" })
        }
    }
}

@Suite
struct RuntimeSecurityCorrectnessTests {
    @Test
    func constantTimeComparatorReturnsCorrectResults() {
        #expect(RuntimeAuth.constantTimeEqual("abc", "abc"))
        #expect(!RuntimeAuth.constantTimeEqual("abc", "xbc"))
        #expect(!RuntimeAuth.constantTimeEqual("abc", "abcd"))
    }

    @Test
    func hostGuardAcceptsLoopbackAndRejectsOtherHosts() throws {
        let router = Router(auth: .disabled)
        let accepted = router.response(
            for: try request(method: "GET", path: "/v1/routes", host: "localhost:9876"),
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        let rejected = router.response(
            for: try request(method: "GET", path: "/v1/routes", host: "evil.com"),
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        let deceptiveLocalhost = router.response(
            for: try request(method: "GET", path: "/v1/routes", host: "localhost.evil.com"),
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(accepted.statusCode == 200)
        #expect(rejected.statusCode == 403)
        #expect(deceptiveLocalhost.statusCode == 403)
        #expect(try decodeJSON(rejected.body)["error"] as? String == "invalid_host")
    }

    @Test
    func debugArtifactsRedactSensitiveBodiesAndUseOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-redaction-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = DebugArtifactRecorder(rootDirectory: root, enabled: true, rawArtifactsEnabled: false)

        let paths = try recorder.record(
            requestID: "redacted",
            routeID: RouteID.typeText.rawValue,
            requestBody: Data(#"{"text":"secret"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )
        let requestJSON = try decodeJSON(Data(contentsOf: paths.requestPath))
        let requestFileMode = try fileMode(at: paths.requestPath)
        let artifactsDirectoryMode = try fileMode(at: paths.directory)

        #expect(requestJSON["text"] as? String == "<redacted len=6>")
        #expect(requestFileMode == 0o600)
        #expect(artifactsDirectoryMode == 0o700)
    }

    @Test
    func readTextResponseBodyIsRedacted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-read-text-redaction-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = DebugArtifactRecorder(rootDirectory: root, enabled: true, rawArtifactsEnabled: false)

        let paths = try recorder.record(
            requestID: "read-text",
            routeID: RouteID.readText.rawValue,
            requestBody: Data(#"{"window":"w"}"#.utf8),
            responseBody: Data(#"{"chunk":{"text":"sensitive"}}"#.utf8)
        )
        let responseJSON = try decodeJSON(Data(contentsOf: paths.responsePath))
        let chunk = try #require(responseJSON["chunk"] as? [String: Any])

        #expect(chunk["text"] as? String == "<redacted len=9>")
    }

    @Test
    func setValueAndPressKeyAreRedactedUnlessRawOverrideIsEnabled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-action-redaction-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = DebugArtifactRecorder(rootDirectory: root, enabled: true, rawArtifactsEnabled: false)

        let setValuePaths = try recorder.record(
            requestID: "set-value",
            routeID: RouteID.setValue.rawValue,
            requestBody: Data(#"{"value":"secret"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )
        let pressKeyPaths = try recorder.record(
            requestID: "press-key",
            routeID: RouteID.pressKey.rawValue,
            requestBody: Data(#"{"key":"command+k"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )
        let rawRecorder = DebugArtifactRecorder(rootDirectory: root, enabled: true, rawArtifactsEnabled: true)
        let rawPaths = try rawRecorder.record(
            requestID: "raw",
            routeID: RouteID.setValue.rawValue,
            requestBody: Data(#"{"value":"visible"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )

        #expect(try decodeJSON(Data(contentsOf: setValuePaths.requestPath))["value"] as? String == "<redacted len=6>")
        #expect(try decodeJSON(Data(contentsOf: pressKeyPaths.requestPath))["key"] as? String == "<redacted len=9>")
        #expect(try decodeJSON(Data(contentsOf: rawPaths.requestPath))["value"] as? String == "visible")
    }

    private func request(method: String, path: String, host: String) throws -> HTTPRequest {
        let data = Data("\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\nContent-Length: 0\r\n\r\n".utf8)
        guard case let .complete(request) = HTTPRequest.parse(data) else {
            throw AgentAPICorrectnessTestError.requestParseFailed
        }
        return request
    }

    private func fileMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}

private func decodeJSON(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private enum AgentAPICorrectnessTestError: Error {
    case requestParseFailed
}

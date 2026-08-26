import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct FindElementsParityTests {
    @Test
    func findElementsRouteIsReadOnlyAndDocumentsExactContract() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.findElements.rawValue }
        )

        #expect(route.method == "POST")
        #expect(route.path == "/v1/find_elements")
        #expect(route.execution.lane == .windowRead)
        let request = try #require(route.request)
        let encodedRequest = try JSONSupport.encoder.encode(
            FindElementsRequest(
                window: "w_fixture",
                role: "button",
                text: "Click me",
                includeMenuBar: true,
                webTraversal: .full,
                maxNodes: 123
            )
        )
        let requestJSON = try #require(
            JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any]
        )
        #expect(Set(request.fields.map(\.name)) == Set(requestJSON.keys))

        let response = FindElementsResponse(
            contractVersion: ContractVersion.current,
            stateToken: "st_fixture",
            interactionToken: "it_fixture",
            window: ResolvedWindowDTO(
                windowID: "w_fixture",
                title: "Fixture",
                bundleID: "com.example.fixture",
                pid: 123,
                launchDate: nil,
                windowNumber: 77,
                frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
                resolutionStrategy: "test"
            ),
            query: FindElementsQueryDTO(role: "button", text: "Click me"),
            matches: [],
            matchCount: 0,
            summary: "No elements matched the query.",
            notes: []
        )
        let data = try JSONSupport.encoder.encode(response)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let responseSchema = route.response
        #expect(Set(responseSchema.fields.map(\.name)) == Set(json.keys))
    }

    @Test
    func findElementsRejectsEmptyQueryBeforeCapture() {
        let state = emptyState()
        let request = FindElementsRequest(window: "w_fixture", role: "  ", text: nil)

        #expect(throws: FindElementsRouteError.invalidRequest(
            "find_elements requires a non-empty role and/or text query."
        )) {
            _ = try FindElementsRouteService.response(from: state, request: request)
        }
    }

    @Test
    func findElementsHTTPRejectsEmptyQueryBeforeWindowLookup() throws {
        let request = try makeRequest(
            body: #"{"window":"not-a-live-window","role":"   "}"#
        )

        let response = Router(auth: .disabled).response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
        let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])

        #expect(response.statusCode == 400)
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("role and/or text") == true)
    }

    private func emptyState() -> GetWindowStateResponse {
        GetWindowStateResponse(
            contractVersion: ContractVersion.current,
            stateToken: "st_fixture",
            interactionToken: "it_fixture",
            window: ResolvedWindowDTO(
                windowID: "w_fixture",
                title: "Fixture",
                bundleID: "com.example.fixture",
                pid: 123,
                launchDate: nil,
                windowNumber: 77,
                frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
                resolutionStrategy: "test"
            ),
            attachedSurfaces: [],
            screenshot: ScreenshotDTO(
                status: "omitted",
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: nil
            ),
            tree: AXPipelineV2TreeDTO(
                nodeCount: 0,
                truncated: false,
                renderedText: "",
                nodes: [],
                lineMappings: [],
                profile: nil
            ),
            menuPresentation: nil,
            focusedElement: FocusedElementDTO(
                index: nil,
                displayRole: nil,
                title: nil,
                description: nil,
                secondaryActions: []
            ),
            selectionSummary: nil,
            backgroundSafety: BackgroundSafetyDTO(
                frontmostBefore: nil,
                frontmostAfter: nil,
                backgroundSafeReadObserved: true,
                backgroundSafeObserved: true
            ),
            performance: ReadPerformanceDTO(
                resolveMs: 1,
                captureMs: 1,
                projectionMs: 0,
                screenshotMs: 0,
                totalMs: 2
            ),
            debug: nil,
            ocr: nil,
            notes: []
        )
    }

    private func makeRequest(body: String) throws -> HTTPRequest {
        let bodyData = Data(body.utf8)
        var data = Data("POST /v1/find_elements HTTP/1.1\r\n".utf8)
        data.append(Data("Host: 127.0.0.1\r\n".utf8))
        data.append(Data("Content-Type: application/json\r\n".utf8))
        data.append(Data("Content-Length: \(bodyData.count)\r\n\r\n".utf8))
        data.append(bodyData)

        switch HTTPRequest.parse(data) {
        case .complete(let request):
            return request
        case .incomplete, .invalid, .tooLarge:
            throw FindElementsTestError.requestParseFailed
        }
    }
}

private enum FindElementsTestError: Error {
    case requestParseFailed
}

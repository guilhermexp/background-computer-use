import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct BackgroundTextSafetyTests {
    @Test
    func textSuccessRequiresTheSameForegroundProcessThroughout() {
        let userApp = ForegroundApplicationSnapshot(pid: 41, bundleID: "com.example.User")
        let targetApp = ForegroundApplicationSnapshot(pid: 52, bundleID: "com.example.Target")

        let preserved = TypeTextBackgroundSafety.evaluate(
            before: userApp,
            beforeDispatch: userApp,
            after: userApp
        )
        #expect(preserved.foregroundPreserved)

        let changed = TypeTextBackgroundSafety.evaluate(
            before: userApp,
            beforeDispatch: targetApp,
            after: targetApp
        )
        #expect(changed.foregroundPreserved == false)
    }

    @Test
    func missingForegroundEvidenceFailsClosed() {
        let userApp = ForegroundApplicationSnapshot(pid: 41, bundleID: "com.example.User")
        let result = TypeTextBackgroundSafety.evaluate(
            before: userApp,
            beforeDispatch: nil,
            after: userApp
        )

        #expect(result.foregroundPreserved == false)
    }

    @Test
    func typeTextRouteOmitsLegacyFocusAssist() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.typeText.rawValue }
        )
        let requestFields = try #require(route.request?.fields)
        let responseFields = route.response.fields

        #expect(requestFields.contains { $0.name == "focusAssistMode" } == false)
        #expect(responseFields.contains { $0.name == "focusAssistMode" } == false)
        #expect(responseFields.contains { $0.name == "backgroundSafety" })
    }

    @Test
    func strictRouterRejectsLegacyFocusAssistField() throws {
        let body = #"{"window":"window-id","text":"hello","focusAssistMode":"focus"}"#
        let request = try makeRequest(method: "POST", path: "/v1/type_text", body: body)

        let response = Router(auth: .disabled).response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        #expect(response.statusCode == 400)
        let json = try #require(
            JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        )
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("focusAssistMode") == true)
    }
}

private func makeRequest(method: String, path: String, body: String) throws -> HTTPRequest {
    let bodyData = Data(body.utf8)
    var request = "\(method) \(path) HTTP/1.1\r\n"
    request += "Host: 127.0.0.1\r\n"
    request += "Content-Type: application/json\r\n"
    request += "Content-Length: \(bodyData.count)\r\n"
    request += "\r\n"
    var data = Data(request.utf8)
    data.append(bodyData)
    switch HTTPRequest.parse(data) {
    case .complete(let parsed):
        return parsed
    case .incomplete, .invalid, .tooLarge:
        throw BackgroundTextSafetyTestError.parseFailed
    }
}

private enum BackgroundTextSafetyTestError: Error {
    case parseFailed
}

@testable import BackgroundComputerUse
import Foundation
import Testing

struct BackgroundTextSafetyTests {
    @Test
    func dispatchedOpaqueUnicodeIsNeverRetrySafe() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: true,
            strategiesAttempted: [.pidUnicode]
        )

        #expect(attempt.retrySafe == false)
    }

    @Test
    func blockedBeforeAnyTransportRemainsRetrySafe() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: nil,
            strategiesAttempted: []
        )

        #expect(attempt.retrySafe)
    }

    @Test
    func opaqueDispatchRemainsAmbiguousAfterForegroundFallback() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: true,
            strategiesAttempted: [.pidUnicode]
        )

        let decision = TypeTextOutcomePolicy.classifyOpaqueDispatch(
            attempt: attempt,
            foregroundPreserved: false
        )

        #expect(decision.classification == .verifierAmbiguous)
        #expect(decision.failureDomain?.rawValue == "verification")
        #expect(decision.summary.contains("reread before continuing"))
        #expect(decision.summary.contains("do not retry blindly"))
        #expect(attempt.strategiesAttempted == [.pidUnicode])
        #expect(attempt.retrySafe == false)
    }

    @Test
    func exactSemanticVerificationWinsAfterForegroundFallback() {
        let decision = TypeTextOutcomePolicy.classifySemanticDispatch(
            exactValueMatch: true,
            exactSelectionMatch: true,
            targetRelocated: false,
            postStateTokenAvailable: false,
            foregroundPreserved: false
        )

        #expect(decision.classification == .success)
        #expect(decision.failureDomain == nil)
    }

    @Test
    func opaqueUnicodeAttemptCannotBecomeRetrySafeWhenPostingFails() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: false,
            strategiesAttempted: [.pidUnicode]
        )

        #expect(attempt.retrySafe == false)
    }

    @Test
    func unicodePreparationRejectsAnUnrelatedThirdAppBeforeWindowServerEffects() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let third = ForegroundApplicationSnapshot(pid: 30, bundleID: "third")

        #expect(BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: original,
            current: third,
            targetPID: 20
        ) == false)
    }

    @Test
    func unicodePreparationAllowsTheOriginalOrExactTargetForeground() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")
        let target = ForegroundApplicationSnapshot(pid: 20, bundleID: "target")

        #expect(BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: original,
            current: original,
            targetPID: target.pid
        ))
        #expect(BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: original,
            current: target,
            targetPID: target.pid
        ))
    }

    @Test
    func textDispatchRejectsMissingForegroundEvidence() {
        let original = ForegroundApplicationSnapshot(pid: 10, bundleID: "user")

        #expect(BackgroundTextPreparation.foregroundAllowsTextDispatch(
            original: original,
            current: nil,
            targetPID: 20
        ) == false)
    }

    @Test
    func attemptedTransportCannotRestoreBeforeVerification() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: false,
            strategiesAttempted: [.pidUnicode]
        )

        #expect(TypeTextOutcomePolicy.canRestoreForeground(
            attempt: attempt,
            verificationCompleted: false
        ) == false)
        #expect(TypeTextOutcomePolicy.canRestoreForeground(
            attempt: attempt,
            verificationCompleted: true
        ))
    }

    @Test
    func blockedBeforeTransportMayRestoreWithoutVerification() {
        let attempt = TypeTextAttemptTelemetry(
            dispatchSucceeded: false,
            strategiesAttempted: []
        )

        #expect(TypeTextOutcomePolicy.canRestoreForeground(
            attempt: attempt,
            verificationCompleted: false
        ))
    }

    @Test
    func backgroundSafetyReportsWhetherForegroundWasPreserved() {
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
    func typeTextRouteDocumentsAdaptiveStrategies() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.typeText.rawValue }
        )
        let responseFields = route.response.fields

        #expect(responseFields.contains { $0.name == "strategiesAttempted" && $0.type == "string[]" })
        #expect(responseFields.contains { $0.name == "fallbackReason" && $0.type == "string | null" })
        #expect(responseFields.contains { $0.name == "performance" && $0.type == "ActionPerformance | null" })
    }

    @Test
    func typeTextRouteDocumentsRetryAndForegroundFallback() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.typeText.rawValue }
        )
        let fields = route.response.fields

        #expect(fields.contains { $0.name == "retrySafe" && $0.type == "boolean" && $0.required })
        #expect(fields.contains {
            $0.name == "foregroundFallbackUsed" && $0.type == "boolean" && $0.required
        })
        #expect(fields.contains {
            $0.name == "foregroundRestored" && $0.type == "boolean" && $0.required
        })
    }

    @Test
    func clickRouteDocumentsPerformanceTelemetry() throws {
        let route = try #require(
            RouteRegistry.publicRoutes().first { $0.id == RouteID.click.rawValue }
        )

        #expect(route.response.fields.contains { field in
            field.name == "performance" && field.type == "ActionPerformance | null"
        })
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
    case let .complete(parsed):
        return parsed
    case .incomplete, .invalid, .tooLarge:
        throw BackgroundTextSafetyTestError.parseFailed
    }
}

private enum BackgroundTextSafetyTestError: Error {
    case parseFailed
}

import Foundation
import Testing
@testable import BackgroundComputerUse

// MARK: - Task 1.3 — Strict request decoding

@Suite
struct StrictRequestDecodingTests {
    @Test
    func pressKeyRejectsUnknownModifiersField() throws {
        let response = try post(
            path: "/v1/press_key",
            body: #"{"window":"w_X","key":"w","modifiers":["command"]}"#
        )

        #expect(response.statusCode == 400)
        let json = try decode(response)
        #expect(json["error"] as? String == "invalid_request")
        let message = try #require(json["message"] as? String)
        #expect(message.contains("modifiers"))
        // Lists the route's accepted fields.
        #expect(message.contains("key"))
        #expect(message.contains("window"))
        let recovery = try #require(json["recovery"] as? [String])
        #expect(recovery.contains { $0.contains("/v1/routes") })
    }

    @Test
    func invalidRequestsDoNotConsumeActionRateLimit() throws {
        let limiter = RuntimeSessionLimiter()
        let router = Router(sessionLimiter: limiter)
        limiter.configure(maxActionsPerSecond: 1)
        let request = try makeRequest(
            method: "POST",
            path: "/v1/press_key",
            body: #"{"window":"w_X","key":"w","modifiers":["command"]}"#
        )

        let first = router.response(for: request, context: RouterContext(baseURL: nil, startedAt: nil))
        let second = router.response(for: request, context: RouterContext(baseURL: nil, startedAt: nil))

        #expect(first.statusCode == 400)
        #expect(second.statusCode == 400)
        let secondJSON = try decode(second)
        #expect(secondJSON["error"] as? String == "invalid_request")
        #expect((secondJSON["message"] as? String)?.contains("modifiers") == true)
    }

    @Test
    func clickRejectsUnknownField() throws {
        let response = try post(
            path: "/v1/click",
            body: #"{"window":"w_X","x":10,"y":10,"bogus":true}"#
        )

        #expect(response.statusCode == 400)
        let json = try decode(response)
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("bogus") == true)
    }

    @Test
    func scrollRejectsUnknownField() throws {
        let response = try post(
            path: "/v1/scroll",
            body: #"{"window":"w_X","target":{"kind":"display_index","value":1},"direction":"down","speed":3}"#
        )

        #expect(response.statusCode == 400)
        let json = try decode(response)
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("speed") == true)
    }

    @Test
    func fullyDocumentedPressKeyRequestHasNoUnknownFields() {
        // Scenario: a request using only documented fields (including optionals) is not rejected
        // for unknown fields. Validated at the schema layer to avoid live AX dispatch.
        let accepted = Set(RouteRegistry.requestFieldNames(for: .pressKey))
        let bodyKeys: Set<String> = [
            "window", "stateToken", "key", "cursor",
            "includeMenuBar", "maxNodes", "imageMode", "confirm", "debug"
        ]
        #expect(bodyKeys.subtracting(accepted).isEmpty)
    }

    @Test
    func everyActionDTOFieldIsDocumentedInRouteRegistry() {
        // Guards against rejecting valid requests: the documented schema must be a superset
        // of the decoder's accepted top-level fields for press_key, click, and scroll.
        #expect(Set(RouteRegistry.requestFieldNames(for: .click)).isSuperset(of: [
            "window", "stateToken", "target", "x", "y", "mode", "clickCount",
            "mouseButton", "cursor", "includeMenuBar", "maxNodes", "imageMode", "debug", "confirm"
        ]))
        #expect(Set(RouteRegistry.requestFieldNames(for: .scroll)).isSuperset(of: [
            "window", "stateToken", "target", "direction", "pages",
            "verificationMode", "cursor", "includeMenuBar", "maxNodes", "imageMode", "debug"
        ]))
    }

    private func post(path: String, body: String) throws -> HTTPResponse {
        let request = try makeRequest(method: "POST", path: path, body: body)
        return Router().response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
    }

    private func decode(_ response: HTTPResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }
}

// MARK: - Task 2.3 — press_key effect verification

@Suite
struct PressKeyVerificationTests {
    @Test
    func effectClassificationMapsTransportAndEffectSignals() {
        #expect(
            PressKeyRouteService.effectClassification(classification: .success, dispatchSucceeded: true) == .success
        )
        #expect(
            PressKeyRouteService.effectClassification(classification: .effectNotVerified, dispatchSucceeded: true)
                == .dispatchedNoObservedEffect
        )
        #expect(
            PressKeyRouteService.effectClassification(classification: .effectNotVerified, dispatchSucceeded: false)
                == .failed
        )
        #expect(
            PressKeyRouteService.effectClassification(classification: .unsupported, dispatchSucceeded: nil) == .failed
        )
    }

    @Test
    func verificationBlockCarriesEffectClassificationAndValueDiff() throws {
        // Integration-style proxy: a key press that changes a focused text field value reports
        // the value diff and is classified as success.
        let evidence = PressKeyVerificationEvidenceDTO(
            preStateToken: "pre",
            postStateToken: "post",
            renderedTextChanged: true,
            focusedElementChanged: false,
            textStateChanged: true,
            selectionSummaryChanged: false,
            visualChangeRatio: 0.2,
            visualChanged: true,
            search: nil,
            selection: nil,
            verificationNotes: ["text value changed"]
        ).withClassification(.success)

        let json = try encode(evidence)
        #expect(json["classification"] as? String == "success")
        #expect(json["postStateToken"] as? String == "post")
        #expect(json["textStateChanged"] as? Bool == true)
    }

    @Test
    func dispatchedWithoutEffectEncodesNonFailingClassification() throws {
        let evidence = PressKeyVerificationEvidenceDTO(
            preStateToken: "pre",
            postStateToken: "post",
            renderedTextChanged: false,
            focusedElementChanged: false,
            textStateChanged: false,
            selectionSummaryChanged: false,
            visualChangeRatio: nil,
            visualChanged: nil,
            search: nil,
            selection: nil,
            verificationNotes: []
        ).withClassification(.dispatchedNoObservedEffect)

        let json = try encode(evidence)
        #expect(json["classification"] as? String == "dispatched_no_observed_effect")
    }

    private func encode(_ value: PressKeyVerificationEvidenceDTO) throws -> [String: Any] {
        let data = try JSONSupport.encoder.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - Task 3.4 — cursor overlay opt-in

@Suite
struct CursorOptInTests {
    @Test
    func actionWithoutCursorRequestRendersNoOverlayEvenWhenGloballyEnabled() {
        #expect(
            AXCursorTargeting.effectiveOptions(requested: nil, options: .visualCursorEnabled).visualCursorEnabled == false
        )
    }

    @Test
    func explicitCursorRequestKeepsConfiguredOptions() {
        let cursor = CursorRequestDTO(id: "agent-1", name: "Agent", color: "#20C46B")
        #expect(
            AXCursorTargeting.effectiveOptions(requested: cursor, options: .visualCursorEnabled).visualCursorEnabled == true
        )
        #expect(
            AXCursorTargeting.effectiveOptions(requested: cursor, options: .visualCursorDisabled).visualCursorEnabled == false
        )
    }

    @Test
    func prepareClickWithoutCursorSkipsSessionAndAnimation() {
        let target = AXActionTargetSnapshot(
            displayIndex: 1,
            projectedIndex: 1,
            primaryCanonicalIndex: 1,
            canonicalIndices: [1],
            displayRole: "button",
            rawRole: "AXButton",
            rawSubrole: nil,
            title: "Test",
            description: nil,
            identifier: nil,
            placeholder: nil,
            url: nil,
            nodeID: "node-1",
            refetchFingerprint: "fingerprint-1",
            refetchLocator: nil,
            projectedValueKind: nil,
            projectedValuePreview: nil,
            projectedValueLength: nil,
            projectedValueTruncated: false,
            isValueSettable: false,
            supportsValueSet: false,
            isTextEntry: false,
            isFocused: false,
            isSelected: false,
            parameterizedAttributes: [],
            frameAppKit: RectDTO(x: 100, y: 100, width: 80, height: 40),
            activationPointAppKit: nil,
            suggestedInteractionPointAppKit: PointDTO(x: 120, y: 120)
        )
        let window = ResolvedWindowDTO(
            windowID: "window-id",
            title: "Window",
            bundleID: "com.example.Test",
            pid: 123,
            launchDate: nil,
            windowNumber: 456,
            frameAppKit: RectDTO(x: 80, y: 80, width: 400, height: 300),
            resolutionStrategy: "test"
        )

        let cursor = AXCursorTargeting.prepareClick(
            requested: nil,
            target: target,
            window: window,
            options: .visualCursorEnabled
        )

        #expect(!cursor.moved)
        #expect(cursor.moveDurationMs == nil)
        #expect(cursor.movement == "disabled")
        #expect(cursor.session.id == "visual-cursor-disabled")
    }

    @Test
    func cursorProfileHasNoImplicitCodexDefault() {
        #expect(CursorProfile.defaultAppearance.id != "codex")
        #expect(CursorProfile.defaultAppearance.name != "Codex")
    }
}

// MARK: - Task 4.3 — list_windows dedup

@Suite
struct WindowListDedupTests {
    private struct StubWindow {
        let role: String?
        let windowNumber: Int
    }

    @Test
    func desktopScrollAreaIsExcludedAndDuplicateWindowIDsCollapse() {
        // Regression for the Finder case: a real AXWindow plus an AXScrollArea sharing the same
        // backing window number, and a second AX element duplicating the real window.
        let records = [
            StubWindow(role: "AXWindow", windowNumber: 1001),
            StubWindow(role: "AXScrollArea", windowNumber: 1001),
            StubWindow(role: "AXWindow", windowNumber: 1001),
            StubWindow(role: "AXWindow", windowNumber: 1002)
        ]

        let result = WindowListFilter.realUniqueWindows(
            records,
            role: { $0.role },
            windowNumber: { $0.windowNumber }
        )

        #expect(result.kept.map(\.windowNumber) == [1001, 1002])
        #expect(result.excludedNonWindow == 1)
        #expect(result.excludedDuplicate == 1)
    }

    @Test
    func windowIDsAreUniquePerResponse() {
        let records = [
            StubWindow(role: "AXWindow", windowNumber: 5),
            StubWindow(role: "AXWindow", windowNumber: 5),
            StubWindow(role: "AXWindow", windowNumber: 6)
        ]

        let result = WindowListFilter.realUniqueWindows(
            records,
            role: { $0.role },
            windowNumber: { $0.windowNumber }
        )

        let numbers = result.kept.map(\.windowNumber)
        #expect(numbers == [5, 6])
        #expect(Set(numbers).count == numbers.count)
    }
}

private func makeRequest(method: String, path: String, body: String = "") throws -> HTTPRequest {
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
        Issue.record("Request parser rejected the hardened API test fixture")
        throw HardenedAgentAPITestError.parseFailed
    }
}

private enum HardenedAgentAPITestError: Error {
    case parseFailed
}

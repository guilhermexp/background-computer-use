import AppKit
import Testing
@testable import BackgroundComputerUse

@Suite
struct CursorFeedbackModelTests {
    @Test
    func streamingAppendAccumulatesTextAndFinishKeepsReadableDwell() {
        var feedback = CursorFeedbackState()
        let start = CursorFeedbackUpdate(
            operation: .update,
            state: .streaming,
            message: "Opening",
            append: false,
            now: 10
        )
        feedback.apply(start)

        let append = CursorFeedbackUpdate(
            operation: .append,
            state: nil,
            message: " Chrome",
            append: true,
            now: 11
        )
        feedback.apply(append)

        #expect(feedback.message == "Opening Chrome")
        #expect(feedback.state == .streaming)
        #expect(feedback.isActive(at: 11.5))

        let finish = CursorFeedbackUpdate(
            operation: .finish,
            state: nil,
            message: "Chrome ready",
            append: false,
            now: 12,
            dwell: 1.25
        )
        feedback.apply(finish)

        #expect(feedback.message == "Chrome ready")
        #expect(feedback.state == .idle)
        #expect(feedback.isActive(at: 13.0))
        #expect(!feedback.isActive(at: 13.4))
    }

    @Test
    func hideClearsFeedbackImmediately() {
        var feedback = CursorFeedbackState()
        feedback.apply(
            CursorFeedbackUpdate(
                operation: .update,
                state: .waiting,
                message: "Waiting",
                append: false,
                now: 5
            )
        )

        feedback.apply(CursorFeedbackUpdate(operation: .hide, now: 6))

        #expect(feedback.message == nil)
        #expect(feedback.state == .idle)
        #expect(!feedback.isActive(at: 6))
    }

    @Test
    func activePredicateIncludesStreamingFeedbackAndFinishedDwell() {
        var feedback = CursorFeedbackState()
        feedback.apply(
            CursorFeedbackUpdate(
                operation: .update,
                state: .streaming,
                message: "Reading logs",
                append: false,
                now: 1
            )
        )

        #expect(CursorSessionActivity(hasActiveFeedback: feedback.isActive(at: 30)).isActive)

        feedback.apply(
            CursorFeedbackUpdate(
                operation: .finish,
                state: nil,
                message: nil,
                append: false,
                now: 30,
                dwell: 2
            )
        )
        #expect(CursorSessionActivity(hasActiveFeedback: feedback.isActive(at: 31)).isActive)
        #expect(!CursorSessionActivity(hasActiveFeedback: feedback.isActive(at: 33.1)).isActive)
    }

    @Test
    func feedbackTextIsBounded() throws {
        let raw = String(repeating: "prefix ", count: 80) + "latest visible words"
        let bounded = try #require(CursorFeedbackLayout.boundedMessage(raw))

        #expect(bounded.count == CursorFeedbackLayout.maxMessageCharacters)
        #expect(bounded.hasPrefix("... "))
        #expect(bounded.hasSuffix("latest visible words"))
    }

    @Test
    func streamingAppendKeepsLatestVisibleTextWhenBounded() throws {
        var feedback = CursorFeedbackState()
        feedback.apply(
            CursorFeedbackUpdate(
                operation: .update,
                state: .streaming,
                message: String(repeating: "context ", count: 80),
                now: 1
            )
        )

        feedback.apply(
            CursorFeedbackUpdate(
                operation: .append,
                message: "agora estou vendo a pagina de projetos e vou conferir a mudanca visual",
                now: 2
            )
        )

        let message = try #require(feedback.message)
        #expect(message.count == CursorFeedbackLayout.maxMessageCharacters)
        #expect(message.hasPrefix("... "))
        #expect(message.hasSuffix("vou conferir a mudanca visual"))
    }
}

@Suite
struct CursorFeedbackRenderingTests {
    @Test
    func overlayRendererDrawsFeedbackBubbleNearCursor() throws {
        let image = try #require(renderSnapshot(includeFeedback: true))
        let bitmap = NSBitmapImageRep(cgImage: image)

        #expect(nonBlackPixelCount(in: CGRect(x: 96, y: 82, width: 150, height: 48), bitmap: bitmap) > 40)
    }

    @Test
    func overlayRendererClampsFeedbackBubbleInsideContextNearEdges() throws {
        let image = try #require(renderSnapshot(
            includeFeedback: true,
            position: CGPoint(x: 248, y: 145),
            message: "Vou comparar o canto da tela sem cobrir o alvo visual"
        ))
        let bitmap = NSBitmapImageRep(cgImage: image)

        #expect(nonBlackPixelCount(in: CGRect(x: 12, y: 12, width: 220, height: 136), bitmap: bitmap) > 40)
    }

    @Test
    func screenshotCompositorExcludesFeedbackByDefault() throws {
        let baseImage = try #require(makeSolidImage(width: 240, height: 160, color: .black))
        let windowFrame = CGRect(x: 10, y: 20, width: 120, height: 80)
        let snapshot = makeSnapshot(feedback: CursorFeedbackSnapshot(
            state: .streaming,
            message: "Vou conferir a mudanca visual",
            opacity: 1,
            target: nil,
            renderInModelFacingScreenshots: false
        ))

        let compositedImage = try #require(
            CursorScreenshotCompositor.compositedImage(
                baseImage: baseImage,
                windowFrameAppKit: windowFrame,
                snapshots: [snapshot]
            )
        )
        let bitmap = NSBitmapImageRep(cgImage: compositedImage)

        let expectedCursorPoint = CursorScreenshotCompositor.modelFacingPoint(
            for: snapshot.position,
            in: windowFrame,
            modelImageSize: CGSize(width: 240, height: 160)
        )
        #expect(nonBlackPixelCount(in: CGRect(x: expectedCursorPoint.x - 8, y: expectedCursorPoint.y - 8, width: 18, height: 18), bitmap: bitmap) > 10)
        #expect(nonBlackPixelCount(in: CGRect(x: expectedCursorPoint.x + 25, y: expectedCursorPoint.y - 8, width: 150, height: 48), bitmap: bitmap) == 0)
    }

    private func renderSnapshot(
        includeFeedback: Bool,
        position: CGPoint = CGPoint(x: 80, y: 80),
        message: String = "Vou conferir a mudanca visual"
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 260,
            height: 160,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 260, height: 160))
        context.clip(to: CGRect(x: 0, y: 0, width: 260, height: 160))

        let feedback = includeFeedback
            ? CursorFeedbackSnapshot(
                state: .streaming,
                message: message,
                opacity: 1,
                target: nil,
                renderInModelFacingScreenshots: true
            )
            : nil
        CursorRenderer.draw(makeSnapshot(position: position, feedback: feedback), in: context)
        return context.makeImage()
    }

    private func makeSnapshot(
        position: CGPoint = CGPoint(x: 80, y: 80),
        feedback: CursorFeedbackSnapshot?
    ) -> CursorSnapshot {
        let accent = CursorAccentPalette.derive(from: NSColor.presenceCursorColor(hex: "#00C2C7"))
        return CursorSnapshot(
            cursorID: "agent",
            attachedWindowNumber: 11,
            attachedWindowLevelRawValue: 0,
            position: position,
            angle: CursorMotionConstants.arrowHomeAngle,
            scale: 1,
            alpha: 1,
            glyph: .arrow,
            previousGlyph: nil,
            morphProgress: 1,
            isPressed: false,
            accent: accent,
            baseColor: accent.fill,
            pivotLocal: CursorPivotKind.tip.pathPoint,
            labelText: "",
            labelAlpha: 0,
            labelScale: 1,
            trailHistories: [],
            trailVisible: false,
            caretPhase: 0,
            anticipationTilt: 0,
            effects: [],
            feedback: feedback
        )
    }

    private func makeSolidImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func nonBlackPixelCount(in region: CGRect, bitmap: NSBitmapImageRep) -> Int {
        let minX = max(Int(region.minX.rounded(.down)), 0)
        let maxX = min(Int(region.maxX.rounded(.up)), bitmap.pixelsWide)
        let minY = max(Int(region.minY.rounded(.down)), 0)
        let maxY = min(Int(region.maxY.rounded(.up)), bitmap.pixelsHigh)
        guard minX < maxX, minY < maxY else { return 0 }

        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0 || color.greenComponent > 0 || color.blueComponent > 0 {
                    count += 1
                }
            }
        }
        return count
    }
}

@Suite(.serialized)
struct CursorFeedbackRouteTests {
    /// Serializes against every other cursor suite and clears runtime state.
    private let runtime = CursorRuntimeTestScope()

    @Test
    func routeRegistryDocumentsCursorFeedbackRoute() throws {
        #expect(RouteID.allCases.contains(.cursorFeedback))
        let route = RouteRegistry.descriptor(for: .cursorFeedback)

        #expect(route.method == "POST")
        #expect(route.path == "/v1/cursor_feedback")
        #expect(RouteRegistry.requestFieldNames(for: .cursorFeedback).contains("operation"))
        #expect(RouteRegistry.requestFieldNames(for: .cursorFeedback).contains("message"))
        #expect(RouteRegistry.requestFieldNames(for: .cursorFeedback).contains("cursor"))
    }

    @Test
    func cursorFeedbackRejectsUnknownField() throws {
        let response = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"update","message":"Checking","bogus":true}"#
        )

        #expect(response.statusCode == 400)
        let json = try decode(response)
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("bogus") == true)
    }

    @Test
    func cursorFeedbackRejectsPartialCoordinateAsInvalidRequest() throws {
        let response = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"point","message":"Deploy logs","x":10}"#
        )

        #expect(response.statusCode == 400)
        let json = try decode(response)
        #expect(json["error"] as? String == "invalid_request")
        #expect((json["message"] as? String)?.contains("coordinates") == true)
    }

    @Test
    func cursorFeedbackUpdateUsesDefaultAgentAndDefersWithoutWindowAttachment() throws {
        let response = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"update","state":"streaming","message":"Vou comparar o que mudou na tela."}"#
        )

        #expect(response.statusCode == 200)
        let json = try decode(response)
        #expect(json["ok"] as? Bool == true)
        #expect(json["state"] as? String == "streaming")
        #expect(json["message"] as? String == "Vou comparar o que mudou na tela.")
        #expect(json["attachment"] as? String == "deferred")
        #expect(((json["warnings"] as? [String]) ?? []).contains { $0.contains("deferred") })
        let cursor = try #require(json["cursor"] as? [String: Any])
        #expect(cursor["id"] as? String == "agent")
    }

    @Test
    func cursorFeedbackExplicitLanesRemainIsolated() throws {
        let firstID = "route-feedback-isolation-first"
        let secondID = "route-feedback-isolation-second"

        _ = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"update","state":"streaming","message":"First lane","cursor":{"id":"\#(firstID)"}}"#
        )
        _ = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"update","state":"streaming","message":"Second lane","cursor":{"id":"\#(secondID)"}}"#
        )

        #expect(CursorRuntime.feedbackSnapshot(cursorID: firstID)?.message == "First lane")
        #expect(CursorRuntime.feedbackSnapshot(cursorID: secondID)?.message == "Second lane")
    }

    @Test
    func cursorFeedbackAppendAndFinishReturnAccumulatedText() throws {
        let cursorID = "route-feedback-append-test"
        _ = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"update","state":"streaming","message":"Opening","cursor":{"id":"\#(cursorID)"}}"#
        )
        let append = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"append","message":" Chrome","cursor":{"id":"\#(cursorID)"}}"#
        )
        let appendJSON = try decode(append)
        #expect(appendJSON["message"] as? String == "Opening Chrome")

        let finish = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"finish","message":"Chrome ready","cursor":{"id":"\#(cursorID)"}}"#
        )
        let finishJSON = try decode(finish)
        #expect(finishJSON["state"] as? String == "idle")
        #expect(finishJSON["message"] as? String == "Chrome ready")
    }

    @Test
    func cursorFeedbackPointWithoutWindowDefersVisualAnimation() throws {
        let response = try post(
            path: "/v1/cursor_feedback",
            body: #"{"operation":"point","message":"Deploy logs","x":-99999,"y":-99999,"dwellMs":600000,"cursor":{"id":"route-feedback-point-test"}}"#
        )

        #expect(response.statusCode == 200)
        let json = try decode(response)
        #expect(json["state"] as? String == "pointing")
        #expect(json["attachment"] as? String == "deferred")
        #expect(json["clamped"] as? Bool == true)
        #expect(json["plannedDurationMs"] == nil || json["plannedDurationMs"] is NSNull)
        #expect(json["targetPointAppKit"] != nil)
        #expect(((json["warnings"] as? [String]) ?? []).contains { $0.contains("deferred") })
    }

    private func post(path: String, body: String) throws -> HTTPResponse {
        let request = try makeFeedbackRequest(method: "POST", path: path, body: body)
        return Router(auth: .disabled).response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )
    }

    private func decode(_ response: HTTPResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private func makeFeedbackRequest(method: String, path: String, body: String = "") throws -> HTTPRequest {
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
            Issue.record("Request parser rejected the cursor feedback API test fixture")
            throw CursorFeedbackRouteTestError.parseFailed
        }
    }

    private enum CursorFeedbackRouteTestError: Error {
        case parseFailed
    }
}

@Suite(.serialized)
struct CursorFeedbackActionIntegrationTests {
    private let runtime = CursorRuntimeTestScope()

    @Test
    func pressKeyActionPreservesVisibleNarrationInsteadOfActionLabel() {
        let cursorID = "action-feedback-press-key-test"
        let publicNarration = "Vou testar este atalho e comparar a tela depois."
        _ = CursorRuntime.updateFeedback(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            update: CursorFeedbackUpdate(
                operation: .update,
                state: .streaming,
                message: publicNarration,
                now: CACurrentMediaTime()
            ),
            anchorPoint: CGPoint(x: 100, y: 100)
        )

        let cursor = AXCursorTargeting.preparePressKey(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            window: testWindow(windowNumber: 9981),
            keyLabel: "Esc",
            options: .visualCursorEnabled
        )

        let actionFeedback = CursorRuntime.feedbackSnapshot(cursorID: cursorID)
        #expect(actionFeedback?.state == .streaming)
        #expect(actionFeedback?.message == publicNarration)

        AXCursorTargeting.finishPressKey(cursor: cursor)
        sleepRunLoop(0.45)

        #expect(CursorRuntime.feedbackSnapshot(cursorID: cursorID)?.message == publicNarration)
    }

    @Test
    func windowAnchoredActionKeepsExistingVisibleNarration() {
        let cursorID = "action-feedback-window-motion-test"
        let windowNumber = 9983
        let publicNarration = "A janela vai mudar de posicao; estou observando o resultado visual."

        CursorRuntime.snap(
            to: CGPoint(x: 140, y: 140),
            attachedWindowNumber: windowNumber,
            cursorID: cursorID
        )
        _ = CursorRuntime.updateFeedback(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            update: CursorFeedbackUpdate(
                operation: .update,
                state: .streaming,
                message: publicNarration,
                now: CACurrentMediaTime()
            ),
            anchorPoint: CGPoint(x: 140, y: 140)
        )
        CursorRuntime.beginActionFeedback(
            cursorID: cursorID,
            attachedWindowNumber: windowNumber
        )

        let actionFeedback = CursorRuntime.feedbackSnapshot(cursorID: cursorID)
        #expect(actionFeedback?.state == .streaming)
        #expect(actionFeedback?.message == publicNarration)
        #expect(CursorRuntime.snapshots(forWindowNumber: windowNumber).contains { snapshot in
            snapshot.cursorID == cursorID && snapshot.feedback?.message == publicNarration
        })

        CursorRuntime.finishActionFeedback(cursorID: cursorID)

        #expect(CursorRuntime.feedbackSnapshot(cursorID: cursorID)?.message == publicNarration)
    }

    @Test
    func pointingFeedbackIsInterruptedByNewActionWithoutActionLabel() {
        let cursorID = "action-feedback-pointing-interrupt-test"
        _ = CursorRuntime.updateFeedback(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            update: CursorFeedbackUpdate(
                operation: .point,
                state: .pointing,
                message: "Deploy logs",
                now: CACurrentMediaTime(),
                dwell: 600,
                target: CGPoint(x: 120, y: 120)
            ),
            anchorPoint: CGPoint(x: 120, y: 120)
        )

        #expect(CursorRuntime.feedbackSnapshot(cursorID: cursorID)?.state == .pointing)

        let cursor = AXCursorTargeting.preparePressKey(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            window: testWindow(windowNumber: 9984),
            keyLabel: "Esc",
            options: .visualCursorEnabled
        )

        #expect(CursorRuntime.feedbackSnapshot(cursorID: cursorID) == nil)

        AXCursorTargeting.finishPressKey(cursor: cursor)
    }

    @Test
    func disabledCursorActionDoesNotCreateFeedback() {
        let cursorID = "action-feedback-disabled-test"
        let cursor = AXCursorTargeting.preparePressKey(
            requested: CursorRequestDTO(id: cursorID, name: "Agent", color: "#0095A1"),
            window: testWindow(windowNumber: 9982),
            keyLabel: "Esc",
            options: .visualCursorDisabled
        )

        #expect(cursor.movement == "disabled")
        #expect(CursorRuntime.feedbackSnapshot(cursorID: cursorID) == nil)
    }

    private func testWindow(windowNumber: Int) -> ResolvedWindowDTO {
        ResolvedWindowDTO(
            windowID: "window-\(windowNumber)",
            title: "Window",
            bundleID: "com.example.Test",
            pid: 123,
            launchDate: nil,
            windowNumber: windowNumber,
            frameAppKit: RectDTO(x: 80, y: 80, width: 400, height: 300),
            resolutionStrategy: "test"
        )
    }
}

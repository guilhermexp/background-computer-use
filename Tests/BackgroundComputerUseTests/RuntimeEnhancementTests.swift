import AppKit
@testable import BackgroundComputerUse
import Foundation
import Testing

struct RuntimeEnhancementTests {
    @Test
    func safetyPolicyRequiresConfirmationForDestructiveLabels() {
        let decision = RuntimeSafetyPolicy.evaluateLabel("Delete deployment", confirmed: false)

        #expect(decision.blocked)
        #expect(decision.reason?.contains("Delete deployment") == true)
        #expect(!RuntimeSafetyPolicy.evaluateLabel("Delete deployment", confirmed: true).blocked)
        #expect(!RuntimeSafetyPolicy.evaluateLabel("View logs", confirmed: false).blocked)
    }

    @Test
    func safetyPolicyRequiresConfirmationBeforeClearingExistingValues() {
        let decision = RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "existing",
            newValue: "",
            confirmed: false
        )

        #expect(decision.blocked)
        #expect(!RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "existing",
            newValue: "",
            confirmed: true
        ).blocked)
        #expect(!RuntimeSafetyPolicy.evaluateValueChange(
            currentValue: "",
            newValue: "",
            confirmed: false
        ).blocked)
    }

    @Test
    func waitConditionMatchesRoleLabelAndValue() {
        let node = WaitForMatcherNode(
            role: "button",
            title: "Deploy",
            description: nil,
            valuePreview: nil
        )

        #expect(WaitForMatcher.matches(
            node,
            role: "button",
            label: "dep",
            valueContains: nil
        ))
        #expect(!WaitForMatcher.matches(
            node,
            role: "text field",
            label: "dep",
            valueContains: nil
        ))
    }

    @Test
    func waitConditionMatchesWindowTitleURLAndRenderedText() {
        let state = AXPipelineV2Response(
            contractVersion: ContractVersion.current,
            stateToken: "token",
            interactionToken: "interaction",
            window: ResolvedWindowDTO(
                windowID: "window",
                title: "Studio - Deployments",
                bundleID: "com.example.app",
                pid: 123,
                launchDate: nil,
                windowNumber: 42,
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
                nodeCount: 1,
                truncated: false,
                renderedText: "Deploy completed successfully",
                nodes: [
                    AXPipelineV2SurfaceNodeDTO(
                        index: 0,
                        displayIndex: 1,
                        projectedIndex: 0,
                        parentIndex: nil,
                        depth: 0,
                        primaryCanonicalIndex: 0,
                        canonicalIndices: [0],
                        childIndices: [],
                        displayRole: "link",
                        rawRole: "AXLink",
                        rawSubrole: nil,
                        title: "Production",
                        description: nil,
                        help: nil,
                        identifier: nil,
                        domIdentifier: nil,
                        url: "https://xperience-studio.com/dashboard/home",
                        nodeID: nil,
                        identity: nil,
                        refetch: nil,
                        refetchFingerprint: nil,
                        value: nil,
                        valueKind: nil,
                        isValueSettable: nil,
                        flags: [],
                        secondaryActions: [],
                        secondaryActionBindings: nil,
                        affordances: nil,
                        availableActions: nil,
                        curatedSecondaryActions: nil,
                        curatedAvailableActions: nil,
                        parameterizedAttributes: nil,
                        frameAppKit: nil,
                        activationPointAppKit: nil,
                        suggestedInteractionPointAppKit: nil,
                        childCount: 0,
                        collectionInfo: nil,
                        interactionTraits: nil,
                        profileHint: nil,
                        transformNotes: []
                    ),
                ],
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
                backgroundSafeReadObserved: nil,
                backgroundSafeObserved: nil
            ),
            notes: []
        )

        #expect(WaitForMatcher.conditionMatches(
            state: state,
            role: nil,
            label: nil,
            valueContains: nil,
            windowTitleContains: "deploy",
            windowTitleChanged: false,
            baselineWindowTitle: nil,
            urlContains: "dashboard",
            textContains: "completed"
        ))
        #expect(WaitForMatcher.conditionMatches(
            state: state,
            role: nil,
            label: nil,
            valueContains: nil,
            windowTitleContains: nil,
            windowTitleChanged: true,
            baselineWindowTitle: "Studio - Builds",
            urlContains: nil,
            textContains: nil
        ))
        #expect(!WaitForMatcher.conditionMatches(
            state: state,
            role: nil,
            label: nil,
            valueContains: nil,
            windowTitleContains: nil,
            windowTitleChanged: true,
            baselineWindowTitle: "Studio - Deployments",
            urlContains: nil,
            textContains: nil
        ))
    }

    @Test
    func annotationBuilderMapsInteractiveNodesIntoModelFacingScreenshot() {
        let state = makeAnnotationState(nodes: [
            annotationNode(
                displayIndex: 8,
                displayRole: "button",
                title: "Deploy",
                frame: RectDTO(x: 100, y: 400, width: 200, height: 80),
                point: PointDTO(x: 200, y: 440)
            ),
            annotationNode(
                displayIndex: 9,
                displayRole: "text",
                title: "Static label",
                frame: RectDTO(x: 100, y: 300, width: 200, height: 40),
                point: PointDTO(x: 200, y: 320)
            ),
            annotationNode(
                displayIndex: 10,
                displayRole: "standard window",
                title: "Window root",
                frame: RectDTO(x: 0, y: 0, width: 800, height: 600),
                point: PointDTO(x: 400, y: 300)
            ),
        ])

        let result = WindowAnnotationBuilder.marks(
            from: state,
            maxMarks: 10,
            includeStaticText: false
        )

        #expect(!result.truncated)
        #expect(result.marks.count == 1)
        let mark = result.marks[0]
        #expect(mark.markID == 1)
        #expect(mark.displayIndex == 8)
        #expect(mark.target?.displayIndex == 8)
        #expect(abs(mark.point.x - 100) < 0.01)
        #expect(abs(mark.point.y - 80) < 0.01)
        #expect(abs((mark.rect?.x ?? -1) - 50) < 0.01)
        #expect(abs((mark.rect?.y ?? -1) - 60) < 0.01)
        #expect(abs((mark.rect?.width ?? -1) - 100) < 0.01)
        #expect(abs((mark.rect?.height ?? -1) - 40) < 0.01)
    }

    @Test
    func annotationBuilderCanIncludeStaticTextAndTruncateMarks() {
        let state = makeAnnotationState(nodes: [
            annotationNode(
                displayIndex: 1,
                displayRole: "button",
                title: "Deploy",
                frame: RectDTO(x: 20, y: 450, width: 100, height: 40),
                point: PointDTO(x: 70, y: 470)
            ),
            annotationNode(
                displayIndex: 2,
                displayRole: "text",
                title: "Ready",
                frame: RectDTO(x: 20, y: 400, width: 100, height: 30),
                point: PointDTO(x: 70, y: 415)
            ),
        ])

        let result = WindowAnnotationBuilder.marks(
            from: state,
            maxMarks: 1,
            includeStaticText: true
        )

        #expect(result.truncated)
        #expect(result.marks.count == 1)
    }

    @Test
    func annotationRendererWritesAnnotatedPNG() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-annotation-renderer-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.png")
        try makePNG(width: 120, height: 80).write(to: source)

        let baseImage = ScreenshotImageDTO(
            imagePath: source.path,
            imageBase64: nil,
            mimeType: "image/png",
            pixelWidth: 120,
            pixelHeight: 80,
            coordinateOrigin: .topLeft,
            coordinateSpace: .modelFacingScreenshot,
            captureKind: "test"
        )
        let mark = try WindowAnnotationMarkDTO(
            markID: 1,
            displayIndex: 4,
            nodeID: nil,
            refetchFingerprint: nil,
            target: .displayIndex(4),
            role: "button",
            title: "Deploy",
            description: nil,
            valuePreview: nil,
            point: PointDTO(x: 50, y: 30),
            rect: RectDTO(x: 20, y: 20, width: 60, height: 30),
            source: "test"
        )

        let rendered = try #require(WindowAnnotationRenderer.render(
            baseImagePath: source.path,
            baseImage: baseImage,
            marks: [mark],
            windowID: "window",
            stateToken: "state",
            imageMode: .path
        ))

        let path = try #require(rendered.imagePath)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(rendered.pixelWidth == 120)
        #expect(rendered.pixelHeight == 80)
        #expect(rendered.captureKind == "model-facing-window-annotation")
    }

    @Test
    func textChunkerReportsBoundedSlices() throws {
        let chunk = try TextChunker.chunk("abcdef", offset: 2, length: 3)

        #expect(chunk.text == "cde")
        #expect(chunk.totalLength == 6)
        #expect(chunk.rangeStart == 2)
        #expect(chunk.rangeEnd == 5)
        #expect(chunk.truncated)
    }

    @Test
    func textSelectionPlannerFindsRequestedOccurrence() throws {
        let range = try TextSelectionPlanner.range(
            in: "alpha beta alpha",
            query: "alpha",
            occurrence: 2,
            position: .select
        )

        #expect(range.location == 11)
        #expect(range.length == 5)
    }

    @Test
    func debugArtifactRecorderWritesRequestAndResponseMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-debug-artifact-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = DebugArtifactRecorder(
            rootDirectory: directory,
            enabled: true
        )
        let artifact = try recorder.record(
            requestID: "req-1",
            routeID: "click",
            requestBody: Data(#"{"window":"w1"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )

        #expect(FileManager.default.fileExists(atPath: artifact.requestPath.path))
        #expect(FileManager.default.fileExists(atPath: artifact.responsePath.path))
    }

    @Test
    func ocrAnchorSummaryKeepsHighConfidenceUsefulAnchors() {
        let summary = OCRAnchorSummaryBuilder.summary(
            lines: [
                .init(text: "Deploy", confidence: 0.97, box: .init(x: 10, y: 20, width: 60, height: 20)),
                .init(text: "x", confidence: 0.99, box: .init(x: 1, y: 1, width: 5, height: 5)),
                .init(text: "Logs", confidence: 0.93, box: .init(x: 90, y: 20, width: 40, height: 20)),
            ],
            interactionToken: "it_summary_filter",
            maxAnchors: 2
        )

        #expect(summary.anchors.map(\.text) == ["Deploy", "Logs"])
        #expect(summary.promptHint.contains(#""Deploy" at (40, 30)"#) == true)
    }

    @Test
    func ocrAnchorSummaryDefaultIncludesContentBelowBrowserChrome() {
        let browserChrome = (0 ..< 10).map { index in
            OCRLineDTO(
                text: "Browser item \(index)",
                confidence: 0.99,
                box: .init(x: 10, y: Double(index * 12), width: 100, height: 10)
            )
        }
        let summary = OCRAnchorSummaryBuilder.summary(
            lines: browserChrome + [
                .init(
                    text: "Smoke input",
                    confidence: 0.99,
                    box: .init(x: 20, y: 180, width: 120, height: 20)
                ),
            ],
            interactionToken: "it_browser_content"
        )

        #expect(summary.anchors.contains { $0.text == "Smoke input" })
    }

    @Test
    func ocrAnchorSummaryCarriesStableClickTargets() throws {
        let lines = [
            OCRLineDTO(
                text: "Update Server",
                confidence: 0.99,
                box: .init(x: 100, y: 200, width: 120, height: 32)
            ),
        ]

        let first = OCRAnchorSummaryBuilder.summary(lines: lines, interactionToken: "it_ABC")
        let second = OCRAnchorSummaryBuilder.summary(lines: lines, interactionToken: "it_ABC")
        let anchor = try #require(first.anchors.first)

        #expect(first.status == .success)
        #expect(anchor.id == second.anchors.first?.id)
        #expect(anchor.box == lines[0].box)
        #expect(anchor.target.kind == .ocrAnchor)
        #expect(anchor.target.value == anchor.id)
    }

    @Test
    func ocrAnchorSummaryReportsNoTextExplicitly() {
        let summary = OCRAnchorSummaryBuilder.summary(lines: [], interactionToken: "it_ABC")

        #expect(summary.status == .noText)
        #expect(summary.anchors.isEmpty)
        #expect(summary.matchesCount == 0)
    }

    @Test
    func ocrActionTargetDecodesAndRejectsEmptyValues() throws {
        let decoded = try JSONDecoder().decode(
            ActionTargetRequestDTO.self,
            from: Data(#"{"kind":"ocr_anchor","value":"ocr_ABC"}"#.utf8)
        )
        #expect(decoded.kind == .ocrAnchor)
        #expect(decoded.value == "ocr_ABC")

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ActionTargetRequestDTO.self,
                from: Data(#"{"kind":"ocr_anchor","value":"  "}"#.utf8)
            )
        }
    }

    @Test
    func interactionTokenIgnoresRenderedTextButTracksTargetGeometry() {
        let firstNode = annotationNode(
            displayIndex: 1,
            displayRole: "button",
            title: "Clock 10:00",
            frame: RectDTO(x: 20, y: 40, width: 120, height: 32),
            point: PointDTO(x: 80, y: 56),
            refetchFingerprint: "button|Clock 10:00"
        )
        let secondNode = annotationNode(
            displayIndex: 1,
            displayRole: "button",
            title: "Clock 10:01",
            frame: RectDTO(x: 20, y: 40, width: 120, height: 32),
            point: PointDTO(x: 80, y: 56),
            refetchFingerprint: "button|Clock 10:01"
        )
        let movedNode = annotationNode(
            displayIndex: 1,
            displayRole: "button",
            title: "Clock 10:01",
            frame: RectDTO(x: 28, y: 40, width: 120, height: 32),
            point: PointDTO(x: 88, y: 56),
            refetchFingerprint: "button|Clock 10:01"
        )
        let tree: (AXPipelineV2SurfaceNodeDTO, String) -> AXPipelineV2TreeDTO = { node, renderedText in
            AXPipelineV2TreeDTO(
                nodeCount: 1,
                truncated: false,
                renderedText: renderedText,
                nodes: [node],
                lineMappings: [],
                profile: "default"
            )
        }
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

        let first = InteractionToken.make(
            windowID: "window",
            title: "Test",
            frame: frame,
            tree: tree(firstNode, "[1] Clock 10:00"),
            pixelWidth: 800,
            pixelHeight: 600
        )
        let second = InteractionToken.make(
            windowID: "window",
            title: "Test",
            frame: frame,
            tree: tree(secondNode, "[1] Clock 10:01"),
            pixelWidth: 800,
            pixelHeight: 600
        )
        let moved = InteractionToken.make(
            windowID: "window",
            title: "Test",
            frame: frame,
            tree: tree(movedNode, "[1] Clock 10:01"),
            pixelWidth: 800,
            pixelHeight: 600
        )

        #expect(first == second)
        #expect(first != moved)
        #expect(first.hasPrefix("it_"))
    }

    @Test
    func sessionLimiterRejectsConcurrentSessionAndThrottlesRapidCalls() {
        let limiter = RuntimeSessionLimiter()

        #expect(limiter.acquire(sessionID: "a", now: 0).allowed)
        #expect(!limiter.acquire(sessionID: "b", now: 0.1).allowed)
        limiter.release(sessionID: "a")
        #expect(limiter.acquire(sessionID: "b", now: 0.2).allowed)

        limiter.configure(maxActionsPerSecond: 1)
        #expect(limiter.beforeAction(now: 1.0).allowed)
        #expect(!limiter.beforeAction(now: 1.1).allowed)
        #expect(limiter.beforeAction(now: 2.1).allowed)
    }

    @Test
    func routeRegistryDocumentsNewRoutes() {
        let ids = Set(RouteRegistry.publicRoutes().map(\.id))

        #expect(ids.contains(RouteID.waitFor.rawValue))
        #expect(ids.contains(RouteID.annotateWindow.rawValue))
        #expect(ids.contains(RouteID.readText.rawValue))
        #expect(ids.contains(RouteID.selectText.rawValue))
    }

    private func makeAnnotationState(nodes: [AXPipelineV2SurfaceNodeDTO]) -> GetWindowStateResponse {
        GetWindowStateResponse(
            contractVersion: ContractVersion.current,
            stateToken: "state",
            interactionToken: "interaction",
            window: ResolvedWindowDTO(
                windowID: "window",
                title: "Test",
                bundleID: "com.example.app",
                pid: 123,
                launchDate: nil,
                windowNumber: 42,
                frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
                resolutionStrategy: "test"
            ),
            attachedSurfaces: [],
            screenshot: ScreenshotDTO(
                status: "captured",
                image: ScreenshotImageDTO(
                    imagePath: "/tmp/test.png",
                    imageBase64: nil,
                    mimeType: "image/png",
                    pixelWidth: 400,
                    pixelHeight: 300,
                    coordinateOrigin: .topLeft,
                    coordinateSpace: .modelFacingScreenshot,
                    captureKind: "test"
                ),
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: nil
            ),
            tree: AXPipelineV2TreeDTO(
                nodeCount: nodes.count,
                truncated: false,
                renderedText: "",
                nodes: nodes,
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
                captureMs: 2,
                projectionMs: 0,
                screenshotMs: 3,
                totalMs: 6
            ),
            debug: nil,
            ocr: nil,
            notes: []
        )
    }

    private func annotationNode(
        displayIndex: Int,
        displayRole: String,
        title: String,
        frame: RectDTO,
        point: PointDTO,
        refetchFingerprint: String? = nil
    ) -> AXPipelineV2SurfaceNodeDTO {
        AXPipelineV2SurfaceNodeDTO(
            index: displayIndex,
            displayIndex: displayIndex,
            projectedIndex: displayIndex,
            parentIndex: nil,
            depth: 0,
            primaryCanonicalIndex: displayIndex,
            canonicalIndices: [displayIndex],
            childIndices: [],
            displayRole: displayRole,
            rawRole: nil,
            rawSubrole: nil,
            title: title,
            description: nil,
            help: nil,
            identifier: nil,
            domIdentifier: nil,
            url: nil,
            nodeID: "node-\(displayIndex)",
            identity: nil,
            refetch: nil,
            refetchFingerprint: refetchFingerprint ?? "refetch-\(displayIndex)",
            value: nil,
            valueKind: nil,
            isValueSettable: false,
            flags: [],
            secondaryActions: [],
            secondaryActionBindings: nil,
            affordances: nil,
            availableActions: nil,
            curatedSecondaryActions: nil,
            curatedAvailableActions: nil,
            parameterizedAttributes: nil,
            frameAppKit: frame,
            activationPointAppKit: nil,
            suggestedInteractionPointAppKit: point,
            childCount: 0,
            collectionInfo: nil,
            interactionTraits: nil,
            profileHint: nil,
            transformNotes: []
        )
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

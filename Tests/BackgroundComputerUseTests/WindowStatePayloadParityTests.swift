import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct WindowStatePayloadParityTests {
    static let perNodeByteCeiling = 1_800

    @Test
    func stateNodeSerializesCanonicalLocatorOnly() throws {
        let data = try JSONSupport.encoder.encode(representativeNode())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["displayIndex"] as? Int == 14)
        #expect(json["nodeID"] as? String == "n:0.3.2")
        #expect(json["refetchFingerprint"] as? String == "0123456789abcdef01234567")
        #expect(json["identity"] == nil)
        #expect(json["refetch"] == nil)

        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(encoded.contains("ancestorFingerprints") == false)
        #expect(encoded.contains("rolePath") == false)
    }

    @Test
    func stateNodePayloadStaysWithinDeclaredBudget() throws {
        let nodes = try representativePipelineNodes()
        try #require(nodes.isEmpty == false)
        let nodesBytes = try JSONSupport.encoder.encode(nodes).count
        let measuredBytes = nodesBytes / nodes.count
        print("PAYLOAD_BUDGET measured_node_bytes=\(measuredBytes) ceiling=\(Self.perNodeByteCeiling)")

        #expect(
            measuredBytes <= Self.perNodeByteCeiling,
            "Measured node payload \(measuredBytes) bytes exceeds ceiling \(Self.perNodeByteCeiling) bytes"
        )
    }

    @Test
    func apiResponsesUseCompactUnsortedJSON() throws {
        #expect(JSONSupport.encoder.outputFormatting.contains(.prettyPrinted) == false)
        #expect(JSONSupport.encoder.outputFormatting.contains(.sortedKeys) == false)

        let data = try JSONSupport.encoder.encode(["payload": ["value": "compact"]])
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(encoded.contains("\n") == false)
    }

    @Test
    func allFourTargetKindsResolveAfterStateNodeTrim() throws {
        let node = representativeNode()
        let capture = makeActionCapture(node: node)
        let resolver = AXActionTargetResolver(executionOptions: .visualCursorDisabled)

        let ocr = OCRAnchorSummaryBuilder.summary(
            lines: [
                OCRLineDTO(
                    text: "Click me",
                    confidence: 0.99,
                    box: OCRBoxDTO(x: 100, y: 200, width: 120, height: 32)
                ),
            ],
            interactionToken: "it_same_read"
        )
        let stateData = try JSONSupport.encoder.encode(makeWindowState(nodes: [node], ocr: ocr))
        let stateJSON = try #require(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        let treeJSON = try #require(stateJSON["tree"] as? [String: Any])
        let nodeJSON = try #require((treeJSON["nodes"] as? [[String: Any]])?.first)

        let displayTarget = try targetFromWire(kind: .displayIndex, value: nodeJSON["displayIndex"])
        let nodeTarget = try targetFromWire(kind: .nodeID, value: nodeJSON["nodeID"])
        let refetchTarget = try targetFromWire(kind: .refetchFingerprint, value: nodeJSON["refetchFingerprint"])

        #expect(resolver.resolveSurfaceNode(target: displayTarget, in: capture)?.nodeID == node.nodeID)
        #expect(resolver.resolveSurfaceNode(target: nodeTarget, in: capture)?.nodeID == node.nodeID)
        #expect(resolver.resolveSurfaceNode(target: refetchTarget, in: capture)?.nodeID == node.nodeID)

        let anchor = try #require(ocr.anchors.first)
        let ocrJSON = try #require(stateJSON["ocr"] as? [String: Any])
        let anchorJSON = try #require((ocrJSON["anchors"] as? [[String: Any]])?.first)
        let wireOCRTargetData = try JSONSerialization.data(withJSONObject: try #require(anchorJSON["target"]))
        let wireOCRTarget = try JSONSupport.decoder.decode(ActionTargetRequestDTO.self, from: wireOCRTargetData)
        let wireInteractionToken = try #require(stateJSON["interactionToken"] as? String)

        #expect(wireOCRTarget.kind == .ocrAnchor)
        #expect(
            OCRClickTargetResolver.resolve(
                requestedID: wireOCRTarget.value,
                suppliedInteractionToken: wireInteractionToken,
                liveInteractionToken: "it_same_read",
                anchors: ocr.anchors
            ) == .matched(anchor, relocated: false)
        )
    }

    @Test
    func surfaceNodeEncodesDOMIdentifierWhenPublished() throws {
        let data = try JSONSupport.encoder.encode(representativeNode(domIdentifier: "b"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["domIdentifier"] as? String == "b")
    }

    @Test
    func surfaceNodeOmitsDOMIdentifierWhenUnavailable() throws {
        let data = try JSONSupport.encoder.encode(representativeNode(domIdentifier: nil))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["domIdentifier"] == nil)
    }

    @Test
    func findElementsReturnsOnlyMatchesWithSameReadTokens() throws {
        let windowNode = representativeNode(
            displayIndex: 1,
            displayRole: "window",
            title: "Fixture Window",
            nodeID: "n:0",
            refetchFingerprint: "aaaaaaaaaaaaaaaaaaaaaaaa"
        )
        let buttonNode = representativeNode(domIdentifier: "b")
        let state = makeWindowState(nodes: [windowNode, buttonNode])
        let request = FindElementsRequest(window: "w_fixture", role: "button", text: "click ME")

        let response = try FindElementsRouteService.response(from: state, request: request)

        #expect(response.stateToken == "st_same_read")
        #expect(response.interactionToken == "it_same_read")
        #expect(response.matches.map(\.nodeID) == ["n:0.3.2"])
        #expect(response.matchCount == 1)

        let data = try JSONSupport.encoder.encode(response)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["tree"] == nil)
    }

    @Test
    func findElementsReturnsEmptySuccessWhenNoNodeMatches() throws {
        let state = makeWindowState(nodes: [representativeNode()])
        let request = FindElementsRequest(window: "w_fixture", role: "checkbox", text: "missing")

        let response = try FindElementsRouteService.response(from: state, request: request)

        #expect(response.matches.isEmpty)
        #expect(response.matchCount == 0)
        #expect(response.summary == "No elements matched the query.")
    }

    private func representativeNode(
        displayIndex: Int = 14,
        displayRole: String = "button",
        title: String = "Click me",
        nodeID: String = "n:0.3.2",
        refetchFingerprint: String = "0123456789abcdef01234567",
        domIdentifier: String? = nil
    ) -> AXPipelineV2SurfaceNodeDTO {
        let signature = AXNodeRefetchSignatureDTO(
            role: "AX\(displayRole.capitalized)",
            subrole: nil,
            roleDescription: displayRole,
            title: title,
            description: "Fixture button used to enforce the serialized node budget",
            placeholder: nil,
            help: "Activates the fixture action",
            identifier: "fixture-button",
            urlHost: "example.test"
        )
        let refetch = AXNodeRefetchLocatorDTO(
            fingerprint: refetchFingerprint,
            parentFingerprint: "abcdef0123456789abcdef01",
            ancestorFingerprints: [
                "111111111111111111111111",
                "222222222222222222222222",
                "333333333333333333333333",
            ],
            ordinalWithinParent: 2,
            rolePath: ["AXWindow", "AXWebArea", "AXGroup", "AXButton"],
            signature: signature
        )
        let identity = AXNodeIdentityDTO(
            nodeID: nodeID,
            path: [0, 3, 2],
            pathString: "0.3.2",
            signature: AXNodeIdentitySignatureDTO(
                role: "AX\(displayRole.capitalized)",
                subrole: nil,
                title: title,
                description: "Fixture button used to enforce the serialized node budget",
                valuePreview: "Click me",
                identifier: "fixture-button",
                url: "https://example.test/fixture"
            ),
            refetch: refetch
        )

        return AXPipelineV2SurfaceNodeDTO(
            index: 8,
            displayIndex: displayIndex,
            projectedIndex: 8,
            parentIndex: 3,
            depth: 3,
            primaryCanonicalIndex: 8,
            canonicalIndices: [8],
            childIndices: [],
            displayRole: displayRole,
            rawRole: "AX\(displayRole.capitalized)",
            rawSubrole: nil,
            title: title,
            description: "Fixture button used to enforce the serialized node budget",
            help: "Activates the fixture action",
            identifier: "fixture-button",
            domIdentifier: domIdentifier,
            url: "https://example.test/fixture",
            nodeID: nodeID,
            identity: identity,
            refetch: refetch,
            refetchFingerprint: refetchFingerprint,
            value: ValueSummaryDTO(kind: "string", preview: title, length: title.count, truncated: false),
            valueKind: "string",
            isValueSettable: false,
            flags: ["web_descendant", "actionable"],
            secondaryActions: [],
            secondaryActionBindings: nil,
            affordances: nil,
            availableActions: nil,
            curatedSecondaryActions: nil,
            curatedAvailableActions: nil,
            parameterizedAttributes: nil,
            frameAppKit: RectDTO(x: 100, y: 200, width: 120, height: 32),
            activationPointAppKit: PointDTO(x: 160, y: 216),
            suggestedInteractionPointAppKit: PointDTO(x: 160, y: 216),
            childCount: 0,
            collectionInfo: nil,
            interactionTraits: nil,
            profileHint: "rich-web-electron",
            transformNotes: []
        )
    }

    private func makeWindowState(
        nodes: [AXPipelineV2SurfaceNodeDTO],
        ocr: OCRAnchorSummaryDTO? = nil
    ) -> GetWindowStateResponse {
        GetWindowStateResponse(
            contractVersion: ContractVersion.current,
            stateToken: "st_same_read",
            interactionToken: "it_same_read",
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
                nodeCount: nodes.count,
                truncated: false,
                renderedText: nodes.compactMap(\.title).joined(separator: "\n"),
                nodes: nodes,
                lineMappings: [],
                profile: "rich-web-electron"
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
                screenshotMs: 0,
                totalMs: 3
            ),
            debug: nil,
            ocr: ocr,
            notes: []
        )
    }

    private func targetFromWire(kind: ActionTargetKindDTO, value: Any?) throws -> ActionTargetRequestDTO {
        let body: [String: Any] = [
            "kind": kind.rawValue,
            "value": try #require(value),
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try JSONSupport.decoder.decode(ActionTargetRequestDTO.self, from: data)
    }

    private func representativePipelineNodes() throws -> [AXPipelineV2SurfaceNodeDTO] {
        let rawNodes = [
            rawNode(
                index: 0,
                parentIndex: nil,
                depth: 0,
                childIndices: [1],
                path: [0],
                role: "AXWindow",
                title: "Fixture Window"
            ),
            rawNode(
                index: 1,
                parentIndex: 0,
                depth: 1,
                childIndices: [2, 3, 4],
                path: [0, 0],
                role: "AXWebArea",
                title: "Fixture Page"
            ),
            rawNode(
                index: 2,
                parentIndex: 1,
                depth: 2,
                childIndices: [],
                path: [0, 0, 0],
                role: "AXButton",
                title: "Click me",
                domIdentifier: "b",
                secondaryActions: ["Press"]
            ),
            rawNode(
                index: 3,
                parentIndex: 1,
                depth: 2,
                childIndices: [],
                path: [0, 0, 1],
                role: "AXStaticText",
                title: "Status: ready"
            ),
            rawNode(
                index: 4,
                parentIndex: 1,
                depth: 2,
                childIndices: [],
                path: [0, 0, 2],
                role: "AXTextField",
                title: "Search",
                isValueSettable: true,
                parameterizedAttributes: ["AXStringForRange", "AXBoundsForRange"]
            ),
        ]
        let fixture = AXPipelineV2Fixture(
            generatedAt: "2026-08-25T00:00:00Z",
            scenarioID: "payload-budget",
            appQuery: "com.example.fixture",
            includeMenuBar: false,
            menuMode: AXMenuMode.none,
            maxNodes: 100,
            window: ResolvedWindowDTO(
                windowID: "w_payload_fixture",
                title: "Fixture Window",
                bundleID: "com.example.fixture",
                pid: 123,
                launchDate: nil,
                windowNumber: 77,
                frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
                resolutionStrategy: "fixture"
            ),
            rawCapture: AXRawCaptureResult(
                rootIndices: [0],
                nodes: rawNodes,
                focusedCanonicalIndex: 4,
                focusSelection: nil,
                truncated: false
            ),
            platformProfile: AXPlatformProfileDTO(
                bundleID: "com.example.fixture",
                bundlePath: nil,
                frameworkHints: ["chromium"],
                helperAppHints: [],
                isChromiumLike: true,
                isElectronLike: false,
                manualAccessibility: nil,
                enablementAttempts: nil,
                notes: []
            ),
            menuPresentation: nil,
            notes: []
        )

        return StatePipelineExperiment().replayFixture(fixture, imageMode: .omit).response.tree.nodes
    }

    private func rawNode(
        index: Int,
        parentIndex: Int?,
        depth: Int,
        childIndices: [Int],
        path: [Int],
        role: String,
        title: String,
        domIdentifier: String? = nil,
        secondaryActions: [String] = [],
        isValueSettable: Bool = false,
        parameterizedAttributes: [String] = []
    ) -> AXRawNodeDTO {
        let fingerprint = String(format: "%024d", index + 1)
        let signature = AXNodeRefetchSignatureDTO(
            role: role,
            subrole: nil,
            roleDescription: role.replacingOccurrences(of: "AX", with: ""),
            title: title,
            description: "Representative pipeline fixture node \(index)",
            placeholder: role == "AXTextField" ? "Search the fixture" : nil,
            help: "Representative payload budget fixture",
            identifier: "fixture-\(index)",
            urlHost: "example.test"
        )
        let refetch = AXNodeRefetchLocatorDTO(
            fingerprint: fingerprint,
            parentFingerprint: parentIndex.map { String(format: "%024d", $0 + 1) },
            ancestorFingerprints: path.dropLast().enumerated().map { offset, _ in
                String(format: "%024d", offset + 1)
            },
            ordinalWithinParent: path.last ?? 0,
            rolePath: Array(repeating: "AXGroup", count: max(0, depth)) + [role],
            signature: signature
        )
        let identity = AXNodeIdentityDTO(
            nodeID: "n:" + path.map(String.init).joined(separator: "."),
            path: path,
            pathString: path.map(String.init).joined(separator: "."),
            signature: AXNodeIdentitySignatureDTO(
                role: role,
                subrole: nil,
                title: title,
                description: "Representative pipeline fixture node \(index)",
                valuePreview: title,
                identifier: "fixture-\(index)",
                url: "https://example.test/fixture"
            ),
            refetch: refetch
        )

        return AXRawNodeDTO(
            index: index,
            parentIndex: parentIndex,
            depth: depth,
            childIndices: childIndices,
            role: role,
            subrole: nil,
            roleDescription: role.replacingOccurrences(of: "AX", with: ""),
            title: title,
            placeholder: role == "AXTextField" ? "Search the fixture" : nil,
            description: "Representative pipeline fixture node \(index)",
            help: "Representative payload budget fixture",
            identifier: "fixture-\(index)",
            domIdentifier: domIdentifier,
            url: "https://example.test/fixture",
            valueDescription: title,
            valueType: "CFString",
            enabled: true,
            selected: false,
            expanded: nil,
            isFocused: role == "AXTextField",
            value: ValueSummaryDTO(kind: "string", preview: title, length: title.count, truncated: false),
            isValueSettable: isValueSettable,
            secondaryActions: secondaryActions,
            availableActions: nil,
            parameterizedAttributes: parameterizedAttributes,
            frameAppKit: RectDTO(x: 20, y: Double(500 - index * 60), width: 320, height: 40),
            activationPointAppKit: PointDTO(x: 180, y: Double(520 - index * 60)),
            childCount: childIndices.count,
            childSource: "AXChildren",
            collectionInfo: nil,
            identity: identity,
            relationships: nil,
            textExtraction: nil,
            interactionTraits: nil
        )
    }

    private func makeActionCapture(node: AXPipelineV2SurfaceNodeDTO) -> AXActionStateCapture {
        let window = ResolvedWindowDTO(
            windowID: "w_fixture",
            title: "Fixture",
            bundleID: "com.example.fixture",
            pid: ProcessInfo.processInfo.processIdentifier,
            launchDate: nil,
            windowNumber: 77,
            frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
            resolutionStrategy: "test"
        )
        let tree = AXPipelineV2TreeDTO(
            nodeCount: 1,
            truncated: false,
            renderedText: "[14] button Click me",
            nodes: [node],
            lineMappings: [],
            profile: "rich-web-electron"
        )
        let response = AXPipelineV2Response(
            contractVersion: StatePipelineContractVersion.current,
            stateToken: "st_fixture",
            interactionToken: "it_fixture",
            window: window,
            attachedSurfaces: [],
            screenshot: ScreenshotDTO(
                status: "omitted",
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: nil
            ),
            tree: tree,
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
            notes: []
        )
        let envelope = AXPipelineV2Envelope(
            response: response,
            rawCapture: AXRawCaptureResult(
                rootIndices: [],
                nodes: [],
                focusedCanonicalIndex: nil,
                focusSelection: nil,
                truncated: false
            ),
            platformProfile: AXPlatformProfileDTO(
                bundleID: "com.example.fixture",
                bundlePath: nil,
                frameworkHints: [],
                helperAppHints: [],
                isChromiumLike: true,
                isElectronLike: false,
                manualAccessibility: nil,
                enablementAttempts: nil,
                notes: []
            ),
            semanticTree: AXSemanticTreeDTO(
                rootIndices: [],
                nodes: [],
                focusedCanonicalIndex: nil,
                focusSelection: nil
            ),
            projectedTree: AXProjectedTreeDTO(
                rootProjectedIndices: [],
                nodes: [],
                lineMappings: [],
                renderedText: "",
                focusedCanonicalIndex: nil,
                focusedProjectedIndex: nil,
                focusedDisplayIndex: nil,
                profile: "rich-web-electron",
                appliedTransforms: [],
                selectionSummary: nil
            ),
            menuPresentation: nil,
            diagnostics: AXPipelineV2DiagnosticsDTO(
                rawNodeCount: 0,
                semanticNodeCount: 0,
                projectedNodeCount: 1,
                renderedLineCount: 1,
                focusedCanonicalIndex: nil,
                focusedProjectedIndex: nil,
                focusedDisplayIndex: nil,
                projectionProfile: "rich-web-electron",
                appliedTransforms: [],
                selectedTextAvailable: nil,
                clickReadiness: nil,
                notes: []
            )
        )
        let element = AXUIElementCreateSystemWide()
        let resolved = ResolvedWindowTarget(
            windowID: window.windowID,
            bundleID: window.bundleID,
            launchDate: nil,
            app: NSRunningApplication.current,
            appElement: element,
            window: AXWindowRecord(
                element: element,
                windowNumber: window.windowNumber,
                title: window.title,
                role: "AXWindow",
                subrole: nil,
                frameAppKit: CGRect(x: 0, y: 0, width: 800, height: 600),
                isFocused: false,
                isMain: false,
                isMinimized: false,
                isOnScreen: false
            ),
            resolutionStrategy: "test",
            notes: []
        )

        return AXActionStateCapture(
            windowID: window.windowID,
            includeMenuBar: false,
            includeCursorOverlay: false,
            menuPathComponents: [],
            webTraversal: .visible,
            maxNodes: 100,
            resolved: resolved,
            envelope: envelope,
            liveElementsByCanonicalIndex: [:],
            displayIndexByProjectedIndex: [node.projectedIndex: node.displayIndex!]
        )
    }
}

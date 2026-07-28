import CoreGraphics
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct WebReliabilityTests {
    @Test
    func ocrClickResolverMatchesExactAndRelocatedAnchors() throws {
        let before = OCRAnchorSummaryBuilder.summary(
            lines: [.init(text: "Update Server", confidence: 0.99, box: .init(x: 100, y: 200, width: 120, height: 32))],
            interactionToken: "it_LIVE"
        )
        let requested = try #require(before.anchors.first)
        let exact = OCRClickTargetResolver.resolve(
            requestedID: requested.id,
            suppliedInteractionToken: "it_LIVE",
            liveInteractionToken: "it_LIVE",
            anchors: before.anchors
        )

        guard case let .matched(exactAnchor, relocated) = exact else {
            Issue.record("Expected exact OCR anchor match")
            return
        }
        #expect(exactAnchor.id == requested.id)
        #expect(!relocated)

        let moved = OCRAnchorSummaryBuilder.summary(
            lines: [.init(text: "Update Server", confidence: 0.99, box: .init(x: 108, y: 204, width: 120, height: 32))],
            interactionToken: "it_LIVE"
        )
        let relocatedResult = OCRClickTargetResolver.resolve(
            requestedID: requested.id,
            suppliedInteractionToken: "it_LIVE",
            liveInteractionToken: "it_LIVE",
            anchors: moved.anchors
        )
        guard case let .matched(movedAnchor, wasRelocated) = relocatedResult else {
            Issue.record("Expected relocated OCR anchor match")
            return
        }
        #expect(movedAnchor.text == "Update Server")
        #expect(wasRelocated)
    }

    @Test
    func ocrClickResolverFailsClosedForStaleToken() throws {
        let summary = OCRAnchorSummaryBuilder.summary(
            lines: [.init(text: "Update Server", confidence: 0.99, box: .init(x: 100, y: 200, width: 120, height: 32))],
            interactionToken: "it_LIVE"
        )
        let requested = try #require(summary.anchors.first)

        let result = OCRClickTargetResolver.resolve(
            requestedID: requested.id,
            suppliedInteractionToken: "it_OLD",
            liveInteractionToken: "it_LIVE",
            anchors: summary.anchors
        )
        #expect(result == .staleInteractionToken)
    }

    @Test
    func visualChangeAnalyzerSeparatesTargetAndWindowChanges() throws {
        let before = try makeImage(changedRect: nil)
        let inside = try makeImage(changedRect: CGRect(x: 20, y: 20, width: 20, height: 20))
        let outside = try makeImage(changedRect: CGRect(x: 70, y: 70, width: 20, height: 20))
        let target = CGRect(x: 0.15, y: 0.15, width: 0.3, height: 0.3)

        let insideResult = try #require(VisualChangeAnalyzer.compare(before: before, after: inside, normalizedRegion: target))
        let outsideResult = try #require(VisualChangeAnalyzer.compare(before: before, after: outside, normalizedRegion: target))

        #expect(insideResult.fullImageRatio > 0)
        #expect(insideResult.targetRegionRatio > 0.25)
        #expect(outsideResult.fullImageRatio > 0)
        #expect(outsideResult.targetRegionRatio == 0)
    }
    @Test
    func ocrVerificationRegionConvertsTopLeftPixelsToBottomLeftNormalizedSpace() {
        let region = ClickRouteService.normalizedOCRVerificationRegion(
            box: OCRBoxDTO(x: 10, y: 20, width: 30, height: 40),
            modelWidth: 100,
            modelHeight: 200
        )

        #expect(region == CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.2))
    }

    @Test
    func ocrCaptureImageModePreservesBase64AndUpgradesOnlyOmit() {
        #expect(ClickRouteService.ocrCaptureImageMode(requested: .base64) == .base64)
        #expect(ClickRouteService.ocrCaptureImageMode(requested: .path) == .path)
        #expect(ClickRouteService.ocrCaptureImageMode(requested: .omit) == .path)
    }


    @Test
    func attachedSheetCanonicalizerFoldsOnlyMatchingOverlappingDuplicate() {
        let sheetFrame = RectDTO(x: 100, y: 100, width: 400, height: 240)
        let nodes = [
            surfaceNode(index: 0, children: [1, 3, 5, 7], role: "AXWindow", label: "Root"),
            surfaceNode(index: 1, parent: 0, children: [2], role: "AXSheet", label: "Update Available", frame: sheetFrame),
            surfaceNode(index: 2, parent: 1, role: "AXButton", label: "Update", interactive: true, frame: sheetFrame),
            surfaceNode(index: 3, parent: 0, children: [4], role: "AXGroup", label: "Web Dialog", frame: sheetFrame),
            surfaceNode(index: 4, parent: 3, role: "AXButton", label: "Install Now", interactive: true, frame: sheetFrame),
            surfaceNode(
                index: 5,
                parent: 0,
                children: [6],
                role: "AXGroup",
                label: "Update Available",
                frame: RectDTO(x: 700, y: 100, width: 400, height: 240)
            ),
            surfaceNode(
                index: 6,
                parent: 5,
                role: "AXButton",
                label: "Update",
                interactive: true,
                frame: RectDTO(x: 700, y: 100, width: 400, height: 240)
            ),
            surfaceNode(
                index: 7,
                parent: 0,
                children: [8],
                role: "AXWebArea",
                label: "Update Available",
                frame: RectDTO(x: 0, y: 0, width: 1_200, height: 800)
            ),
            surfaceNode(
                index: 8,
                parent: 7,
                role: "AXButton",
                label: "Update",
                interactive: true,
                frame: sheetFrame
            )
        ]

        let plan = AXAttachedSheetCanonicalizer.plan(nodes: nodes)

        #expect(plan.sheetIndices == [1])
        #expect(plan.duplicateRootsBySheet[1] == [3])
        #expect(plan.foldedIndicesBySheet[1] == [3, 4])
    }

    @Test
    func attachedSurfaceCompositionUsesOnlyExplicitSameProcessWindowsInBackToFrontOrder() {
        let rootFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let surfaces = [
            AttachedSurfaceDTO(
                id: "front",
                role: "AXSheet",
                title: "Front",
                frameAppKit: RectDTO(x: 100, y: 100, width: 200, height: 100),
                windowNumber: 11,
                isLiveActionSurface: true
            ),
            AttachedSurfaceDTO(
                id: "back",
                role: "AXSheet",
                title: "Back",
                frameAppKit: RectDTO(x: 120, y: 120, width: 200, height: 100),
                windowNumber: 12,
                isLiveActionSurface: true
            )
        ]
        let inventory = [
            CGWindowRecord(ownerPID: 123, windowNumber: 10, title: "Root", frameAppKit: rootFrame, orderIndex: 3, isOnScreen: true),
            CGWindowRecord(ownerPID: 123, windowNumber: 11, title: "Front", frameAppKit: CGRect(x: 100, y: 100, width: 200, height: 100), orderIndex: 1, isOnScreen: true),
            CGWindowRecord(ownerPID: 123, windowNumber: 12, title: "Back", frameAppKit: CGRect(x: 120, y: 120, width: 200, height: 100), orderIndex: 5, isOnScreen: true),
            CGWindowRecord(ownerPID: 999, windowNumber: 11, title: "Foreign", frameAppKit: CGRect(x: 100, y: 100, width: 200, height: 100), orderIndex: 0, isOnScreen: true),
            CGWindowRecord(ownerPID: 123, windowNumber: 13, title: "Unrequested", frameAppKit: CGRect(x: 100, y: 100, width: 200, height: 100), orderIndex: 0, isOnScreen: true)
        ]

        let records = AttachedSurfaceCompositionPlanner.records(
            ownerPID: 123,
            rootWindowNumber: 10,
            rootFrame: rootFrame,
            surfaces: surfaces,
            inventory: inventory
        )

        #expect(records.map(\.windowNumber) == [12, 11])
    }

    @Test
    func attachedSurfaceCompositePreservesRootOrientationAndUsesAppKitTopOffset() throws {
        let rootImage = try makeImage(
            changedRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            width: 100,
            height: 100
        )
        let surfaceImage = try makeImage(
            changedRect: CGRect(x: 0, y: 0, width: 20, height: 10),
            width: 20,
            height: 10
        )
        let result = CGWindowCaptureService.composite(
            rootCapture: CGWindowCapture(image: rootImage, windowNumber: 1, warnings: []),
            rootFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            surfaces: [
                CGAttachedSurfaceCapture(
                    capture: CGWindowCapture(image: surfaceImage, windowNumber: 2, warnings: []),
                    frameAppKit: CGRect(x: 10, y: 70, width: 20, height: 10)
                )
            ],
            warnings: ["surface diagnostic"]
        )
        let capture = try result.get()

        #expect(try pixelBrightness(rootImage, x: 5, y: 5) == pixelBrightness(capture.image, x: 5, y: 5))
        #expect(try pixelBrightness(rootImage, x: 5, y: 95) == pixelBrightness(capture.image, x: 5, y: 95))
        #expect(try pixelBrightness(capture.image, x: 15, y: 25) < 30)
        #expect(try pixelBrightness(capture.image, x: 15, y: 75) > 700)
        #expect(capture.warnings == ["surface diagnostic"])
    }


    @Test
    func nativeBackgroundClickUsesBottomLeftWindowLocalCoordinates() {
        let local = NativeBackgroundClickTransport.windowLocalAppKit(
            point: CGPoint(x: 178, y: 1050),
            windowFrameAppKit: CGRect(x: 100, y: 200, width: 1920, height: 1170)
        )

        #expect(local == CGPoint(x: 78, y: 850))
    }


    private func surfaceNode(
        index: Int,
        parent: Int? = nil,
        children: [Int] = [],
        role: String,
        label: String,
        interactive: Bool = false,
        frame: RectDTO? = nil
    ) -> AXAttachedSheetProjectionNode {
        AXAttachedSheetProjectionNode(
            index: index,
            parentIndex: parent,
            childIndices: children,
            role: role,
            subrole: nil,
            displayRole: role == "AXButton" ? "button" : "container",
            label: label,
            title: label,
            description: nil,
            isInteractive: interactive,
            frameAppKit: frame
        )
    }

    private func makeImage(
        changedRect: CGRect?,
        width: Int = 100,
        height: Int = 100
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let changedRect {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(changedRect)
        }
        return try #require(context.makeImage())
    }
    private func pixelBrightness(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        return Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])
    }

}

import AppKit
import Foundation

struct WindowAnnotationService {
    private let windowStateService: WindowStateService

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        windowStateService = WindowStateService(executionOptions: executionOptions)
    }

    func annotateWindow(request: AnnotateWindowRequest) throws -> AnnotateWindowResponse {
        let maxMarks = min(200, max(1, request.maxMarks ?? 80))
        let state = try windowStateService.getWindowState(
            request: GetWindowStateRequest(
                window: request.window,
                includeMenuBar: request.includeMenuBar ?? false,
                menuPath: nil,
                webTraversal: request.webTraversal,
                maxNodes: request.maxNodes,
                imageMode: request.imageMode ?? .path
            )
        )

        let selection = WindowAnnotationBuilder.marks(
            from: state,
            maxMarks: maxMarks,
            includeStaticText: request.includeStaticText ?? false
        )
        var notes = state.notes
        var annotatedImage: ScreenshotImageDTO?

        if let imagePath = state.screenshot.image?.imagePath {
            annotatedImage = WindowAnnotationRenderer.render(
                baseImagePath: imagePath,
                baseImage: state.screenshot.image,
                marks: selection.marks,
                windowID: state.window.windowID,
                stateToken: state.stateToken,
                imageMode: request.imageMode ?? .path
            )
            if annotatedImage == nil {
                notes.append("Annotation marks were computed, but the annotated PNG artifact could not be rendered.")
            }
        } else {
            notes.append("Annotation marks were computed, but no model-facing screenshot path was available to render the annotated image.")
        }

        return AnnotateWindowResponse(
            contractVersion: ContractVersion.current,
            stateToken: state.stateToken,
            window: state.window,
            screenshot: state.screenshot,
            annotatedImage: annotatedImage,
            marks: selection.marks,
            truncated: selection.truncated,
            maxMarks: maxMarks,
            backgroundSafety: state.backgroundSafety,
            performance: state.performance,
            notes: notes
        )
    }
}

enum WindowAnnotationBuilder {
    static func marks(
        from state: GetWindowStateResponse,
        maxMarks: Int,
        includeStaticText: Bool
    ) -> (marks: [WindowAnnotationMarkDTO], truncated: Bool) {
        guard let image = state.screenshot.image else {
            return ([], false)
        }

        let windowFrame = CGRect(
            x: state.window.frameAppKit.x,
            y: state.window.frameAppKit.y,
            width: state.window.frameAppKit.width,
            height: state.window.frameAppKit.height
        )
        let imageSize = CGSize(width: image.pixelWidth, height: image.pixelHeight)
        var candidates = state.tree.nodes
            .filter { isAnnotatable($0, includeStaticText: includeStaticText) }
            .compactMap {
                markCandidate(
                    for: $0,
                    windowFrame: windowFrame,
                    imageSize: imageSize
                )
            }

        candidates.sort {
            if abs($0.point.y - $1.point.y) > 8 {
                return $0.point.y < $1.point.y
            }
            return $0.point.x < $1.point.x
        }

        let truncated = candidates.count > maxMarks
        let marks = candidates.prefix(maxMarks).enumerated().map { offset, candidate in
            WindowAnnotationMarkDTO(
                markID: offset + 1,
                displayIndex: candidate.node.displayIndex,
                nodeID: candidate.node.nodeID,
                refetchFingerprint: candidate.node.refetchFingerprint,
                target: semanticTarget(for: candidate.node),
                role: candidate.node.displayRole,
                title: candidate.node.title,
                description: candidate.node.description,
                valuePreview: candidate.node.value?.preview,
                point: candidate.point,
                rect: candidate.rect,
                source: candidate.source
            )
        }
        return (Array(marks), truncated)
    }

    private struct Candidate {
        let node: AXPipelineV2SurfaceNodeDTO
        let point: PointDTO
        let rect: RectDTO?
        let source: String
    }

    private static func markCandidate(
        for node: AXPipelineV2SurfaceNodeDTO,
        windowFrame: CGRect,
        imageSize: CGSize
    ) -> Candidate? {
        let rect = node.frameAppKit.flatMap {
            modelFacingRect(for: $0, windowFrame: windowFrame, imageSize: imageSize)
        }
        let pointSource: (PointDTO, String)? = node.suggestedInteractionPointAppKit.map { ($0, "suggested_interaction_point") }
            ?? node.activationPointAppKit.map { ($0, "activation_point") }
            ?? node.frameAppKit.map { frame in
                (
                    PointDTO(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2),
                    "frame_center"
                )
            }

        guard let pointSource else {
            return nil
        }
        let point = modelFacingPoint(for: pointSource.0, windowFrame: windowFrame, imageSize: imageSize)
        guard isInside(point, imageSize: imageSize, padding: 4) else {
            return nil
        }

        return Candidate(node: node, point: point, rect: rect, source: pointSource.1)
    }

    private static func isAnnotatable(_ node: AXPipelineV2SurfaceNodeDTO, includeStaticText: Bool) -> Bool {
        guard node.displayIndex != nil || node.nodeID != nil || node.refetchFingerprint != nil else {
            return false
        }
        guard node.frameAppKit != nil || node.suggestedInteractionPointAppKit != nil || node.activationPointAppKit != nil else {
            return false
        }

        let role = normalized(node.displayRole)
        let structuralRoles: Set<String> = [
            "application", "window", "standard window", "container", "group",
            "generic element", "split group", "layout area", "section"
        ]
        if structuralRoles.contains(role) {
            return false
        }

        if node.secondaryActions.isEmpty == false ||
            node.availableActions?.isEmpty == false ||
            node.curatedAvailableActions?.isEmpty == false ||
            node.affordances?.isEmpty == false ||
            node.isValueSettable == true {
            return true
        }

        let interactiveRoles: Set<String> = [
            "button", "link", "text field", "text area", "search field",
            "checkbox", "radio button", "pop up button", "combo box",
            "menu button", "menu item", "tab", "slider", "row", "cell",
            "image", "disclosure triangle"
        ]
        if interactiveRoles.contains(role) {
            return true
        }

        return includeStaticText && role.contains("text")
    }

    private static func semanticTarget(for node: AXPipelineV2SurfaceNodeDTO) -> ActionTargetRequestDTO? {
        if let displayIndex = node.displayIndex {
            return try? .displayIndex(displayIndex)
        }
        if let nodeID = node.nodeID {
            return try? .nodeID(nodeID)
        }
        if let refetchFingerprint = node.refetchFingerprint {
            return try? .refetchFingerprint(refetchFingerprint)
        }
        return nil
    }

    private static func modelFacingPoint(
        for point: PointDTO,
        windowFrame: CGRect,
        imageSize: CGSize
    ) -> PointDTO {
        let mapped = CursorScreenshotCompositor.modelFacingPoint(
            for: CGPoint(x: point.x, y: point.y),
            in: windowFrame,
            modelImageSize: imageSize
        )
        return PointDTO(
            x: min(max(Double(mapped.x), 0), Double(imageSize.width)),
            y: min(max(Double(mapped.y), 0), Double(imageSize.height))
        )
    }

    private static func modelFacingRect(
        for rect: RectDTO,
        windowFrame: CGRect,
        imageSize: CGSize
    ) -> RectDTO? {
        let topLeft = modelFacingPoint(
            for: PointDTO(x: rect.x, y: rect.y + rect.height),
            windowFrame: windowFrame,
            imageSize: imageSize
        )
        let bottomRight = modelFacingPoint(
            for: PointDTO(x: rect.x + rect.width, y: rect.y),
            windowFrame: windowFrame,
            imageSize: imageSize
        )
        let minX = min(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let maxX = max(topLeft.x, bottomRight.x)
        let maxY = max(topLeft.y, bottomRight.y)
        let clippedMinX = min(max(minX, 0), Double(imageSize.width))
        let clippedMinY = min(max(minY, 0), Double(imageSize.height))
        let clippedMaxX = min(max(maxX, 0), Double(imageSize.width))
        let clippedMaxY = min(max(maxY, 0), Double(imageSize.height))
        guard clippedMaxX > clippedMinX, clippedMaxY > clippedMinY else {
            return nil
        }
        return RectDTO(
            x: clippedMinX,
            y: clippedMinY,
            width: clippedMaxX - clippedMinX,
            height: clippedMaxY - clippedMinY
        )
    }

    private static func isInside(_ point: PointDTO, imageSize: CGSize, padding: Double) -> Bool {
        point.x >= -padding &&
            point.y >= -padding &&
            point.x <= Double(imageSize.width) + padding &&
            point.y <= Double(imageSize.height) + padding
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

enum WindowAnnotationRenderer {
    static func render(
        baseImagePath: String,
        baseImage: ScreenshotImageDTO?,
        marks: [WindowAnnotationMarkDTO],
        windowID: String,
        stateToken: String,
        imageMode: ImageMode
    ) -> ScreenshotImageDTO? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: baseImagePath)),
              let bitmap = NSBitmapImageRep(data: data),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        let size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        let source = NSImage(cgImage: cgImage, size: size)
        let annotated = NSImage(size: size, flipped: true) { rect in
            source.draw(in: rect)
            draw(marks: marks, imageSize: size)
            return true
        }

        guard let tiff = annotated.tiffRepresentation,
              let outputBitmap = NSBitmapImageRep(data: tiff),
              let pngData = outputBitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let capturesDirectory = FileManager.default.temporaryDirectory
            .appending(path: "background-computer-use", directoryHint: .isDirectory)
            .appending(path: "captures", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
            let destination = capturesDirectory.appending(path: "\(windowID)-\(stateToken)-annotated.png")
            try pngData.write(to: destination, options: .atomic)
            return ScreenshotImageDTO(
                imagePath: destination.path,
                imageBase64: imageMode == .base64 ? pngData.base64EncodedString() : nil,
                mimeType: "image/png",
                pixelWidth: bitmap.pixelsWide,
                pixelHeight: bitmap.pixelsHigh,
                coordinateOrigin: baseImage?.coordinateOrigin ?? .topLeft,
                coordinateSpace: baseImage?.coordinateSpace ?? .modelFacingScreenshot,
                captureKind: "model-facing-window-annotation"
            )
        } catch {
            return nil
        }
    }

    private static func draw(marks: [WindowAnnotationMarkDTO], imageSize: NSSize) {
        for mark in marks {
            if let rect = mark.rect {
                drawOutline(rect)
            }
            drawLabel(mark: mark, imageSize: imageSize)
        }
    }

    private static func drawOutline(_ rect: RectDTO) {
        NSColor.systemTeal.withAlphaComponent(0.82).setStroke()
        let path = NSBezierPath(
            roundedRect: NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
            xRadius: 4,
            yRadius: 4
        )
        path.lineWidth = 2
        path.stroke()
    }

    private static func drawLabel(mark: WindowAnnotationMarkDTO, imageSize: NSSize) {
        let text = "\(mark.markID)" as NSString
        let font = NSFont.boldSystemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let paddingX: CGFloat = 7
        let paddingY: CGFloat = 4
        let labelWidth = max(22, textSize.width + paddingX * 2)
        let labelHeight = max(22, textSize.height + paddingY * 2)
        let anchor = CGPoint(x: mark.point.x, y: mark.point.y)
        let origin = clampedLabelOrigin(
            anchor: anchor,
            labelSize: CGSize(width: labelWidth, height: labelHeight),
            imageSize: imageSize
        )

        NSColor.black.withAlphaComponent(0.26).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: origin.x + 2, y: origin.y + 2, width: labelWidth, height: labelHeight),
            xRadius: 6,
            yRadius: 6
        ).fill()

        NSColor.systemTeal.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: origin.x, y: origin.y, width: labelWidth, height: labelHeight),
            xRadius: 6,
            yRadius: 6
        ).fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(
            ovalIn: NSRect(x: anchor.x - 3, y: anchor.y - 3, width: 6, height: 6)
        )
        ring.lineWidth = 1.5
        ring.stroke()

        text.draw(
            at: CGPoint(
                x: origin.x + (labelWidth - textSize.width) / 2,
                y: origin.y + (labelHeight - textSize.height) / 2
            ),
            withAttributes: attributes
        )
    }

    private static func clampedLabelOrigin(
        anchor: CGPoint,
        labelSize: CGSize,
        imageSize: NSSize
    ) -> CGPoint {
        let proposed = CGPoint(
            x: anchor.x + 6,
            y: anchor.y - labelSize.height - 6
        )
        return CGPoint(
            x: min(max(proposed.x, 4), max(4, imageSize.width - labelSize.width - 4)),
            y: min(max(proposed.y, 4), max(4, imageSize.height - labelSize.height - 4))
        )
    }
}

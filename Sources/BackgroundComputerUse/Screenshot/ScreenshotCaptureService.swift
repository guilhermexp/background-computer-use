import AppKit
import CoreGraphics
import Foundation

enum ScreenshotCaptureService {
    struct EvidenceCapture {
        let image: CGImage?
        let diagnostic: String?
    }

    static func captureEvidenceImage(
        window: ResolvedWindowDTO,
        attachedSurfaces: [AttachedSurfaceDTO] = [],
        rawCaptureProvider: (() -> Result<CGWindowCapture, CGWindowCaptureError>)? = nil
    ) -> EvidenceCapture {
        let rawCapture = rawCaptureProvider?() ?? CGWindowCaptureService.captureImageResult(
            window: window,
            attachedSurfaces: attachedSurfaces
        )
        let rawImage: CGImage
        switch rawCapture {
        case let .success(capture):
            rawImage = capture.image
        case let .failure(error):
            return EvidenceCapture(
                image: nil,
                diagnostic: "Clean post-click capture failed: \(error.description)"
            )
        }

        let targetWindow = TargetWindowIdentity(
            bundleID: window.bundleID,
            pid: window.pid,
            windowNumber: window.windowNumber,
            title: window.title,
            logicalFrameTopLeft: GlobalEventTapTopLeftRect(
                x: window.frameAppKit.x,
                y: window.frameAppKit.y,
                width: window.frameAppKit.width,
                height: window.frameAppKit.height
            )
        )
        let modelSize = ScreenshotFitRule().predictedModelSize(for: targetWindow.logicalFrameTopLeft)
        guard let image = modelFacingImage(
            rawImage: rawImage,
            modelSize: modelSize,
            windowFrameAppKit: CGRect(
                x: window.frameAppKit.x,
                y: window.frameAppKit.y,
                width: window.frameAppKit.width,
                height: window.frameAppKit.height
            ),
            cursorSnapshots: [],
            includeCursorOverlay: false
        ) else {
            return EvidenceCapture(
                image: nil,
                diagnostic: "Clean post-click capture failed while normalizing the raw window image."
            )
        }
        return EvidenceCapture(image: image, diagnostic: nil)
    }

    static func capture(
        window: ResolvedWindowDTO,
        stateToken: String,
        imageMode: ImageMode,
        includeRawRetinaCapture: Bool = false,
        includeCursorOverlay: Bool = true,
        attachedSurfaces: [AttachedSurfaceDTO] = [],
        rawCaptureProvider: (() -> Result<CGWindowCapture, CGWindowCaptureError>)? = nil,
        cursorSnapshots providedCursorSnapshots: [CursorSnapshot]? = nil
    ) -> ScreenshotDTO {
        if imageMode == .omit {
            return makeResponse(
                status: "omitted",
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: nil
            )
        }

        let rootFrame = CGRect(
            x: window.frameAppKit.x,
            y: window.frameAppKit.y,
            width: window.frameAppKit.width,
            height: window.frameAppKit.height
        )
        let attachedRecords = AttachedSurfaceCompositionPlanner.records(
            ownerPID: window.pid,
            rootWindowNumber: window.windowNumber,
            rootFrame: rootFrame,
            surfaces: attachedSurfaces,
            inventory: CGWindowInventory.current(onScreenOnly: true)
        )
        let rawCapture = rawCaptureProvider?() ?? CGWindowCaptureService.captureComposite(
            rootWindowNumber: window.windowNumber,
            rootFrame: rootFrame,
            attachedRecords: attachedRecords
        )
        let rawImage: CGImage
        let captureWarnings: [String]
        switch rawCapture {
        case let .success(capture):
            rawImage = capture.image
            captureWarnings = capture.warnings
        case let .failure(error):
            let status: String
            switch error {
            case .permissionDenied:
                status = "permission_denied"
            default:
                status = "capture_failed"
            }
            return makeResponse(
                status: status,
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: error.description
            )
        }

        let targetWindow = TargetWindowIdentity(
            bundleID: window.bundleID,
            pid: window.pid,
            windowNumber: window.windowNumber,
            title: window.title,
            logicalFrameTopLeft: GlobalEventTapTopLeftRect(
                x: window.frameAppKit.x,
                y: window.frameAppKit.y,
                width: window.frameAppKit.width,
                height: window.frameAppKit.height
            )
        )
        let fitRule = ScreenshotFitRule()
        let modelSize = fitRule.predictedModelSize(for: targetWindow.logicalFrameTopLeft)

        let windowFrameAppKit = CGRect(
            x: window.frameAppKit.x,
            y: window.frameAppKit.y,
            width: window.frameAppKit.width,
            height: window.frameAppKit.height
        )
        let cursorSnapshots = includeCursorOverlay
            ? (providedCursorSnapshots ?? CursorRuntime.snapshots(forWindowNumber: window.windowNumber))
            : []
        guard let modelImageResult = makeModelFacingImage(
            rawImage: rawImage,
            modelSize: modelSize,
            windowFrameAppKit: windowFrameAppKit,
            cursorSnapshots: cursorSnapshots,
            includeCursorOverlay: includeCursorOverlay
        ) else {
            return makeResponse(
                status: "normalize_failed",
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: "Failed to normalize the raw capture into the model-facing screenshot fit."
            )
        }
        let modelImage = modelImageResult.image
        let cursorOverlayError = modelImageResult.cursorOverlayError

        guard let modelPNGData = NSBitmapImageRep(cgImage: modelImage).representation(
            using: .png,
            properties: [:]
        ) else {
            return makeResponse(
                status: "encode_failed",
                image: nil,
                rawRetinaCapture: nil,
                coordinateContract: nil,
                captureError: "Failed to encode the captured image as PNG."
            )
        }

        let rawPNGData = includeRawRetinaCapture
            ? NSBitmapImageRep(cgImage: rawImage).representation(using: .png, properties: [:])
            : nil

        var modelImagePath: String?
        var rawImagePath: String?
        do {
            let capturesDirectory = FileManager.default.temporaryDirectory
                .appending(path: "background-computer-use", directoryHint: .isDirectory)
                .appending(path: "captures", directoryHint: .isDirectory)
            let modelDestination = capturesDirectory.appending(path: "\(window.windowID)-\(stateToken)-model.png")
            try SecureFileWriter.write(modelPNGData, to: modelDestination)
            modelImagePath = modelDestination.path

            if let rawPNGData {
                let rawDestination = capturesDirectory.appending(path: "\(window.windowID)-\(stateToken)-raw.png")
                try SecureFileWriter.write(rawPNGData, to: rawDestination)
                rawImagePath = rawDestination.path
            } else {
                rawImagePath = nil
            }
        } catch {
            modelImagePath = nil
            rawImagePath = nil
        }

        let rawPixelSize = includeRawRetinaCapture
            ? PixelSize(width: rawImage.width, height: rawImage.height)
            : nil
        let modelPixelSize = PixelSize(width: modelImage.width, height: modelImage.height)
        let coordinateContract: ScreenshotCoordinateContract?
        do {
            var coordinateNotes = [
                "Model-facing screenshot uses the validated 768/2048 fit rule.",
            ]
            if cursorSnapshots.isEmpty == false, cursorOverlayError == nil {
                coordinateNotes.append(
                    "Model-facing screenshot includes \(cursorSnapshots.count) composited virtual cursor overlay(s)."
                )
            }
            coordinateContract = try ScreenshotCoordinateContract.make(
                stateToken: stateToken,
                targetWindow: targetWindow,
                modelFacingPath: modelImagePath,
                modelFacingPixelSize: modelPixelSize,
                rawPath: rawImagePath,
                rawPixelSize: rawPixelSize,
                fitRule: fitRule,
                notes: coordinateNotes
            )
        } catch {
            coordinateContract = nil
        }

        let image = ScreenshotImageDTO(
            imagePath: modelImagePath,
            imageBase64: imageMode == .base64 ? modelPNGData.base64EncodedString() : nil,
            mimeType: "image/png",
            pixelWidth: modelImage.width,
            pixelHeight: modelImage.height,
            coordinateOrigin: .topLeft,
            coordinateSpace: .modelFacingScreenshot,
            captureKind: "model-facing-window-fit"
        )
        let rawRetinaCapture: ScreenshotImageDTO?
        if includeRawRetinaCapture {
            rawRetinaCapture = ScreenshotImageDTO(
                imagePath: rawImagePath,
                imageBase64: imageMode == .base64 ? rawPNGData?.base64EncodedString() : nil,
                mimeType: "image/png",
                pixelWidth: rawImage.width,
                pixelHeight: rawImage.height,
                coordinateOrigin: .topLeft,
                coordinateSpace: .rawRetinaCapture,
                captureKind: "raw-retina-window-capture"
            )
        } else {
            rawRetinaCapture = nil
        }

        return makeResponse(
            status: "captured",
            image: image,
            rawRetinaCapture: rawRetinaCapture,
            coordinateContract: coordinateContract,
            captureError: captureError(
                modelImagePath: modelImagePath,
                rawImagePath: rawImagePath,
                rawRequested: includeRawRetinaCapture,
                rawEncoded: rawPNGData != nil,
                coordinateContract: coordinateContract,
                cursorOverlayError: cursorOverlayError,
                captureWarnings: captureWarnings
            )
        )
    }

    static func modelFacingImage(
        rawImage: CGImage,
        modelSize: PixelSize,
        windowFrameAppKit: CGRect,
        cursorSnapshots: [CursorSnapshot],
        includeCursorOverlay: Bool
    ) -> CGImage? {
        makeModelFacingImage(
            rawImage: rawImage,
            modelSize: modelSize,
            windowFrameAppKit: windowFrameAppKit,
            cursorSnapshots: cursorSnapshots,
            includeCursorOverlay: includeCursorOverlay
        )?.image
    }

    private struct ModelFacingImageResult {
        let image: CGImage
        let cursorOverlayError: String?
    }

    private static func makeModelFacingImage(
        rawImage: CGImage,
        modelSize: PixelSize,
        windowFrameAppKit: CGRect,
        cursorSnapshots: [CursorSnapshot],
        includeCursorOverlay: Bool
    ) -> ModelFacingImageResult? {
        guard let modelImage = resize(rawImage, to: modelSize) else {
            return nil
        }
        guard includeCursorOverlay, cursorSnapshots.isEmpty == false else {
            return ModelFacingImageResult(image: modelImage, cursorOverlayError: nil)
        }
        guard let compositedImage = CursorScreenshotCompositor.compositedImage(
            baseImage: modelImage,
            windowFrameAppKit: windowFrameAppKit,
            snapshots: cursorSnapshots
        ) else {
            return ModelFacingImageResult(
                image: modelImage,
                cursorOverlayError: "Failed to composite \(cursorSnapshots.count) virtual cursor overlay(s) onto the model-facing screenshot."
            )
        }
        return ModelFacingImageResult(image: compositedImage, cursorOverlayError: nil)
    }

    private static func resize(_ image: CGImage, to pixelSize: PixelSize) -> CGImage? {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize.width,
            pixelsHigh: pixelSize.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmapRep else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(
                in: NSRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height),
                from: NSRect(x: 0, y: 0, width: image.width, height: image.height),
                operation: .copy,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep.cgImage
    }

    private static func captureError(
        modelImagePath: String?,
        rawImagePath: String?,
        rawRequested: Bool,
        rawEncoded: Bool,
        coordinateContract: ScreenshotCoordinateContract?,
        cursorOverlayError: String?,
        captureWarnings: [String]
    ) -> String? {
        var errors: [String] = []
        errors.append(contentsOf: captureWarnings)
        if modelImagePath == nil {
            errors.append("Captured and normalized the image but failed to persist the model-facing PNG artifact.")
        }
        if rawRequested, rawEncoded == false {
            errors.append("Captured the raw image but failed to encode the raw Retina diagnostic PNG.")
        }
        if rawRequested, rawEncoded, rawImagePath == nil {
            errors.append("Captured the raw image but failed to persist the raw Retina diagnostic PNG.")
        }
        if coordinateContract == nil {
            errors.append("Captured the image but failed to build the screenshot coordinate contract.")
        }
        if let cursorOverlayError {
            errors.append(cursorOverlayError)
        }
        return errors.isEmpty ? nil : errors.joined(separator: " ")
    }

    private static func makeResponse(
        status: String,
        image: ScreenshotImageDTO?,
        rawRetinaCapture: ScreenshotImageDTO?,
        coordinateContract: ScreenshotCoordinateContract?,
        captureError: String?
    ) -> ScreenshotDTO {
        ScreenshotDTO(
            status: status,
            image: image,
            rawRetinaCapture: rawRetinaCapture,
            coordinateContract: coordinateContract,
            captureError: captureError
        )
    }
}

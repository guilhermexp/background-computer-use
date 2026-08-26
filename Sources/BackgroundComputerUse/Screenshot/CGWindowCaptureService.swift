import AppKit
import CoreGraphics
import Darwin
import Foundation

struct CGWindowCapture {
    let image: CGImage
    let windowNumber: Int
    let warnings: [String]
}

struct CGAttachedSurfaceCapture {
    let capture: CGWindowCapture
    let frameAppKit: CGRect
}

enum CGWindowCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case symbolUnavailable
    case captureReturnedNil(windowNumber: Int)
    case compositionFailed(windowNumber: Int)

    var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required to capture window screenshots."
        case .symbolUnavailable:
            return "Could not resolve CGWindowListCreateImage from CoreGraphics."
        case let .captureReturnedNil(windowNumber):
            return "CGWindowListCreateImage returned nil for windowNumber \(windowNumber)."
        case let .compositionFailed(windowNumber):
            return "Could not compose attached surfaces over windowNumber \(windowNumber)."
        }
    }
}

enum CGWindowCaptureService {
    private typealias CreateImageFunction = @convention(c) (
        CGRect,
        UInt32,
        UInt32,
        UInt32
    ) -> Unmanaged<CGImage>?

    static func captureImage(
        window: ResolvedWindowDTO,
        attachedSurfaces: [AttachedSurfaceDTO] = []
    ) -> CGImage? {
        switch captureImageResult(window: window, attachedSurfaces: attachedSurfaces) {
        case let .success(capture):
            return capture.image
        case .failure:
            return nil
        }
    }

    static func captureImageResult(
        window: ResolvedWindowDTO,
        attachedSurfaces: [AttachedSurfaceDTO] = []
    ) -> Result<CGWindowCapture, CGWindowCaptureError> {
        let rootFrame = CGRect(
            x: window.frameAppKit.x,
            y: window.frameAppKit.y,
            width: window.frameAppKit.width,
            height: window.frameAppKit.height
        )
        let records = AttachedSurfaceCompositionPlanner.records(
            ownerPID: window.pid,
            rootWindowNumber: window.windowNumber,
            rootFrame: rootFrame,
            surfaces: attachedSurfaces,
            inventory: CGWindowInventory.current(onScreenOnly: true)
        )
        return captureComposite(
            rootWindowNumber: window.windowNumber,
            rootFrame: rootFrame,
            attachedRecords: records
        )
    }

    static func capture(windowNumber: Int) -> Result<CGWindowCapture, CGWindowCaptureError> {
        guard ScreenCaptureAuthorization.isAuthorized() else {
            return .failure(.permissionDenied)
        }

        guard let createImage = resolveCreateImage() else {
            return .failure(.symbolUnavailable)
        }

        let listOption = CGWindowListOption.optionIncludingWindow.rawValue
        let imageOption = CGWindowImageOption.boundsIgnoreFraming.rawValue |
            CGWindowImageOption.bestResolution.rawValue

        guard let unmanagedImage = createImage(
            .null,
            listOption,
            UInt32(windowNumber),
            imageOption
        ) else {
            return .failure(.captureReturnedNil(windowNumber: windowNumber))
        }

        return .success(
            CGWindowCapture(
                image: unmanagedImage.takeRetainedValue(),
                windowNumber: windowNumber,
                warnings: []
            )
        )
    }

    static func captureComposite(
        rootWindowNumber: Int,
        rootFrame: CGRect,
        attachedRecords: [CGWindowRecord]
    ) -> Result<CGWindowCapture, CGWindowCaptureError> {
        let rootResult = capture(windowNumber: rootWindowNumber)
        guard attachedRecords.isEmpty == false else { return rootResult }
        guard case let .success(rootCapture) = rootResult else { return rootResult }

        var surfaceCaptures: [CGAttachedSurfaceCapture] = []
        var warnings: [String] = []
        for record in attachedRecords {
            switch capture(windowNumber: record.windowNumber) {
            case let .success(surfaceCapture):
                surfaceCaptures.append(
                    CGAttachedSurfaceCapture(
                        capture: surfaceCapture,
                        frameAppKit: record.frameAppKit
                    )
                )
            case let .failure(error):
                warnings.append(
                    "Attached surface windowNumber \(record.windowNumber) was omitted from the composite: \(error.description)"
                )
            }
        }
        return composite(
            rootCapture: rootCapture,
            rootFrame: rootFrame,
            surfaces: surfaceCaptures,
            warnings: warnings
        )
    }

    static func composite(
        rootCapture: CGWindowCapture,
        rootFrame: CGRect,
        surfaces: [CGAttachedSurfaceCapture],
        warnings: [String] = []
    ) -> Result<CGWindowCapture, CGWindowCaptureError> {
        guard surfaces.isEmpty == false else {
            return .success(
                CGWindowCapture(
                    image: rootCapture.image,
                    windowNumber: rootCapture.windowNumber,
                    warnings: rootCapture.warnings + warnings
                )
            )
        }

        let width = rootCapture.image.width
        let height = rootCapture.image.height
        guard rootFrame.width > 0,
              rootFrame.height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return .failure(.compositionFailed(windowNumber: rootCapture.windowNumber))
        }

        let pixelWidth = CGFloat(width)
        let pixelHeight = CGFloat(height)
        let scaleX = pixelWidth / rootFrame.width
        let scaleY = pixelHeight / rootFrame.height
        context.interpolationQuality = .high
        context.draw(
            rootCapture.image,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
        for surface in surfaces {
            let frame = surface.frameAppKit
            context.draw(
                surface.capture.image,
                in: CGRect(
                    x: (frame.minX - rootFrame.minX) * scaleX,
                    y: (frame.minY - rootFrame.minY) * scaleY,
                    width: frame.width * scaleX,
                    height: frame.height * scaleY
                )
            )
        }

        guard let image = context.makeImage() else {
            return .failure(.compositionFailed(windowNumber: rootCapture.windowNumber))
        }
        return .success(
            CGWindowCapture(
                image: image,
                windowNumber: rootCapture.windowNumber,
                warnings: rootCapture.warnings + warnings
            )
        )
    }

    private static let createImageFunction: CreateImageFunction? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ) else {
            return nil
        }

        guard let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }

        return unsafeBitCast(symbol, to: CreateImageFunction.self)
    }()

    private static func resolveCreateImage() -> CreateImageFunction? {
        createImageFunction
    }
}

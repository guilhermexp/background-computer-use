import ApplicationServices
import CoreGraphics
import CryptoKit
import Foundation

struct AXAttachedSurfaceRecord {
    let element: AXUIElement
    let dto: AttachedSurfaceDTO
}

struct AXAttachedSurfaceDiscovery {
    func surfaces(for window: AXUIElement, ownerPID: pid_t) -> [AttachedSurfaceDTO] {
        records(for: window, ownerPID: ownerPID).map(\.dto)
    }

    func records(for window: AXUIElement, ownerPID: pid_t) -> [AXAttachedSurfaceRecord] {
        let rootFrame = AXHelpers.frame(window)
        let explicitSheets = AXHelpers.elementArrayAttribute(window, attribute: "AXSheets" as CFString)
        let childSurfaces = AXHelpers.children(window).filter(Self.isAttachedSurface)

        var seen = Set<CFHashCode>()
        return (explicitSheets + childSurfaces)
            .compactMap { element -> AXAttachedSurfaceRecord? in
                let identity = CFHash(element)
                guard seen.insert(identity).inserted,
                      let frame = AXHelpers.frame(element),
                      frame.width > 0,
                      frame.height > 0,
                      rootFrame.map({ $0.intersects(frame) }) ?? true else {
                    return nil
                }

                let role = AXHelpers.stringAttribute(element, attribute: kAXRoleAttribute as CFString) ?? "AXSurface"
                let title = AXHelpers.stringAttribute(element, attribute: kAXTitleAttribute as CFString)
                let windowNumber = Self.windowNumber(for: element)
                return AXAttachedSurfaceRecord(
                    element: element,
                    dto: AttachedSurfaceDTO(
                        id: Self.surfaceID(
                            ownerPID: ownerPID,
                            role: role,
                            title: title,
                            frame: frame,
                            windowNumber: windowNumber
                        ),
                        role: role,
                        title: title,
                        frameAppKit: RectDTO(
                            x: frame.minX,
                            y: frame.minY,
                            width: frame.width,
                            height: frame.height
                        ),
                        windowNumber: windowNumber,
                        isLiveActionSurface: Self.containsEnabledAction(element)
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.dto.frameAppKit.y != rhs.dto.frameAppKit.y {
                    return lhs.dto.frameAppKit.y > rhs.dto.frameAppKit.y
                }
                return lhs.dto.id < rhs.dto.id
            }
    }

    private static func isAttachedSurface(_ element: AXUIElement) -> Bool {
        let role = AXHelpers.stringAttribute(element, attribute: kAXRoleAttribute as CFString)
        return role == kAXSheetRole as String || role == "AXDialog"
    }

    private static func containsEnabledAction(_ root: AXUIElement) -> Bool {
        var pending = [root]
        var nextIndex = 0
        var visited = Set<CFHashCode>()
        var examined = 0
        while nextIndex < pending.count, examined < 256 {
            let element = pending[nextIndex]
            nextIndex += 1
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }
            examined += 1

            if AXHelpers.boolAttribute(element, attribute: kAXEnabledAttribute as CFString) != false,
               AXHelpers.actionNames(element).isEmpty == false {
                return true
            }
            pending.append(contentsOf: AXHelpers.children(element))
        }
        return false
    }

    private static func windowNumber(for element: AXUIElement) -> Int? {
        guard let privateGetWindow = AXHelpers.privateGetWindow else { return nil }
        var windowID = CGWindowID(0)
        guard privateGetWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        return Int(windowID)
    }

    private static func surfaceID(
        ownerPID: pid_t,
        role: String,
        title: String?,
        frame: CGRect,
        windowNumber: Int?
    ) -> String {
        let payload = [
            String(ownerPID),
            role,
            title ?? "",
            windowNumber.map(String.init) ?? "",
            String(format: "%.1f,%.1f,%.1f,%.1f", frame.minX, frame.minY, frame.width, frame.height)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "surface_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

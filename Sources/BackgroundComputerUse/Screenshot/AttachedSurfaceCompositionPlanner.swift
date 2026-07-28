import CoreGraphics
import Foundation

enum AttachedSurfaceCompositionPlanner {
    static func records(
        ownerPID: pid_t,
        rootWindowNumber: Int,
        rootFrame: CGRect,
        surfaces: [AttachedSurfaceDTO],
        inventory: [CGWindowRecord]
    ) -> [CGWindowRecord] {
        let requestedWindowNumbers = Set(surfaces.compactMap(\.windowNumber))
        guard requestedWindowNumbers.isEmpty == false else { return [] }

        return inventory.filter { record in
            record.ownerPID == ownerPID &&
            record.windowNumber != rootWindowNumber &&
            requestedWindowNumbers.contains(record.windowNumber) &&
            record.isOnScreen &&
            record.frameAppKit.width > 0 &&
            record.frameAppKit.height > 0 &&
            record.frameAppKit.intersects(rootFrame)
        }
        .sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex > rhs.orderIndex
            }
            return lhs.windowNumber < rhs.windowNumber
        }
    }
}

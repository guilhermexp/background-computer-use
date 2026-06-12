import ApplicationServices
import Foundation

/// Filters a discovered window list down to real windows (AX role `AXWindow`) with unique
/// backing window IDs, so auxiliary AX containers (e.g. the Finder desktop `AXScrollArea`)
/// and duplicate elements that resolve to the same window are not listed twice.
enum WindowListFilter {
    static func realUniqueWindows<Element>(
        _ records: [Element],
        role: (Element) -> String?,
        windowNumber: (Element) -> Int
    ) -> (kept: [Element], excludedNonWindow: Int, excludedDuplicate: Int) {
        var seenWindowNumbers = Set<Int>()
        var kept: [Element] = []
        var excludedNonWindow = 0
        var excludedDuplicate = 0

        for record in records {
            guard role(record) == (kAXWindowRole as String) else {
                excludedNonWindow += 1
                continue
            }
            guard seenWindowNumbers.insert(windowNumber(record)).inserted else {
                excludedDuplicate += 1
                continue
            }
            kept.append(record)
        }

        return (kept, excludedNonWindow, excludedDuplicate)
    }
}

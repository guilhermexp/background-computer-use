import Foundation

public final class ActivityHistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var stored: [ActivityEnvelope] = []
    private var latestScreenshotByWindow: [String: String] = [:]

    public init(capacity: Int = 200) {
        self.capacity = max(capacity, 1)
    }

    public func append(_ activity: ActivityEnvelope) {
        lock.lock()
        stored.insert(activity, at: 0)
        if stored.count > capacity {
            stored.removeLast(stored.count - capacity)
        }
        if let windowID = activity.windowID, let screenshotPath = activity.screenshotPath {
            latestScreenshotByWindow[windowID] = screenshotPath
        }
        lock.unlock()
    }

    public func activities(windowID: String? = nil) -> [ActivityEnvelope] {
        lock.lock()
        defer { lock.unlock() }
        guard let windowID else { return stored }
        return stored.filter { $0.windowID == windowID }
    }

    public func latestScreenshotPath(windowID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return latestScreenshotByWindow[windowID]
    }
}

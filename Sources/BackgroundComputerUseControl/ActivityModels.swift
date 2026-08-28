import Foundation

public struct ActivityEnvelope: Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let appBundleID: String?
    public let windowID: String?
    public let action: String
    public let verdict: String
    public let summary: String
    public let screenshotPath: String?
    public let timestamp: Date

    public init(
        id: String,
        sessionID: String,
        appBundleID: String?,
        windowID: String?,
        action: String,
        verdict: String,
        summary: String,
        screenshotPath: String?,
        timestamp: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.appBundleID = appBundleID
        self.windowID = windowID
        self.action = action
        self.verdict = verdict
        self.summary = String(summary.prefix(240))
        self.screenshotPath = screenshotPath
        self.timestamp = timestamp
    }
}

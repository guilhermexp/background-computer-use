import Foundation

public struct AnnotateWindowResponse: Encodable, Sendable {
    public let contractVersion: String
    public let stateToken: String
    public let window: ResolvedWindowDTO
    public let screenshot: ScreenshotDTO
    public let annotatedImage: ScreenshotImageDTO?
    public let marks: [WindowAnnotationMarkDTO]
    public let truncated: Bool
    public let maxMarks: Int
    public let backgroundSafety: BackgroundSafetyDTO
    public let performance: ReadPerformanceDTO
    public let notes: [String]
}

public struct WindowAnnotationMarkDTO: Encodable, Sendable {
    public let markID: Int
    public let displayIndex: Int?
    public let nodeID: String?
    public let refetchFingerprint: String?
    public let target: ActionTargetRequestDTO?
    public let role: String
    public let title: String?
    public let description: String?
    public let valuePreview: String?
    public let point: PointDTO
    public let rect: RectDTO?
    public let source: String
}

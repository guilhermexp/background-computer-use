import Foundation

public struct WaitForResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let conditionMet: Bool
    public let elapsedMs: Double
    public let summary: String
    public let state: AXPipelineV2Response
    public let notes: [String]
}

public struct ReadTextResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let summary: String
    public let window: ResolvedWindowDTO
    public let target: AXActionTargetSnapshotDTO
    public let chunk: TextChunkDTO
    public let warnings: [String]
}

public struct TextSelectionRangeResponseDTO: Encodable, Sendable {
    public let location: Int
    public let length: Int
}

public struct SelectTextResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let classification: ActionClassificationDTO
    public let failureDomain: ActionFailureDomainDTO?
    public let summary: String
    public let window: ResolvedWindowDTO?
    public let target: AXActionTargetSnapshotDTO?
    public let selectedRange: TextSelectionRangeResponseDTO?
    public let preStateToken: String?
    public let postStateToken: String?
    public let warnings: [String]
    public let notes: [String]
}

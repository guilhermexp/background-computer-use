import Foundation

public enum PasteFormatDTO: String, Codable, Sendable {
    case text
    case markdown
    case html
}

public struct PasteRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let interactionToken: String?
    public let target: ActionTargetRequestDTO
    public let content: String
    public let format: PasteFormatDTO
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        interactionToken: String? = nil,
        target: ActionTargetRequestDTO,
        content: String,
        format: PasteFormatDTO,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.interactionToken = interactionToken
        self.target = target
        self.content = content
        self.format = format
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.debug = debug
        self.confirm = confirm
    }
}

public struct PasteVerificationDTO: Encodable, Sendable {
    public let beforeValue: String?
    public let expectedValue: String?
    public let afterValue: String?
    public let exactValueMatch: Bool
    public let targetRelocated: Bool
    public let refreshedTargetMatchStrategy: String?
}

public struct PasteResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let classification: ActionClassificationDTO
    public let failureDomain: ActionFailureDomainDTO?
    public let summary: String
    public let window: ResolvedWindowDTO?
    public let target: AXActionTargetSnapshotDTO?
    public let format: PasteFormatDTO
    public let contentLength: Int
    public let dispatchPrimitive: String?
    public let dispatchSucceeded: Bool?
    public let pasteboardRestored: Bool
    public let preStateToken: String?
    public let postStateToken: String?
    public let cursor: ActionCursorTargetResponseDTO
    public let warnings: [String]
    public let notes: [String]
    public let backgroundSafety: TypeTextBackgroundSafetyDTO?
    public let verification: PasteVerificationDTO?
}

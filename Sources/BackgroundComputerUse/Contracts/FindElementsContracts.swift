import Foundation

public struct FindElementsRequest: Codable, Sendable {
    public let window: String
    public let role: String?
    public let text: String?
    public let includeMenuBar: Bool?
    public let webTraversal: AXWebTraversalMode?
    public let maxNodes: Int?

    public init(
        window: String,
        role: String? = nil,
        text: String? = nil,
        includeMenuBar: Bool? = nil,
        webTraversal: AXWebTraversalMode? = nil,
        maxNodes: Int? = nil
    ) {
        self.window = window
        self.role = role
        self.text = text
        self.includeMenuBar = includeMenuBar
        self.webTraversal = webTraversal
        self.maxNodes = maxNodes
    }
}

public struct FindElementsQueryDTO: Encodable, Sendable {
    public let role: String?
    public let text: String?

    public init(role: String?, text: String?) {
        self.role = role
        self.text = text
    }
}

public struct FindElementsResponse: Encodable, Sendable {
    public let contractVersion: String
    public let stateToken: String
    public let interactionToken: String
    public let window: ResolvedWindowDTO
    public let query: FindElementsQueryDTO
    public let matches: [AXPipelineV2SurfaceNodeDTO]
    public let matchCount: Int
    public let summary: String
    public let notes: [String]

    public init(
        contractVersion: String,
        stateToken: String,
        interactionToken: String,
        window: ResolvedWindowDTO,
        query: FindElementsQueryDTO,
        matches: [AXPipelineV2SurfaceNodeDTO],
        matchCount: Int,
        summary: String,
        notes: [String]
    ) {
        self.contractVersion = contractVersion
        self.stateToken = stateToken
        self.interactionToken = interactionToken
        self.window = window
        self.query = query
        self.matches = matches
        self.matchCount = matchCount
        self.summary = summary
        self.notes = notes
    }
}

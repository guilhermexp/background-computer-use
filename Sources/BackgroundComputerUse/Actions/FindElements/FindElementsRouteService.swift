import Foundation

enum FindElementsRouteError: Error, Equatable {
    case invalidRequest(String)
}

struct FindElementsRouteService {
    private let windowStateService: WindowStateService

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        windowStateService = WindowStateService(executionOptions: executionOptions)
    }

    func findElements(request: FindElementsRequest) throws -> FindElementsResponse {
        _ = try Self.query(from: request)
        let state = try windowStateService.getWindowState(
            request: GetWindowStateRequest(
                window: request.window,
                includeMenuBar: request.includeMenuBar,
                webTraversal: request.webTraversal,
                maxNodes: request.maxNodes,
                imageMode: .omit
            )
        )
        return try Self.response(from: state, request: request)
    }

    static func response(
        from state: GetWindowStateResponse,
        request: FindElementsRequest
    ) throws -> FindElementsResponse {
        let query = try query(from: request)
        let matches = state.tree.nodes.filter { node in
            nodeMatches(node: node, query: query)
        }
        let summary = matches.isEmpty
            ? "No elements matched the query."
            : "Matched \(matches.count) element\(matches.count == 1 ? "" : "s")."

        return FindElementsResponse(
            contractVersion: state.contractVersion,
            stateToken: state.stateToken,
            interactionToken: state.interactionToken,
            window: state.window,
            query: query,
            matches: matches,
            matchCount: matches.count,
            summary: summary,
            notes: [
                "Matches, stateToken, and interactionToken come from the same state capture."
            ]
        )
    }

    private static func query(from request: FindElementsRequest) throws -> FindElementsQueryDTO {
        let role = trimmed(request.role)
        let text = trimmed(request.text)
        guard role != nil || text != nil else {
            throw FindElementsRouteError.invalidRequest(
                "find_elements requires a non-empty role and/or text query."
            )
        }
        return FindElementsQueryDTO(role: role, text: text)
    }

    private static func nodeMatches(
        node: AXPipelineV2SurfaceNodeDTO,
        query: FindElementsQueryDTO
    ) -> Bool {
        if let role = query.role {
            let expected = normalized(role)
            let roles = [node.displayRole, node.rawRole]
                .compactMap { $0 }
                .map(normalized)
            guard roles.contains(expected) || roles.contains("ax\(expected)") else {
                return false
            }
        }
        if let text = query.text {
            let searchable = [node.title, node.description, node.help, node.value?.preview]
                .compactMap { $0 }
                .joined(separator: " ")
            guard normalized(searchable).contains(normalized(text)) else {
                return false
            }
        }
        return true
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

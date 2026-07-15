import Foundation

struct WaitForMatcherNode: Sendable {
    let role: String?
    let title: String?
    let description: String?
    let valuePreview: String?
}

enum WaitForMatcher {
    static func matches(
        _ node: WaitForMatcherNode,
        role: String?,
        label: String?,
        valueContains: String?
    ) -> Bool {
        if let role,
           normalized(node.role) != normalized(role) {
            return false
        }

        if let label {
            let labelNeedle = normalized(label)
            let labelHaystack = [
                node.title,
                node.description,
            ]
            .compactMap(normalized)
            .joined(separator: " ")
            guard labelHaystack.contains(labelNeedle) else {
                return false
            }
        }

        if let valueContains {
            let valueNeedle = normalized(valueContains)
            guard normalized(node.valuePreview).contains(valueNeedle) else {
                return false
            }
        }

        return true
    }

    static func contains(_ haystack: String?, needle: String?) -> Bool {
        guard let needle else {
            return true
        }

        return normalized(haystack).contains(normalized(needle))
    }

    static func anyNodeURLContains(_ nodes: [AXPipelineV2SurfaceNodeDTO], needle: String?) -> Bool {
        guard let needle else {
            return true
        }

        let normalizedNeedle = normalized(needle)
        return nodes.contains { normalized($0.url).contains(normalizedNeedle) }
    }

    static func conditionMatches(
        state: AXPipelineV2Response,
        role: String?,
        label: String?,
        valueContains: String?,
        windowTitleContains: String?,
        windowTitleChanged: Bool,
        baselineWindowTitle: String?,
        urlContains: String?,
        textContains: String?
    ) -> Bool {
        let needsElementMatch = role != nil || label != nil || valueContains != nil
        let elementMatches = needsElementMatch
            ? state.tree.nodes.contains {
                matches(
                    WaitForMatcherNode(surfaceNode: $0),
                    role: role,
                    label: label,
                    valueContains: valueContains
                )
            }
            : true

        let titleContains = contains(state.window.title, needle: windowTitleContains)
        let titleChanged = windowTitleChanged
            ? normalized(state.window.title) != normalized(baselineWindowTitle)
            : true
        let urlMatches = anyNodeURLContains(state.tree.nodes, needle: urlContains)
        let textMatches = contains(state.tree.renderedText, needle: textContains)

        return elementMatches && titleContains && titleChanged && urlMatches && textMatches
    }

    static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

extension WaitForMatcherNode {
    init(surfaceNode node: AXPipelineV2SurfaceNodeDTO) {
        self.init(
            role: node.displayRole,
            title: node.title,
            description: node.description,
            valuePreview: node.value?.preview
        )
    }
}

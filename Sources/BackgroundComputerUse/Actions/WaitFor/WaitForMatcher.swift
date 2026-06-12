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

    private static func normalized(_ value: String?) -> String {
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

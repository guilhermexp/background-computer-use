import Foundation

struct AXTreeScopeFilter {
    struct Result {
        let tree: AXPipelineV2TreeDTO
        let note: String
    }

    static func filter(_ tree: AXPipelineV2TreeDTO, target: ActionTargetRequestDTO) -> Result? {
        guard let root = node(in: tree, matching: target) else {
            return nil
        }

        var included = Set<Int>()
        var stack = [root.projectedIndex]
        while let current = stack.popLast() {
            guard included.insert(current).inserted,
                  let node = tree.nodes.first(where: { $0.projectedIndex == current }) else {
                continue
            }
            stack.append(contentsOf: node.childIndices)
        }

        let nodes = tree.nodes.filter { included.contains($0.projectedIndex) }
        let lineMappings = tree.lineMappings.filter { included.contains($0.projectedIndex) }
        let renderedText = render(nodes: nodes)

        return Result(
            tree: AXPipelineV2TreeDTO(
                nodeCount: nodes.count,
                truncated: tree.truncated,
                renderedText: renderedText,
                nodes: nodes,
                lineMappings: lineMappings,
                profile: tree.profile
            ),
            note: "Tree scoped to \(target.summary); \(nodes.count) of \(tree.nodes.count) nodes returned."
        )
    }

    private static func node(in tree: AXPipelineV2TreeDTO, matching target: ActionTargetRequestDTO) -> AXPipelineV2SurfaceNodeDTO? {
        switch target.kind {
        case .displayIndex:
            guard let displayIndex = target.displayIndex else {
                return nil
            }
            return tree.nodes.first { $0.displayIndex == displayIndex }
        case .nodeID:
            return tree.nodes.first { $0.nodeID == target.value }
        case .refetchFingerprint:
            return tree.nodes.first { $0.refetchFingerprint == target.value }
        }
    }

    private static func render(nodes: [AXPipelineV2SurfaceNodeDTO]) -> String {
        nodes
            .sorted {
                ($0.displayIndex ?? $0.projectedIndex, $0.projectedIndex) <
                    ($1.displayIndex ?? $1.projectedIndex, $1.projectedIndex)
            }
            .map { node in
                let index = node.displayIndex.map { "[\($0)] " } ?? ""
                let label = [node.title, node.description, node.value?.preview]
                    .compactMap { $0 }
                    .first { $0.isEmpty == false }
                return "\(index)\(node.displayRole)\(label.map { " \"\($0)\"" } ?? "")"
            }
            .joined(separator: "\n")
    }
}

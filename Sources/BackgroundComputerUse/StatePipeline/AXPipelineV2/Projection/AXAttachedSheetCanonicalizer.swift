import CoreGraphics
import Foundation

struct AXAttachedSheetProjectionNode: Sendable {
    let index: Int
    let parentIndex: Int?
    let childIndices: [Int]
    let role: String?
    let subrole: String?
    let displayRole: String
    let label: String?
    let title: String?
    let description: String?
    let isInteractive: Bool
    let frameAppKit: RectDTO?
}

struct AXAttachedSheetCanonicalizationPlan: Sendable {
    let sheetIndices: [Int]
    let duplicateRootsBySheet: [Int: [Int]]
    let foldedIndicesBySheet: [Int: [Int]]
}

enum AXAttachedSheetCanonicalizer {
    static func plan(nodes: [AXAttachedSheetProjectionNode]) -> AXAttachedSheetCanonicalizationPlan {
        let sheetIndices = nodes.indices.filter { index in
            nodes[index].role == "AXSheet" || nodes[index].subrole == "AXSheet"
        }
        guard sheetIndices.isEmpty == false else {
            return AXAttachedSheetCanonicalizationPlan(
                sheetIndices: [],
                duplicateRootsBySheet: [:],
                foldedIndicesBySheet: [:]
            )
        }

        var foldedRoots = Set<Int>()
        var duplicateRootsBySheet: [Int: [Int]] = [:]
        var foldedIndicesBySheet: [Int: [Int]] = [:]
        for sheetIndex in sheetIndices {
            guard signature(at: sheetIndex, nodes: nodes) != nil else { continue }
            for candidateIndex in nodes.indices where candidateIndex != sheetIndex {
                guard foldedRoots.contains(candidateIndex) == false,
                      isDuplicateCandidate(nodes[candidateIndex]),
                      signature(at: candidateIndex, nodes: nodes) != nil,
                      isAncestor(candidateIndex, of: sheetIndex, nodes: nodes) == false,
                      isAncestor(sheetIndex, of: candidateIndex, nodes: nodes) == false,
                      framesRepresentSameSurface(nodes[sheetIndex].frameAppKit, nodes[candidateIndex].frameAppKit) else {
                    continue
                }

                let foldedIndices = subtreeIndices(root: candidateIndex, nodes: nodes)
                foldedRoots.insert(candidateIndex)
                duplicateRootsBySheet[sheetIndex, default: []].append(candidateIndex)
                foldedIndicesBySheet[sheetIndex, default: []].append(contentsOf: foldedIndices)
            }
        }

        return AXAttachedSheetCanonicalizationPlan(
            sheetIndices: sheetIndices,
            duplicateRootsBySheet: duplicateRootsBySheet.mapValues { Array(Set($0)).sorted() },
            foldedIndicesBySheet: foldedIndicesBySheet.mapValues { Array(Set($0)).sorted() }
        )
    }

    private static func signature(
        at index: Int,
        nodes: [AXAttachedSheetProjectionNode]
    ) -> String? {
        let node = nodes[index]
        let title = normalized(node.label ?? node.title ?? node.description ?? "")
        guard title.isEmpty == false else { return nil }

        let actions = subtreeIndices(root: index, nodes: nodes)
            .filter { nodes[$0].isInteractive }
            .compactMap { descendantIndex in
                let descendant = nodes[descendantIndex]
                return descendant.label ?? descendant.title ?? descendant.description
            }
            .map(normalized)
            .filter { $0.isEmpty == false }
        let distinctActions = Array(Set(actions)).sorted()
        guard distinctActions.isEmpty == false else { return nil }
        return title + "|" + distinctActions.joined(separator: "|")
    }

    private static func isDuplicateCandidate(_ node: AXAttachedSheetProjectionNode) -> Bool {
        node.role == "AXDialog" ||
            node.role == "AXGroup" ||
            node.role == "AXWebArea" ||
            node.displayRole == "dialog"
    }

    private static func subtreeIndices(
        root: Int,
        nodes: [AXAttachedSheetProjectionNode]
    ) -> [Int] {
        var result: [Int] = []
        var pending = [root]
        var visited = Set<Int>()
        while let index = pending.popLast() {
            guard nodes.indices.contains(index), visited.insert(index).inserted else { continue }
            result.append(index)
            pending.append(contentsOf: nodes[index].childIndices)
        }
        return result
    }

    private static func isAncestor(
        _ possibleAncestor: Int,
        of index: Int,
        nodes: [AXAttachedSheetProjectionNode]
    ) -> Bool {
        var current = nodes[index].parentIndex
        while let candidate = current, nodes.indices.contains(candidate) {
            if candidate == possibleAncestor { return true }
            current = nodes[candidate].parentIndex
        }
        return false
    }

    private static func framesRepresentSameSurface(_ lhs: RectDTO?, _ rhs: RectDTO?) -> Bool {
        guard let lhs, let rhs else { return false }
        let lhsRect = CGRect(x: lhs.x, y: lhs.y, width: lhs.width, height: lhs.height)
        let rhsRect = CGRect(x: rhs.x, y: rhs.y, width: rhs.width, height: rhs.height)
        let intersection = lhsRect.intersection(rhsRect)
        guard intersection.isNull == false else { return false }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhsRect.width * lhsRect.height + rhsRect.width * rhsRect.height - intersectionArea
        guard unionArea > 0 else { return false }
        return intersectionArea / unionArea >= 0.8
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

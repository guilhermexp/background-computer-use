import ApplicationServices
import CryptoKit
import Foundation

enum InteractionToken {
    /// AppKit title-bar controls. Their internal AX subtree (the zoom button's inner AXGroup,
    /// for one) can differ between two consecutive reads of an otherwise idle window. They are
    /// never the target an OCR anchor points at, so they must not participate in identity.
    private static let windowChromeSubroles: Set<String> = [
        String(kAXCloseButtonSubrole),
        String(kAXMinimizeButtonSubrole),
        String(kAXZoomButtonSubrole),
        String(kAXFullScreenButtonSubrole),
    ]

    static func make(
        windowID: String,
        title _: String,
        frame: CGRect,
        tree: AXPipelineV2TreeDTO,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) -> String {
        var components = [
            "window:\(windowID)",
            "frame:\(rectComponent(frame))",
            "pixels:\(pixelWidth.map(String.init) ?? "nil")x\(pixelHeight.map(String.init) ?? "nil")",
            "profile:\(tree.profile ?? "nil")",
            "truncated:\(tree.truncated)",
        ]
        let retained = contentNodes(in: tree.nodes)
        // Indices are re-based on the retained set so a chrome subtree growing or shrinking
        // cannot shift the numbering of the content that follows it.
        var rebased: [Int: Int] = [:]
        for (position, node) in retained.enumerated() {
            rebased[node.projectedIndex] = position
        }
        components.append(contentsOf: retained.map { nodeComponent($0, rebased: rebased) })

        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return "it_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentNodes(in nodes: [AXPipelineV2SurfaceNodeDTO]) -> [AXPipelineV2SurfaceNodeDTO] {
        var excluded = Set<Int>()
        return nodes.filter { node in
            let isChrome = node.rawSubrole.map(windowChromeSubroles.contains) ?? false
            let underChrome = node.parentIndex.map(excluded.contains) ?? false
            if isChrome || underChrome {
                excluded.insert(node.projectedIndex)
                return false
            }
            return true
        }
    }

    private static func nodeComponent(_ node: AXPipelineV2SurfaceNodeDTO, rebased: [Int: Int]) -> String {
        let frame = node.frameAppKit.map {
            [stableNumber($0.x), stableNumber($0.y), stableNumber($0.width), stableNumber($0.height)]
                .joined(separator: ",")
        } ?? "nil"
        let activation = node.activationPointAppKit.map {
            "\(stableNumber($0.x)),\(stableNumber($0.y))"
        } ?? "nil"
        let suggested = node.suggestedInteractionPointAppKit.map {
            "\(stableNumber($0.x)),\(stableNumber($0.y))"
        } ?? "nil"
        let index: (Int) -> String = { rebased[$0].map(String.init) ?? "x" }

        var components: [String] = []
        components.append(index(node.projectedIndex))
        components.append(node.parentIndex.map(index) ?? "nil")
        components.append(String(node.depth))
        // Canonical (raw-tree) indices are positional and shift whenever any earlier raw node
        // appears or disappears; nodeID already carries the structural identity.
        components.append(node.childIndices.map(index).joined(separator: ","))
        components.append(node.displayRole)
        components.append(node.rawRole ?? "")
        components.append(node.rawSubrole ?? "")
        components.append(node.nodeID ?? "")
        components.append(node.flags.sorted().joined(separator: ","))
        components.append(node.secondaryActions.sorted().joined(separator: ","))
        components.append(frame)
        components.append(activation)
        components.append(suggested)
        components.append(String(node.childCount))
        return components.joined(separator: ":")
    }

    private static func rectComponent(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height]
            .map(stableNumber)
            .joined(separator: ",")
    }

    private static func stableNumber(_ value: Double) -> String {
        String(format: "%.3f", value.isFinite ? value : 0)
    }
}

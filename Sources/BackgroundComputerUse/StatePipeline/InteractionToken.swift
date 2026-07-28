import CryptoKit
import Foundation

enum InteractionToken {
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
        components.append(contentsOf: tree.nodes.map(nodeComponent))

        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return "it_" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func nodeComponent(_ node: AXPipelineV2SurfaceNodeDTO) -> String {
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

        var components: [String] = []
        components.append(String(node.projectedIndex))
        components.append(node.parentIndex.map(String.init) ?? "nil")
        components.append(String(node.depth))
        components.append(String(node.primaryCanonicalIndex))
        components.append(node.canonicalIndices.map(String.init).joined(separator: ","))
        components.append(node.childIndices.map(String.init).joined(separator: ","))
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

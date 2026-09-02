import Foundation
import Testing
@testable import BackgroundComputerUse

struct InteractionTokenTests {
    @Test
    func windowChromeSubtreeChangesDoNotMoveTheToken() {
        // Observed on macOS 27 with an Electron window: the AppKit full-screen (zoom) button
        // exposes an internal AXGroup that appears and disappears between consecutive reads.
        // That flapping shifted every later projectedIndex and made two back-to-back
        // get_window_state calls alternate between two tokens, so no OCR-anchor click could
        // ever pass the stale guard.
        let chromeWithInnerGroup = [
            node(index: 0, parent: nil, depth: 0, role: "full screen button", subrole: "AXFullScreenButton",
                 children: [1], frame: RectDTO(x: 57, y: 1144, width: 16, height: 16)),
            node(index: 1, parent: 0, depth: 1, role: "container", subrole: nil,
                 children: [], frame: RectDTO(x: 58, y: 1145, width: 14, height: 14)),
            node(index: 2, parent: nil, depth: 0, role: "button", subrole: nil,
                 children: [], frame: RectDTO(x: 100, y: 100, width: 80, height: 30), nodeID: "n:1"),
        ]
        let chromeWithoutInnerGroup = [
            node(index: 0, parent: nil, depth: 0, role: "full screen button", subrole: "AXFullScreenButton",
                 children: [], frame: RectDTO(x: 57, y: 1144, width: 16, height: 16)),
            node(index: 1, parent: nil, depth: 0, role: "button", subrole: nil,
                 children: [], frame: RectDTO(x: 100, y: 100, width: 80, height: 30), nodeID: "n:1"),
        ]
        let contentMoved = [
            node(index: 0, parent: nil, depth: 0, role: "full screen button", subrole: "AXFullScreenButton",
                 children: [], frame: RectDTO(x: 57, y: 1144, width: 16, height: 16)),
            node(index: 1, parent: nil, depth: 0, role: "button", subrole: nil,
                 children: [], frame: RectDTO(x: 140, y: 100, width: 80, height: 30), nodeID: "n:1"),
        ]

        let a = token(chromeWithInnerGroup)
        let b = token(chromeWithoutInnerGroup)
        let c = token(contentMoved)

        #expect(a == b)
        #expect(a != c)
    }

    private func token(_ nodes: [AXPipelineV2SurfaceNodeDTO]) -> String {
        InteractionToken.make(
            windowID: "w",
            title: "T",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1170),
            tree: AXPipelineV2TreeDTO(
                nodeCount: nodes.count,
                truncated: false,
                renderedText: "",
                nodes: nodes,
                lineMappings: [],
                profile: "default"
            ),
            pixelWidth: nil,
            pixelHeight: nil
        )
    }

    private func node(
        index: Int,
        parent: Int?,
        depth: Int,
        role: String,
        subrole: String?,
        children: [Int],
        frame: RectDTO,
        nodeID: String? = nil
    ) -> AXPipelineV2SurfaceNodeDTO {
        AXPipelineV2SurfaceNodeDTO(
            index: index,
            displayIndex: index,
            projectedIndex: index,
            parentIndex: parent,
            depth: depth,
            primaryCanonicalIndex: index,
            canonicalIndices: [index],
            childIndices: children,
            displayRole: role,
            rawRole: nil,
            rawSubrole: subrole,
            title: nil,
            description: nil,
            help: nil,
            identifier: nil,
            domIdentifier: nil,
            url: nil,
            nodeID: nodeID ?? "n:\(index)",
            identity: nil,
            refetch: nil,
            refetchFingerprint: "r\(index)",
            value: nil,
            valueKind: nil,
            isValueSettable: false,
            flags: [],
            secondaryActions: [],
            secondaryActionBindings: nil,
            affordances: nil,
            availableActions: nil,
            curatedSecondaryActions: nil,
            curatedAvailableActions: nil,
            parameterizedAttributes: nil,
            frameAppKit: frame,
            activationPointAppKit: nil,
            suggestedInteractionPointAppKit: nil,
            childCount: children.count,
            collectionInfo: nil,
            interactionTraits: nil,
            profileHint: nil,
            transformNotes: []
        )
    }
}

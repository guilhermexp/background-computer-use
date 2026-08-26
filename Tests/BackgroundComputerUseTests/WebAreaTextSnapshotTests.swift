import Testing
@testable import BackgroundComputerUse

@Suite
struct WebAreaTextSnapshotTests {
    @Test
    func canonicalTextIncludesOnlyWebDescendants() {
        let nodes = [
            makeNode(
                index: 0,
                title: "Uso da memória em MH Click Test: 31,3 MB",
                flags: []
            ),
            makeNode(index: 1, title: "Submit", flags: ["web_descendant"]),
            makeNode(index: 2, description: "NOT CLICKED", flags: ["web_descendant"]),
        ]

        #expect(WebAreaTextSnapshot.canonicalText(in: nodes) == "Submit\nNOT CLICKED")
    }

    @Test
    func missingWebAreaCannotEstablishTextSample() {
        let nodes = [makeNode(index: 0, title: "Browser chrome", flags: [])]

        #expect(WebAreaTextSnapshot.canonicalText(in: nodes) == nil)
    }

    @Test
    func baselineUsesTheSecondStableSampleAsTextBefore() {
        let baseline = WebAreaTextBaseline(firstSample: "Submit", secondSample: "Submit")

        #expect(baseline.baselineStable == true)
        #expect(baseline.textBefore == "Submit")
        #expect(baseline.diagnostic == nil)
    }

    @Test
    func missingSampleProducesNoBaselineEvidence() {
        let baseline = WebAreaTextBaseline(firstSample: "Submit", secondSample: nil)

        #expect(baseline.baselineStable == nil)
        #expect(baseline.textBefore == nil)
        #expect(baseline.diagnostic == WebAreaTextBaseline.missingSampleDiagnostic)
    }

    private func makeNode(
        index: Int,
        title: String? = nil,
        description: String? = nil,
        flags: [String]
    ) -> AXPipelineV2SurfaceNodeDTO {
        AXPipelineV2SurfaceNodeDTO(
            index: index,
            displayIndex: index,
            projectedIndex: index,
            parentIndex: nil,
            depth: 0,
            primaryCanonicalIndex: index,
            canonicalIndices: [index],
            childIndices: [],
            displayRole: "text",
            rawRole: "AXStaticText",
            rawSubrole: nil,
            title: title,
            description: description,
            help: nil,
            identifier: nil,
            url: nil,
            nodeID: "node-\(index)",
            identity: nil,
            refetch: nil,
            refetchFingerprint: nil,
            value: nil,
            valueKind: nil,
            isValueSettable: nil,
            flags: flags,
            secondaryActions: [],
            secondaryActionBindings: nil,
            affordances: nil,
            availableActions: nil,
            curatedSecondaryActions: nil,
            curatedAvailableActions: nil,
            parameterizedAttributes: nil,
            frameAppKit: nil,
            activationPointAppKit: nil,
            suggestedInteractionPointAppKit: nil,
            childCount: 0,
            collectionInfo: nil,
            interactionTraits: nil,
            profileHint: nil,
            transformNotes: []
        )
    }
}

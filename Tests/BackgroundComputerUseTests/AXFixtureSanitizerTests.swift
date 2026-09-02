import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct AXFixtureSanitizerTests {
    private let sentinel = "PRIVATE_FIXTURE_SENTINEL"

    @Test
    func sanitizerRedactsSensitiveStringsAndPreservesStructure() throws {
        let fixture = makeFixture()

        let sanitized = try AXFixtureSanitizer.sanitize(fixture)
        let data = try JSONSupport.encoder.encode(sanitized)
        let encoded = try #require(String(data: data, encoding: .utf8))
        let node = try #require(sanitized.rawCapture.nodes.first)
        let original = try #require(fixture.rawCapture.nodes.first)

        #expect(encoded.contains(sentinel) == false)
        #expect(encoded.contains(AXFixtureSanitizer.placeholder))
        #expect(node.role == original.role)
        #expect(node.subrole == original.subrole)
        #expect(node.frameAppKit?.x == original.frameAppKit?.x)
        #expect(node.secondaryActions == original.secondaryActions)
        #expect(node.availableActions?.map(\.rawName) == original.availableActions?.map(\.rawName))
        #expect(node.parameterizedAttributes == original.parameterizedAttributes)
        #expect(node.isValueSettable == original.isValueSettable)
        #expect(node.interactionTraits?.supportsPress == original.interactionTraits?.supportsPress)
        #expect(node.childIndices == original.childIndices)
        #expect(sanitized.rawCapture.truncated == fixture.rawCapture.truncated)
        #expect(sanitized.platformProfile.bundleID == fixture.platformProfile.bundleID)
        #expect(sanitized.scenarioID == fixture.scenarioID)
    }

    @Test
    func exporterDoesNothingWhenEnvironmentIsDisabled() throws {
        let probe = FixtureExportProbe()
        let exporter = AXFixtureExporter(
            environment: { _ in nil },
            writeFixture: probe.write
        )

        try exporter.exportIfRequested(makeFixture())

        #expect(probe.writeCount == 0)
    }

    @Test
    func exporterPassesOnlySanitizedFixtureToWriter() throws {
        let probe = FixtureExportProbe()
        let exporter = AXFixtureExporter(
            environment: { key in key == "BCU_FIXTURE_EXPORT_DIR" ? "/tmp/bcu-fixtures" : nil },
            writeFixture: probe.write
        )

        try exporter.exportIfRequested(makeFixture())
        let written = try #require(probe.fixture)
        let path = try #require(probe.path)
        let data = try JSONSupport.encoder.encode(written)
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(probe.writeCount == 1)
        #expect(path.hasPrefix("/tmp/bcu-fixtures/"))
        #expect(path.hasSuffix(".json"))
        #expect(encoded.contains(sentinel) == false)
        #expect(encoded.contains(AXFixtureSanitizer.placeholder))
    }

    @Test(arguments: ["", "relative/fixtures"])
    func exporterRejectsEmptyAndRelativeDirectories(_ directory: String) {
        let exporter = AXFixtureExporter(
            environment: { key in key == "BCU_FIXTURE_EXPORT_DIR" ? directory : nil },
            writeFixture: { _, _ in Issue.record("Writer must not run for invalid directory") }
        )

        #expect(throws: StatePipelineExperimentError.self) {
            try exporter.exportIfRequested(makeFixture())
        }
    }

    private func makeFixture() -> StatePipelineFixture {
        let action = AXActionDescriptorDTO(
            rawName: "AXPress",
            label: sentinel,
            description: sentinel,
            category: "primary",
            hiddenFromSecondaryActions: false
        )
        let traits = AXInteractionTraitsDTO(
            supportsPress: true,
            supportsOpen: false,
            supportsPick: false,
            supportsShowMenu: false,
            supportsRaise: false,
            supportsConfirm: false,
            supportsCancel: false,
            supportsIncrement: false,
            supportsDecrement: false,
            supportsScrollToVisible: false,
            supportsScrollToShowDescendant: false,
            supportsValueSet: true,
            isPotentialScrollContainer: false,
            isPotentialScrollBar: false,
            isTextEntry: true
        )
        let extraction = AXTextExtractionDTO(
            source: "fixture",
            mode: "value",
            availableModes: ["value"],
            text: sentinel,
            attributedText: sentinel,
            selectedText: sentinel,
            selectedAttributedText: sentinel,
            length: sentinel.count,
            truncated: false,
            supportsTextMarkers: true,
            supportedParameterizedAttributes: ["AXStringForRange"]
        )
        let node = AXRawNodeDTO(
            index: 0,
            parentIndex: nil,
            depth: 0,
            childIndices: [1],
            role: "AXTextField",
            subrole: "AXSearchField",
            roleDescription: sentinel,
            title: sentinel,
            placeholder: sentinel,
            description: sentinel,
            help: sentinel,
            identifier: sentinel,
            domIdentifier: sentinel,
            url: sentinel,
            valueDescription: sentinel,
            valueType: "CFString",
            enabled: true,
            selected: false,
            expanded: nil,
            isFocused: true,
            value: ValueSummaryDTO(kind: "string", preview: sentinel, length: sentinel.count, truncated: false),
            isValueSettable: true,
            secondaryActions: ["Press"],
            availableActions: [action],
            parameterizedAttributes: ["AXStringForRange"],
            frameAppKit: RectDTO(x: 10, y: 20, width: 300, height: 40),
            activationPointAppKit: PointDTO(x: 20, y: 30),
            childCount: 1,
            childSource: "AXChildren",
            collectionInfo: nil,
            identity: nil,
            relationships: nil,
            textExtraction: extraction,
            interactionTraits: traits
        )
        return StatePipelineFixture(
            generatedAt: "2026-09-02T00:00:00Z",
            scenarioID: "sanitizer-test",
            targetPID: 123,
            includeMenuBar: false,
            menuMode: AXMenuMode.none,
            maxNodes: 6500,
            window: ResolvedWindowDTO(
                windowID: "w_fixture",
                title: sentinel,
                bundleID: "com.example.fixture",
                pid: 123,
                launchDate: nil,
                windowNumber: 1,
                frameAppKit: RectDTO(x: 0, y: 0, width: 800, height: 600),
                resolutionStrategy: "fixture"
            ),
            rawCapture: AXRawCaptureResult(
                rootIndices: [0],
                nodes: [node],
                focusedCanonicalIndex: 0,
                focusSelection: AXFocusSelectionSnapshotDTO(
                    focusedCanonicalIndex: 0,
                    focusedNodeID: nil,
                    selectedCanonicalIndices: [],
                    selectedNodeIDs: [],
                    selectedText: sentinel,
                    selectedTextSource: "AXSelectedText"
                ),
                truncated: true
            ),
            platformProfile: AXPlatformProfileDTO(
                bundleID: "com.example.fixture",
                bundlePath: sentinel,
                frameworkHints: [],
                helperAppHints: [],
                isChromiumLike: false,
                isElectronLike: false,
                manualAccessibility: nil,
                enablementAttempts: nil,
                notes: [sentinel]
            ),
            menuPresentation: nil,
            notes: [sentinel]
        )
    }
}

private final class FixtureExportProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFixture: StatePipelineFixture?
    private var storedPath: String?
    private var count = 0

    var fixture: StatePipelineFixture? { lock.withLock { storedFixture } }
    var path: String? { lock.withLock { storedPath } }
    var writeCount: Int { lock.withLock { count } }

    func write(_ fixture: StatePipelineFixture, to path: String) {
        lock.withLock {
            storedFixture = fixture
            storedPath = path
            count += 1
        }
    }
}

import ApplicationServices
@testable import BackgroundComputerUse
import Testing

struct AXTextOperationPayloadTests {
    @Test
    func replacementPayloadPreservesCaseAndDisablesSmartReplace() throws {
        let marker = "marker" as CFString
        let payload = AXTextOperationPayload.replacing(
            markerRange: marker,
            text: "macOS"
        )

        #expect(payload["AXTextOperationType"] as? String == "TextOperationReplacePreserveCase")
        #expect(payload["AXTextOperationReplacementString"] as? String == "macOS")
        #expect(payload["AXTextOperationSmartReplace"] as? Bool == false)
        let ranges = try #require(payload["AXTextOperationMarkerRanges"] as? [CFTypeRef])
        #expect(ranges.count == 1)
        #expect(CFEqual(ranges[0], marker))
    }
}

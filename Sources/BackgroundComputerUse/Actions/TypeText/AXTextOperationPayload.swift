import ApplicationServices
import Foundation

enum AXTextOperationPayload {
    static func replacing(
        markerRange: CFTypeRef,
        text: String
    ) -> [String: Any] {
        [
            "AXTextOperationType": "TextOperationReplacePreserveCase",
            "AXTextOperationReplacementString": text,
            "AXTextOperationMarkerRanges": [markerRange],
            "AXTextOperationSmartReplace": false,
        ]
    }
}

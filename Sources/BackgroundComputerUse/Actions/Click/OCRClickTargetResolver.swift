import CoreGraphics
import Foundation

enum OCRClickTargetResolution: Equatable {
    case matched(OCRAnchorDTO, relocated: Bool)
    case staleInteractionToken
    case missing
    case ambiguous
}

struct OCRAnchorEvidence {
    let disappeared: Bool?
    let diagnostic: String?
}

enum OCRClickTargetResolver {
    static func anchorEvidence(
        anchor: OCRAnchorDTO,
        captureEvidence: () -> ScreenshotCaptureService.EvidenceCapture,
        recognize: (CGImage) -> OCRAnchorSummaryDTO
    ) -> OCRAnchorEvidence {
        let capture = captureEvidence()
        let summary = capture.image.map(recognize)
        return anchorEvidence(
            anchor: anchor,
            cleanPostOCR: summary,
            unavailableDiagnostic: capture.diagnostic
        )
    }

    static func anchorEvidence(
        anchor: OCRAnchorDTO,
        cleanPostOCR: OCRAnchorSummaryDTO?,
        unavailableDiagnostic: String?
    ) -> OCRAnchorEvidence {
        guard let cleanPostOCR else {
            return OCRAnchorEvidence(
                disappeared: nil,
                diagnostic: unavailableDiagnostic
                    ?? "Anchor disappearance was not computed because the clean post-click screenshot was unavailable for OCR."
            )
        }
        guard cleanPostOCR.status == .success || cleanPostOCR.status == .noText else {
            return OCRAnchorEvidence(
                disappeared: nil,
                diagnostic: "Anchor disappearance was not computed because clean post-click OCR returned status \(cleanPostOCR.status.rawValue): \(cleanPostOCR.diagnostic ?? "no diagnostic")."
            )
        }
        return OCRAnchorEvidence(
            disappeared: isAnchorPresent(anchor, in: cleanPostOCR.anchors) == false,
            diagnostic: nil
        )
    }

    static func resolve(
        requestedID: String,
        suppliedInteractionToken: String?,
        liveInteractionToken: String,
        anchors: [OCRAnchorDTO]
    ) -> OCRClickTargetResolution {
        guard suppliedInteractionToken == liveInteractionToken else {
            return .staleInteractionToken
        }
        if let exact = anchors.first(where: { $0.id == requestedID }) {
            return .matched(exact, relocated: false)
        }
        guard let identity = identity(from: requestedID) else {
            return .missing
        }

        let candidates = anchors.filter { anchor in
            anchor.occurrence == identity.occurrence &&
                normalized(anchor.text) == identity.text &&
                isNear(anchor.box, identity.box)
        }
        guard candidates.count <= 1 else {
            return .ambiguous
        }
        guard let candidate = candidates.first else {
            return .missing
        }
        return .matched(candidate, relocated: true)
    }

    static func isAnchorPresent(_ anchor: OCRAnchorDTO, in anchors: [OCRAnchorDTO]) -> Bool {
        anchors.contains {
            normalized($0.text) == normalized(anchor.text) &&
                $0.occurrence == anchor.occurrence &&
                isNear($0.box, anchor.box)
        }
    }

    private struct Identity {
        let occurrence: Int
        let text: String
        let box: OCRBoxDTO
    }

    private static func identity(from id: String) -> Identity? {
        guard id.hasPrefix("ocr_") else { return nil }
        let components = id.dropFirst(4).split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              let occurrence = Int(components[0]),
              let text = decodeText(String(components[1])) else {
            return nil
        }
        let boxValues = components[2].split(separator: ",").compactMap { Double($0).map { $0 * 4 } }
        guard boxValues.count == 4 else { return nil }
        return Identity(
            occurrence: occurrence,
            text: text,
            box: OCRBoxDTO(x: boxValues[0], y: boxValues[1], width: boxValues[2], height: boxValues[3])
        )
    }

    private static func decodeText(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func isNear(_ lhs: OCRBoxDTO, _ rhs: OCRBoxDTO) -> Bool {
        let lhsCenter = CGPoint(x: lhs.x + lhs.width / 2, y: lhs.y + lhs.height / 2)
        let rhsCenter = CGPoint(x: rhs.x + rhs.width / 2, y: rhs.y + rhs.height / 2)
        let distance = hypot(lhsCenter.x - rhsCenter.x, lhsCenter.y - rhsCenter.y)
        let tolerance = max(24, hypot(rhs.width, rhs.height) * 0.5)
        return distance <= tolerance
    }
}

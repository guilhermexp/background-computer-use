import CryptoKit
import Foundation

public struct OCRBoxDTO: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct OCRLineDTO: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Double
    public let box: OCRBoxDTO

    public init(text: String, confidence: Double, box: OCRBoxDTO) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }

    var centerX: Double {
        box.x + box.width / 2
    }

    var centerY: Double {
        box.y + box.height / 2
    }
}

public enum OCRRecognitionStatusDTO: String, Codable, Equatable, Sendable {
    case success
    case noText = "no_text"
    case imageUnavailable = "image_unavailable"
    case recognitionFailed = "recognition_failed"
}

public struct OCRAnchorDTO: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let occurrence: Int
    public let x: Int
    public let y: Int
    public let confidence: Double
    public let box: OCRBoxDTO
    public let target: ActionTargetRequestDTO
}

public struct OCRAnchorSummaryDTO: Codable, Equatable, Sendable {
    public let status: OCRRecognitionStatusDTO
    public let diagnostic: String?
    public let promptHint: String
    public let anchors: [OCRAnchorDTO]
    public let matchesCount: Int
}

enum OCRAnchorSummaryBuilder {
    static func summary(
        lines: [OCRLineDTO],
        interactionToken: String,
        maxAnchors: Int = 24
    ) -> OCRAnchorSummaryDTO {
        var occurrences: [String: Int] = [:]
        let anchors = lines
            .filter { useful($0) }
            .sorted { lhs, rhs in
                if abs(lhs.box.y - rhs.box.y) > 8 {
                    return lhs.box.y < rhs.box.y
                }
                return lhs.box.x < rhs.box.x
            }
            .prefix(max(0, maxAnchors))
            .map { line -> OCRAnchorDTO in
                let normalizedText = normalized(line.text)
                let occurrence = occurrences[normalizedText, default: 0] + 1
                occurrences[normalizedText] = occurrence
                let id = anchorID(
                    text: normalizedText,
                    occurrence: occurrence,
                    box: line.box,
                    interactionToken: interactionToken
                )
                return OCRAnchorDTO(
                    id: id,
                    text: line.text,
                    occurrence: occurrence,
                    x: Int(line.centerX.rounded()),
                    y: Int(line.centerY.rounded()),
                    confidence: line.confidence,
                    box: line.box,
                    target: .generatedOCRAnchor(id)
                )
            }

        let prompt = anchors
            .map { "\"\($0.text)\" at (\($0.x), \($0.y)) target \($0.id)" }
            .joined(separator: "; ")
        return OCRAnchorSummaryDTO(
            status: anchors.isEmpty ? .noText : .success,
            diagnostic: nil,
            promptHint: anchors.isEmpty
                ? "OCR found no actionable text in this image."
                : "OCR anchors: \(prompt). Prefer each anchor's target for clicks.",
            anchors: anchors,
            matchesCount: lines.count
        )
    }

    static func failure(
        status: OCRRecognitionStatusDTO,
        diagnostic: String
    ) -> OCRAnchorSummaryDTO {
        precondition(status != .success && status != .noText)
        return OCRAnchorSummaryDTO(
            status: status,
            diagnostic: diagnostic,
            promptHint: diagnostic,
            anchors: [],
            matchesCount: 0
        )
    }

    private static func anchorID(
        text: String,
        occurrence: Int,
        box: OCRBoxDTO,
        interactionToken: String
    ) -> String {
        let quantizedBox = [box.x, box.y, box.width, box.height]
            .map { Int(($0 / 4).rounded()) }
            .map(String.init)
            .joined(separator: ",")
        let payload = "\(interactionToken)|\(text)|\(occurrence)|\(quantizedBox)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let encodedText = Data(text.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let hash = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
        return "ocr_\(occurrence).\(encodedText).\(quantizedBox).\(hash)"
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func useful(_ line: OCRLineDTO) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 2 &&
            line.confidence >= 0.5 &&
            line.box.width >= 8 &&
            line.box.height >= 8
    }
}

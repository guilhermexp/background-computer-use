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

public struct OCRAnchorDTO: Codable, Equatable, Sendable {
    public let text: String
    public let x: Int
    public let y: Int
    public let confidence: Double
}

public struct OCRAnchorSummaryDTO: Codable, Equatable, Sendable {
    public let promptHint: String
    public let anchors: [OCRAnchorDTO]
    public let matchesCount: Int
}

enum OCRAnchorSummaryBuilder {
    static func summary(
        lines: [OCRLineDTO],
        maxAnchors: Int = 8
    ) -> OCRAnchorSummaryDTO? {
        let anchors = lines
            .filter { useful($0) }
            .sorted { lhs, rhs in
                if abs(lhs.box.y - rhs.box.y) > 8 {
                    return lhs.box.y < rhs.box.y
                }
                return lhs.box.x < rhs.box.x
            }
            .prefix(max(0, maxAnchors))
            .map {
                OCRAnchorDTO(
                    text: $0.text,
                    x: Int($0.centerX.rounded()),
                    y: Int($0.centerY.rounded()),
                    confidence: $0.confidence
                )
            }

        guard anchors.isEmpty == false else {
            return nil
        }

        let prompt = anchors
            .map { "\"\($0.text)\" at (\($0.x), \($0.y))" }
            .joined(separator: "; ")
        return OCRAnchorSummaryDTO(
            promptHint: "OCR anchors: \(prompt). Use these local coordinates from this image.",
            anchors: anchors,
            matchesCount: lines.count
        )
    }

    private static func useful(_ line: OCRLineDTO) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 2 &&
            line.confidence >= 0.5 &&
            line.box.width >= 8 &&
            line.box.height >= 8
    }
}

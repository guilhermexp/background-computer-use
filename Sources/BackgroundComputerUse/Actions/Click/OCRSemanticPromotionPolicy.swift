import Foundation

enum OCRSemanticPromotionPolicy {
    static func labelsMatch(anchor: String, candidate: String?) -> Bool {
        guard let candidate else { return false }
        let normalizedAnchor = normalize(anchor)
        let normalizedCandidate = normalize(candidate)
        guard normalizedAnchor.isEmpty == false, normalizedCandidate.isEmpty == false else { return false }
        return normalizedAnchor == normalizedCandidate
            || normalizedAnchor.contains(normalizedCandidate)
            || normalizedCandidate.contains(normalizedAnchor)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

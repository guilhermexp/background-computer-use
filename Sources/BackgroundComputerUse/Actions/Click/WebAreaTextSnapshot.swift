import Foundation

enum WebAreaTextSnapshot {
    private static let webDescendantFlag = "web_descendant"

    static func canonicalText(in nodes: [AXPipelineV2SurfaceNodeDTO]) -> String? {
        let webNodes = nodes.filter { $0.flags.contains(webDescendantFlag) }
        guard webNodes.isEmpty == false else {
            return nil
        }

        return webNodes
            .flatMap { node in
                [node.title, node.description, node.help, node.value?.preview]
                    .compactMap(canonicalFragment)
            }
            .joined(separator: "\n")
    }

    private static func canonicalFragment(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let canonical = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return canonical.isEmpty ? nil : canonical
    }
}

struct WebAreaTextBaseline: Equatable {
    static let missingSampleDiagnostic = "The web-area text was unavailable in at least one pre-dispatch capture, so a stable baseline could not be established."

    let baselineStable: Bool?
    let textBefore: String?
    let diagnostic: String?

    init(firstSample: String?, secondSample: String?) {
        guard let firstSample, let secondSample else {
            baselineStable = nil
            textBefore = nil
            diagnostic = Self.missingSampleDiagnostic
            return
        }
        baselineStable = firstSample == secondSample
        textBefore = secondSample
        diagnostic = nil
    }

    init(unavailableDiagnostic: String) {
        baselineStable = nil
        textBefore = nil
        diagnostic = unavailableDiagnostic
    }

    private init(baselineStable: Bool?, textBefore: String?, diagnostic: String?) {
        self.baselineStable = baselineStable
        self.textBefore = textBefore
        self.diagnostic = diagnostic
    }

    static let notApplicable = WebAreaTextBaseline(
        baselineStable: nil,
        textBefore: nil,
        diagnostic: nil
    )
}

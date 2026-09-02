import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct DocumentationExamplesTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct RequestExample {
        let routeID: RouteID
        let body: [String: Any]
        let source: String
    }

    private struct ScanError: Error, CustomStringConvertible {
        let description: String
    }

    @Test
    func parserAssociatesNearbyRoutesAndIgnoresContextFreeObjects() throws {
        let source = #"""
        POST /v1/click
        ```json
        {"window":"w","x":1,"y":2}
        ```

        curl -s -X POST "$BASE/v1/list_windows" \
          -H 'content-type: application/json' \
          -d '{"pid":123}'

        ```json
        {"id":"agent","name":"Agent","color":"#0095A1"}
        ```
        """#

        let examples = try Self.requestExamples(in: source, source: "synthetic")

        #expect(examples.count == 2)
        #expect(examples.map(\.routeID) == [.click, .listWindows])
        #expect(examples[0].source == "synthetic:2")
        #expect(examples[1].source == "synthetic:8")
    }

    @Test
    func repositoryRequestExamplesMatchRegistrySchemas() throws {
        let paths = [
            Self.repositoryRoot.appendingPathComponent("README.md"),
            Self.repositoryRoot.appendingPathComponent("skills/background-computer-use/SKILL.md"),
        ]
        let examples = try paths.flatMap { url in
            try Self.requestExamples(
                in: String(contentsOf: url, encoding: .utf8),
                source: url.path
            )
        }

        #expect(examples.count >= 7, "Documentation parser found too few route-bound request bodies")
        let requiredRoutes: Set<RouteID> = [
            .listApps,
            .listWindows,
            .getWindowState,
            .click,
            .typeText,
            .cursorFeedback,
        ]
        #expect(requiredRoutes.isSubset(of: Set(examples.map(\.routeID))))

        for example in examples {
            let keys = Set(example.body.keys)
            let accepted = Set(RouteRegistry.requestFieldNames(for: example.routeID))
            let required = Set(RouteRegistry.requiredRequestFieldNames(for: example.routeID))
            let unknown = keys.subtracting(accepted).sorted()
            let missing = required.subtracting(keys).sorted()
            #expect(unknown.isEmpty, "\(example.source): unknown top-level request fields \(unknown)")
            #expect(missing.isEmpty, "\(example.source): missing required request fields \(missing)")
        }
    }

    @Test
    func readmeCoreRouteInventoryExactlyMatchesRegistry() throws {
        let url = Self.repositoryRoot.appendingPathComponent("README.md")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
        let heading = try #require(lines.firstIndex(of: "Core routes:"))
        var actual: [String] = []
        for line in lines[(heading + 1)...] {
            if line.hasPrefix("## ") {
                break
            }
            guard line.hasPrefix("- `") else {
                continue
            }
            let fields = line.split(separator: "`", omittingEmptySubsequences: false)
            guard fields.count >= 3 else {
                continue
            }
            actual.append(String(fields[1]))
        }
        let expected = RouteRegistry.descriptors.map { "\($0.method) \($0.path)" }

        #expect(Set(actual) == Set(expected), "Inventory difference: actual=\(Set(actual)) expected=\(Set(expected))")
        #expect(actual.count == expected.count, "Inventory contains a missing or duplicate route")
    }

    private static func requestExamples(in content: String, source: String) throws -> [RequestExample] {
        let lines = content.components(separatedBy: .newlines)
        let routes = RouteRegistry.descriptors.compactMap { descriptor -> (path: String, routeID: RouteID)? in
            guard let routeID = RouteID(rawValue: descriptor.id) else { return nil }
            return (descriptor.path, routeID)
        }
        var examples: [RequestExample] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line == "```json" {
                let openingLine = index + 1
                guard let closing = lines[openingLine...].firstIndex(of: "```") else {
                    throw scanError(source: source, line: openingLine, message: "unterminated JSON fence")
                }
                let jsonText = lines[openingLine..<closing].joined(separator: "\n")
                let body = try parseObject(jsonText, source: source, line: openingLine)
                if let routeID = routeNear(lines: lines, index: index, lookback: 3, routes: routes) {
                    examples.append(RequestExample(routeID: routeID, body: body, source: "\(source):\(openingLine)"))
                }
                index = closing + 1
                continue
            }

            if let marker = line.range(of: "-d '") {
                let bodyStart = marker.upperBound
                guard let bodyEnd = line[bodyStart...].firstIndex(of: "'") else {
                    throw scanError(source: source, line: index + 1, message: "unterminated curl JSON body")
                }
                guard let routeID = routeNear(lines: lines, index: index, lookback: 6, routes: routes) else {
                    throw scanError(source: source, line: index + 1, message: "curl JSON body has no nearby route")
                }
                let body = try parseObject(String(line[bodyStart..<bodyEnd]), source: source, line: index + 1)
                examples.append(RequestExample(routeID: routeID, body: body, source: "\(source):\(index + 1)"))
            }
            index += 1
        }
        return examples
    }

    private static func routeNear(
        lines: [String],
        index: Int,
        lookback: Int,
        routes: [(path: String, routeID: RouteID)]
    ) -> RouteID? {
        let lowerBound = max(0, index - lookback)
        for candidateIndex in stride(from: index, through: lowerBound, by: -1) {
            for route in routes where lines[candidateIndex].contains(route.path) {
                return route.routeID
            }
        }
        return nil
    }

    private static func parseObject(_ text: String, source: String, line: Int) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            throw scanError(source: source, line: line, message: "invalid JSON: \(error)")
        }
        guard let body = object as? [String: Any] else {
            throw scanError(source: source, line: line, message: "request JSON is not an object")
        }
        return body
    }

    private static func scanError(source: String, line: Int, message: String) -> ScanError {
        ScanError(description: "\(source):\(line): \(message)")
    }
}

import Foundation

enum AXFixtureSanitizer {
    static let placeholder = "<redacted>"

    private static let sensitiveKeys: Set<String> = [
        "roleDescription",
        "title",
        "placeholder",
        "description",
        "help",
        "identifier",
        "domIdentifier",
        "url",
        "urlHost",
        "value",
        "valueDescription",
        "preview",
        "valuePreview",
        "text",
        "attributedText",
        "selectedText",
        "selectedAttributedText",
        "label",
        "sourceTitle",
        "sourceURL",
        "bundlePath",
        "activeTopLevelTitle",
        "activePathTitles",
        "pathTitles",
        "notes",
        "note",
        "warnings",
        "metadata",
    ]

    static func sanitize(_ fixture: StatePipelineFixture) throws -> StatePipelineFixture {
        let data = try JSONSupport.encoder.encode(fixture)
        let object = try JSONSerialization.jsonObject(with: data)
        let sanitized = sanitize(object, key: nil)
        let sanitizedData = try JSONSerialization.data(withJSONObject: sanitized)
        return try JSONSupport.decoder.decode(StatePipelineFixture.self, from: sanitizedData)
    }

    private static func isSensitive(_ key: String?) -> Bool {
        guard let key else { return false }
        return sensitiveKeys.contains(key)
    }

    private static func sanitize(_ value: Any, key: String?) -> Any {
        if let string = value as? String {
            return isSensitive(key) ? placeholder : string
        }
        if let array = value as? [Any] {
            let redactMembers = isSensitive(key)
            return array.map { member -> Any in
                if redactMembers, member is String {
                    return placeholder
                }
                return sanitize(member, key: nil)
            }
        }
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            sanitized.reserveCapacity(dictionary.count)
            for (childKey, child) in dictionary {
                sanitized[childKey] = sanitize(child, key: childKey)
            }
            return sanitized
        }
        return value
    }
}

struct AXFixtureExporter {
    typealias EnvironmentLookup = @Sendable (String) -> String?
    typealias FixtureWriter = @Sendable (StatePipelineFixture, String) throws -> Void

    private let environment: EnvironmentLookup
    private let writeFixture: FixtureWriter

    init(
        environment: @escaping EnvironmentLookup = { ProcessInfo.processInfo.environment[$0] },
        writeFixture: @escaping FixtureWriter = { fixture, path in
            try StatePipelineExperiment().saveFixture(fixture, to: path)
        }
    ) {
        self.environment = environment
        self.writeFixture = writeFixture
    }

    func exportIfRequested(_ fixture: StatePipelineFixture) throws {
        guard let directory = environment("BCU_FIXTURE_EXPORT_DIR") else { return }
        guard !directory.isEmpty, NSString(string: directory).isAbsolutePath else {
            throw StatePipelineExperimentError.invalidFixtureExportDirectory(directory)
        }
        let sanitized = try AXFixtureSanitizer.sanitize(fixture)
        let path = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased() + ".json")
            .path
        try writeFixture(sanitized, path)
    }
}

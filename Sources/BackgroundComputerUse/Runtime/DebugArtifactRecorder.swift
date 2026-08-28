import Foundation

struct DebugArtifactPaths: Sendable {
    let directory: URL
    let requestPath: URL
    let responsePath: URL
    let metadataPath: URL
}

struct DebugArtifactRecorder: Sendable {
    let rootDirectory: URL
    let enabled: Bool
    let rawArtifactsEnabled: Bool

    init(
        rootDirectory: URL = DebugArtifactRecorder.defaultRootDirectory(),
        enabled: Bool = DebugArtifactRecorder.isEnabledByEnvironment(),
        rawArtifactsEnabled: Bool = ProcessInfo.processInfo.environment["DEBUG_ARTIFACTS_RAW"] == "1"
    ) {
        self.rootDirectory = rootDirectory
        self.enabled = enabled
        self.rawArtifactsEnabled = rawArtifactsEnabled
    }

    func record(
        requestID: String,
        routeID: String,
        requestBody: Data,
        responseBody: Data
    ) throws -> DebugArtifactPaths {
        let directory = rootDirectory.appendingPathComponent(safeFileComponent(requestID), isDirectory: true)
        let requestPath = directory.appendingPathComponent("request.json")
        let responsePath = directory.appendingPathComponent("response.json")
        let metadataPath = directory.appendingPathComponent("metadata.json")

        guard enabled else {
            return DebugArtifactPaths(
                directory: directory,
                requestPath: requestPath,
                responsePath: responsePath,
                metadataPath: metadataPath
            )
        }

        try SecureFileWriter.prepareDirectory(rootDirectory)
        try SecureFileWriter.prepareDirectory(directory)
        try SecureFileWriter.write(
            redactedRequestBody(requestBody, routeID: routeID),
            to: requestPath
        )
        try SecureFileWriter.write(
            redactedResponseBody(responseBody, routeID: routeID),
            to: responsePath
        )

        let metadata: [String: String] = [
            "requestID": requestID,
            "routeID": routeID,
            "recordedAt": Time.iso8601String(from: Date()),
        ]
        try SecureFileWriter.write(JSONSupport.encoder.encode(metadata), to: metadataPath)

        return DebugArtifactPaths(
            directory: directory,
            requestPath: requestPath,
            responsePath: responsePath,
            metadataPath: metadataPath
        )
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("background-computer-use", isDirectory: true)
            .appendingPathComponent("debug-artifacts", isDirectory: true)
    }

    static func isEnabledByEnvironment() -> Bool {
        let value = ProcessInfo.processInfo.environment["BACKGROUND_COMPUTER_USE_DEBUG_ARTIFACTS"]?
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private func normalizedJSON(_ data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return data
        }
        return normalized
    }

    private func redactedRequestBody(_ data: Data, routeID: String) -> Data {
        guard rawArtifactsEnabled == false else {
            return normalizedJSON(data)
        }
        let sensitiveKeys = sensitiveRequestKeys(routeID: routeID)
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            guard sensitiveKeys.isEmpty else {
                return normalizedJSON([
                    "body": "<redacted malformed request body len=\(data.count)>",
                ])
            }
            return normalizedJSON(data)
        }

        for key in sensitiveKeys {
            if let value = object[key] as? String {
                object[key] = redaction(for: value)
            }
        }
        return normalizedJSON(object)
    }

    private func sensitiveRequestKeys(routeID: String) -> Set<String> {
        switch routeID {
        case RouteID.typeText.rawValue, RouteID.selectText.rawValue:
            return ["text"]
        case RouteID.paste.rawValue:
            return ["content"]
        case RouteID.setValue.rawValue:
            return ["value"]
        case RouteID.pressKey.rawValue:
            return ["key"]
        default:
            return []
        }
    }

    private func redactedResponseBody(_ data: Data, routeID: String) -> Data {
        guard rawArtifactsEnabled == false,
              routeID == RouteID.readText.rawValue,
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return normalizedJSON(data)
        }
        return normalizedJSON(redactingTextFields(in: object))
    }

    private func redactingTextFields(in value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { key, nestedValue in
                if key == "text", let text = nestedValue as? String {
                    return (key, redaction(for: text) as Any)
                }
                return (key, redactingTextFields(in: nestedValue))
            })
        }
        if let array = value as? [Any] {
            return array.map(redactingTextFields)
        }
        return value
    }

    private func redaction(for value: String) -> String {
        "<redacted len=\(value.count)>"
    }

    private func normalizedJSON(_ object: Any) -> Data {
        guard let normalized = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Data()
        }
        return normalized
    }

    private func safeFileComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        .map(String.init)
        .joined()
    }
}

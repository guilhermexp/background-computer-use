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

    init(
        rootDirectory: URL = DebugArtifactRecorder.defaultRootDirectory(),
        enabled: Bool = DebugArtifactRecorder.isEnabledByEnvironment()
    ) {
        self.rootDirectory = rootDirectory
        self.enabled = enabled
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

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try normalizedJSON(requestBody).write(to: requestPath, options: .atomic)
        try normalizedJSON(responseBody).write(to: responsePath, options: .atomic)

        let metadata: [String: String] = [
            "requestID": requestID,
            "routeID": routeID,
            "recordedAt": Time.iso8601String(from: Date()),
        ]
        try JSONSupport.encoder.encode(metadata).write(to: metadataPath, options: .atomic)

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
              let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return data
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

import Foundation
import Network
import Testing
@testable import BackgroundComputerUse

@Suite(.serialized)
struct LoopbackServerIntegrationTests {
    @Test
    func realLoopbackCoversAuthStreamingEOFAndLimits() async throws {
        let server = LoopbackServer(auth: RuntimeAuth(token: "integration-token"))
        let baseURL = try await server.start()
        defer { server.stop() }

        let (healthData, healthResponse) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("health"))
        #expect((healthResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(healthData.isEmpty == false)

        var unauthorized = URLRequest(url: baseURL.appendingPathComponent("v1/routes"))
        unauthorized.httpMethod = "GET"
        let (_, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorized)
        #expect((unauthorizedResponse as? HTTPURLResponse)?.statusCode == 401)

        var authorized = unauthorized
        authorized.setValue("integration-token", forHTTPHeaderField: RuntimeAuth.headerName)
        let (_, authorizedResponse) = try await URLSession.shared.data(for: authorized)
        #expect((authorizedResponse as? HTTPURLResponse)?.statusCode == 200)

        let port = try #require(baseURL.port)
        let splitHeaders = rawRequest([
            "POST /v1/list_apps HTTP/1.1",
            "Host: 127.0.0.1",
            "Content-Type: application/json",
            "Content-Length: 2",
            "\(RuntimeAuth.headerName): integration-token",
            "Connection: close",
        ])
        #expect(parsesAsCompleteRequest(splitHeaders + "{}"))
        let split = try RawLoopbackHTTPClient.exchange(
            port: port,
            chunks: [Data(splitHeaders.utf8), Data("{}".utf8)]
        )
        #expect(split.statusCode == 200, Comment(rawValue: split.body))
        #expect(split.signalsConnectionClose)
        #expect(split.closed)

        let prematureRequest = rawRequest([
            "POST /v1/list_apps HTTP/1.1",
            "Host: localhost",
            "Content-Type: application/json",
            "Content-Length: 10",
        ]) + "{}"
        let premature = try RawLoopbackHTTPClient.exchange(
            port: port,
            chunks: [Data(prematureRequest.utf8)],
            endOfStream: true
        )
        #expect(premature.statusCode == 400)
        #expect(premature.signalsConnectionClose)

        let malformedRequest = rawRequest([
            "GET /health HTTP/1.1",
            "MalformedHeader",
        ])
        let malformed = try RawLoopbackHTTPClient.exchange(
            port: port,
            chunks: [Data(malformedRequest.utf8)]
        )
        #expect(malformed.statusCode == 400)
        #expect(malformed.signalsConnectionClose)

        let oversizedRequest = rawRequest([
            "POST /v1/list_apps HTTP/1.1",
            "Host: localhost",
            "Content-Type: application/json",
            "Content-Length: 10485761",
        ])
        let oversized = try RawLoopbackHTTPClient.exchange(
            port: port,
            chunks: [Data(oversizedRequest.utf8)]
        )
        #expect(oversized.statusCode == 413)
        #expect(oversized.signalsConnectionClose)
    }
}

private struct RawHTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let closed: Bool
    let body: String

    var signalsConnectionClose: Bool {
        headers["connection"]?.lowercased() == "close"
    }
}

private enum RawLoopbackHTTPClient {
    static func exchange(port: Int, chunks: [Data], endOfStream: Bool = false) throws -> RawHTTPResponse {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: try #require(NWEndpoint.Port(rawValue: UInt16(port))),
            using: .tcp
        )
        let queue = DispatchQueue(label: "LoopbackServerIntegrationTests.client")
        let ready = DispatchSemaphore(value: 0)
        let collector = RawResponseCollector()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            connection.cancel()
            throw RawHTTPClientError.timeout("connection readiness")
        }

        collector.receive(from: connection)
        for chunk in chunks {
            try write(chunk, context: .defaultMessage, on: connection, collector: collector, stage: "request send")
        }
        if endOfStream {
            try write(nil, context: .finalMessage, on: connection, collector: collector, stage: "request finalization")
        }
        guard collector.finished.wait(timeout: .now() + 10) == .success else {
            connection.cancel()
            throw RawHTTPClientError.timeout("response close after \(chunks.count) write(s): \(String(decoding: chunks[0].prefix(32), as: UTF8.self))")
        }
        connection.cancel()
        return try collector.response()
    }

    private static func write(
        _ content: Data?,
        context: NWConnection.ContentContext,
        on connection: NWConnection,
        collector: RawResponseCollector,
        stage: String
    ) throws {
        let completed = DispatchSemaphore(value: 0)
        connection.send(
            content: content,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                collector.record(error: error)
                completed.signal()
            }
        )
        guard completed.wait(timeout: .now() + 5) == .success else {
            connection.cancel()
            throw RawHTTPClientError.timeout(stage)
        }
    }
}

private final class RawResponseCollector: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var closed = false
    private var error: Error?

    func record(error: Error?) {
        guard let error else { return }
        lock.withLock { self.error = error }
    }

    func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] chunk, _, complete, error in
            lock.withLock {
                if let chunk { data.append(chunk) }
                if let error { self.error = error }
                closed = complete
            }
            if complete || error != nil {
                finished.signal()
            } else {
                receive(from: connection)
            }
        }
    }

    func response() throws -> RawHTTPResponse {
        let (payload, closed, failure) = lock.withLock { (self.data, self.closed, self.error) }
        if let failure {
            throw failure
        }
        let text = try #require(String(data: payload, encoding: .utf8))
        let responseParts = text.components(separatedBy: "\r\n\r\n")
        let body = responseParts.dropFirst().joined(separator: "\r\n\r\n")
        let lines = responseParts[0].components(separatedBy: "\r\n")
        let statusComponents = try #require(lines.first).split(separator: " ")
        let statusCode = try #require(statusComponents.dropFirst().first.flatMap { Int($0) })
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            headers[String(pieces[0]).lowercased()] = pieces[1].trimmingCharacters(in: .whitespaces)
        }
        return RawHTTPResponse(statusCode: statusCode, headers: headers, closed: closed, body: body)
    }
}

private enum RawHTTPClientError: Error {
    case timeout(String)
}

private func rawRequest(_ headerLines: [String]) -> String {
    (headerLines + ["", ""]).joined(separator: "\r\n")
}

private func parsesAsCompleteRequest(_ raw: String) -> Bool {
    if case .complete = HTTPRequest.parse(Data(raw.utf8)) {
        return true
    }
    return false
}

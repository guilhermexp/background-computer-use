import Foundation
import Security

struct RuntimeAuth: Sendable {
    static let headerName = "X-Background-Computer-Use-Token"

    let token: String?

    static let disabled = RuntimeAuth(token: nil)

    static func generateRequired() throws -> RuntimeAuth {
        RuntimeAuth(token: try RuntimeAuthToken.generate())
    }

    var isRequired: Bool {
        token != nil
    }

    func isAuthorized(request: HTTPRequest) -> Bool {
        guard let token else {
            return true
        }

        guard let suppliedToken = request.headerValue(named: Self.headerName) else {
            return false
        }
        return Self.constantTimeEqual(suppliedToken, token)
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = [UInt8](lhs.utf8)
        let rhsBytes = [UInt8](rhs.utf8)
        let byteCount = max(lhsBytes.count, rhsBytes.count)
        var difference = lhsBytes.count ^ rhsBytes.count

        for index in 0..<byteCount {
            let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
            let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(lhsByte ^ rhsByte)
        }
        return difference == 0
    }

    var dto: RuntimeAuthDTO {
        RuntimeAuthDTO(
            required: isRequired,
            headerName: Self.headerName
        )
    }
}

enum RuntimeAuthToken {
    static func generate(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw RuntimeAuthTokenError.generationFailed(status)
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum RuntimeAuthTokenError: Error, CustomStringConvertible {
    case generationFailed(OSStatus)

    var description: String {
        switch self {
        case .generationFailed(let status):
            return "Failed to generate runtime auth token: SecRandomCopyBytes status \(status)."
        }
    }
}
